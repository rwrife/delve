extends SceneTree

var failures: Array[String] = []
var save_path = ""
var export_path = ""


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _run() -> void:
	save_path = "user://delve-ui-test-%s.json" % OS.get_process_id()
	export_path = "user://delve-ui-test-%s-backup.json" % OS.get_process_id()
	var scene = load("res://godot/main.tscn")
	var app = scene.instantiate()
	app.save_path_override = save_path
	root.add_child(app)
	await process_frame
	check(app.game.ready and app.screen == "home", "home screen loads")
	app._request_new()
	await process_frame
	check(app.screen == "explore" and app.game.world.room == "entrance", "new button starts exploration")
	check(app.move_buttons.size() == 1, "entrance exposes its exit")
	app.move_buttons[0].pressed.emit()
	await process_frame
	check(app.game.world.room == "brazier-hall", "exit button moves the explorer")
	app._open_journal()
	app._navigate("notes")
	app._edit_note("entrance")
	await process_frame
	app.note_editor.text = "A remembered clue"
	app._save_note()
	check(app.game.active_run().notes.entrance == "A remembered clue", "note editor saves")
	app._navigate("quests")
	app._mark_goal(true, "silence")
	check(app.game.active_run().markedGoals.has("silence"), "quest control saves a player mark")
	app._navigate("record")
	check(app.game.current_record().steps == 2, "record screen uses ledger facts")
	app._navigate("explore")
	app._toggle_pause()
	var room = app.game.world.room
	app._visit("sealed-vault")
	check(app.game.world.room == room, "paused exploration ignores movement")
	app._toggle_pause()
	app._open_data()
	app._set_confirm(false)
	check(not app.game.archive.settings.confirmNewRun, "settings control persists")
	app.file_operation = "backup"
	app._file_selected(export_path)
	check(FileAccess.file_exists(export_path), "data screen exports a backup")
	app._navigate("explore")
	app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.paused, "losing focus pauses exploration")
	app._return_to_entrance()
	check(app.screen == "home" and app.game.active_run() != null, "pause can return to entrance without ending the run")
	app._resume()
	check(app.screen == "explore" and app.game.current_record().sessions == "2", "resume records another session")
	app._act("retreat", "")
	check(app.screen == "home" and app.game.active_run() == null, "retreat shows the ending")
	await process_frame
	if "--visual" in OS.get_cmdline_user_args():
		app._request_new()
		app._visit("brazier-hall")
		await create_timer(8.0).timeout
	app.queue_free()
	await process_frame
	for path in [save_path, save_path + ".tmp", export_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures.is_empty():
		print("All Godot UI tests passed.")
		quit(0)
	else:
		printerr("%d Godot UI test(s) failed." % failures.size())
		quit(1)
