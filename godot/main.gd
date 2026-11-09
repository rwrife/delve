extends Control

const Game = preload("res://godot/delve_game.gd")
const RoomView = preload("res://godot/room_view.gd")
const TEXT = Color("#eee8d8")
const MUTED = Color("#b8b2a5")
const ACCENT = Color("#e0c58c")
const ERROR = Color("#ff9d8e")

var game = Game.new()
var save_path_override = ""
var screen = "home"
var return_screen = "home"
var paused = false
var note_room = ""
var note_editor: TextEdit
var status = ""
var status_label: Label
var body: VBoxContainer
var main_panel: Control
var move_buttons: Array[Button] = []
var file_dialog: FileDialog
var new_dialog: ConfirmationDialog
var restore_dialog: ConfirmationDialog
var file_operation = ""


func _ready() -> void:
	theme = _make_theme()
	_setup_dialogs()
	var path = save_path_override if not save_path_override.is_empty() else "user://delve.json"
	game.initialize(path)
	_rebuild()


func _make_theme() -> Theme:
	var result = Theme.new()
	result.default_font_size = 18
	result.set_color("font_color", "Label", TEXT)
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_focus_color", "Button", Color.WHITE)
	result.set_color("font_disabled_color", "Button", Color("#817e77"))
	result.set_color("font_color", "CheckBox", TEXT)
	result.set_color("font_color", "TextEdit", TEXT)
	result.set_color("caret_color", "TextEdit", ACCENT)
	result.set_stylebox("normal", "Button", _style(Color("#303b3c"), Color("#58635d")))
	result.set_stylebox("hover", "Button", _style(Color("#43534e"), ACCENT))
	result.set_stylebox("pressed", "Button", _style(Color("#596952"), ACCENT))
	result.set_stylebox("focus", "Button", _style(Color(0, 0, 0, 0), Color("#ffe4a8"), 2))
	result.set_stylebox("disabled", "Button", _style(Color("#242b2a"), Color("#414641")))
	result.set_stylebox("normal", "TextEdit", _style(Color("#202a2a"), Color("#69766b")))
	result.set_stylebox("focus", "TextEdit", _style(Color("#202a2a"), ACCENT))
	return result


func _style(background: Color, border: Color, width = 1) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(7)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


func _setup_dialogs() -> void:
	new_dialog = ConfirmationDialog.new()
	new_dialog.title = "Start a new delve?"
	new_dialog.dialog_text = "Your previous run will remain in backup history, but the new delve becomes the active run."
	new_dialog.ok_button_text = "Start new delve"
	new_dialog.confirmed.connect(_start_new)
	add_child(new_dialog)

	restore_dialog = ConfirmationDialog.new()
	restore_dialog.title = "Replace all local data?"
	restore_dialog.ok_button_text = "Replace local data"
	restore_dialog.confirmed.connect(_restore)
	add_child(restore_dialog)

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_selected.connect(_file_selected)
	add_child(file_dialog)


func _rebuild() -> void:
	if is_instance_valid(main_panel):
		main_panel.queue_free()
	move_buttons.clear()
	main_panel = Control.new()
	main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_panel)

	var background = ColorRect.new()
	background.color = Color("#141d20")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_panel.add_child(background)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	main_panel.add_child(margin)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var header = HBoxContainer.new()
	column.add_child(header)
	var brand = _label("DELVE", 22, ACCENT)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	var section = _label(_screen_title(), 16, MUTED)
	section.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(section)
	column.add_child(HSeparator.new())
	status_label = _label("", 16, ERROR)
	status_label.visible = false
	column.add_child(status_label)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)

	if not game.ready:
		_label_to_body("The saved game or dungeon content could not be loaded. Existing data was not changed.", 20)
		_button_to_body("Retry", _retry)
		_set_status(game.error_message, true)
		return
	match screen:
		"home":
			_build_home()
		"explore":
			_build_exploration()
		"journal":
			_build_journal()
		"notes":
			_build_notes()
		"note":
			_build_note()
		"quests":
			_build_quests()
		"record":
			_build_record()
		"data":
			_build_data()
	if not status.is_empty():
		_set_status(status, not game.error_message.is_empty())


func _screen_title() -> String:
	match screen:
		"home": return "ENTRANCE"
		"explore": return "EXPLORATION"
		"journal", "notes", "note", "quests", "record": return "JOURNAL"
		"data": return "YOUR DATA"
	return ""


func _label(text: String, font_size = 18, color = TEXT) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _label_to_body(text: String, font_size = 18, color = TEXT) -> Label:
	var label = _label(text, font_size, color)
	body.add_child(label)
	return label


func _button(text: String, action: Callable, disabled = false) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = disabled
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(action)
	return button


func _button_to_body(text: String, action: Callable, disabled = false) -> Button:
	var button = _button(text, action, disabled)
	body.add_child(button)
	return button


func _set_status(message: String, is_error = false) -> void:
	status = message
	if is_instance_valid(status_label):
		status_label.text = message
		status_label.visible = not message.is_empty()
		status_label.add_theme_color_override("font_color", ERROR if is_error else ACCENT)


func _clear_status() -> void:
	status = ""
	game.error_message = ""


func _title(id: String) -> String:
	return id.replace("-", " ").capitalize()


func _retry() -> void:
	var path = save_path_override if not save_path_override.is_empty() else "user://delve.json"
	if game.initialize(path):
		_clear_status()
	else:
		status = game.error_message
	_rebuild()


func _build_home() -> void:
	_label_to_body("A fixed dungeon. A mystery worth remembering.", 28, ACCENT)
	_label_to_body("Explore three handcrafted wings, follow the inscriptions, and keep your own notes. The dungeon is always the same.", 18, MUTED)
	if not game.last_ending.is_empty():
		body.add_child(HSeparator.new())
		_label_to_body(game.last_ending, 20, ACCENT)
		_add_record(game.last_record)
	body.add_child(HSeparator.new())
	_button_to_body("New delve", _request_new)
	if game.active_run() != null:
		_button_to_body("Resume delve", _resume)
		_label_to_body("An unfinished delve is saved on this device.", 15, MUTED)
	_button_to_body("Your data", _open_data)
	_label_to_body("Offline play  •  Original geometric placeholder art", 15, MUTED)


func _request_new() -> void:
	if game.active_run() != null and game.archive.settings.confirmNewRun:
		new_dialog.popup_centered()
	else:
		_start_new()


func _start_new() -> void:
	if game.start_new():
		screen = "explore"
		paused = false
		_clear_status()
	else:
		status = game.error_message
	_rebuild()


func _resume() -> void:
	if game.resume_session():
		screen = "explore"
		paused = false
		_clear_status()
	else:
		status = game.error_message
	_rebuild()


func _build_exploration() -> void:
	if game.active_run() == null:
		screen = "home"
		_build_home()
		return
	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	toolbar.add_child(_button("Journal  [J]", _open_journal))
	toolbar.add_child(_button("Continue" if paused else "Pause  [P]", _toggle_pause))
	toolbar.add_child(_button("Your data", _open_data))
	body.add_child(toolbar)
	var tables = game.tables_for_active()
	var state = game.world
	_label_to_body(_title(state.room), 28, ACCENT)
	_label_to_body("%d rooms visited  •  %d events saved" % [state.visited.size(), game.active_run().ledger.entries.size()], 16, MUTED)
	var connections = game.connections(tables, state.room)
	var allowed = []
	for connection in connections:
		allowed.append(game.can_visit(connection.room))
	var room_view = RoomView.new()
	room_view.custom_minimum_size = Vector2(0, 220)
	room_view.configure(state, tables, connections, allowed)
	body.add_child(room_view)
	_label_to_body("Circle: explorer  •  Numbered doors: exits  •  Diamond: key  •  Triangle: switch  •  Cross: discovery", 15, MUTED)
	if not state.keys.is_empty():
		var key_names: Array[String] = []
		for key in state.keys:
			key_names.append(_title(key))
		key_names.sort()
		_label_to_body("Keys: " + ", ".join(key_names), 16, ACCENT)
	if paused:
		_label_to_body("Paused — progress is saved.", 20, ACCENT)
		_button_to_body("Return to entrance", _return_to_entrance)
		return
	_label_to_body("Exits", 20, ACCENT)
	for index in range(connections.size()):
		var connection = connections[index]
		var is_allowed = allowed[index]
		var label = "[%d]  %s%s" % [index + 1, _title(connection.room), "" if is_allowed else "  — locked"]
		var button = _button_to_body(label, _visit.bind(connection.room), not is_allowed)
		move_buttons.append(button)
	var switch_ids = tables.switchEffects.keys()
	switch_ids.sort()
	for element in switch_ids:
		if not tables.has("switchRooms") or tables.switchRooms.get(element) != state.room:
			continue
		var on = true
		for effect in tables.switchEffects[element]:
			on = on and state.flags.has(effect)
		_button_to_body("%s  •  Use %s" % ["ON" if on else "OFF", _title(element)], _act.bind("action", element))
	var discoveries = tables.discoverySpawns.keys()
	discoveries.sort()
	for id in discoveries:
		if tables.discoverySpawns[id] == state.room:
			var found = state.discoveries.has(id)
			_button_to_body("%s  %s" % ["Recorded" if found else "Discover", _title(id)], _act.bind("discovery", id), found)
	if state.room == tables.get("goalRoom") and tables.contentVersion >= 3:
		_button_to_body("Finish the delve", _act.bind("finish", ""))
	_button_to_body("Retreat to entrance", _act.bind("retreat", ""))


func _visit(room: String) -> void:
	_act("visit", room)


func _act(kind: String, id: String) -> void:
	if paused:
		return
	if game.perform(kind, id):
		_clear_status()
		if game.active_run() == null:
			screen = "home"
	else:
		status = game.error_message
	_rebuild()


func _toggle_pause() -> void:
	paused = not paused
	_clear_status()
	_rebuild()


func _return_to_entrance() -> void:
	screen = "home"
	paused = false
	_clear_status()
	_rebuild()


func _open_journal() -> void:
	screen = "journal"
	_clear_status()
	_rebuild()


func _build_journal() -> void:
	_label_to_body("Clue journal", 28, ACCENT)
	_label_to_body("Keep notes and theories separately from what the dungeon can prove.", 18, MUTED)
	_button_to_body("Room notes", _navigate.bind("notes"))
	_button_to_body("Quest inscriptions", _navigate.bind("quests"))
	_button_to_body("Run record", _navigate.bind("record"))
	_button_to_body("Back to the dungeon", _navigate.bind("explore"))


func _navigate(destination: String) -> void:
	screen = destination
	_clear_status()
	_rebuild()


func _build_notes() -> void:
	_label_to_body("Room notes", 28, ACCENT)
	_label_to_body("One note per visited room. Your words belong to you.", 18, MUTED)
	var rooms = game.world.visited.duplicate()
	rooms.sort()
	for room in rooms:
		var text = game.active_run().notes.get(room, "")
		var summary = "No note recorded" if text.is_empty() else text.replace("\n", " ").left(70)
		_button_to_body("%s  —  %s" % [_title(room), summary], _edit_note.bind(room))
	_button_to_body("Back to journal", _navigate.bind("journal"))


func _edit_note(room: String) -> void:
	note_room = room
	_navigate("note")


func _build_note() -> void:
	_label_to_body(_title(note_room), 28, ACCENT)
	_label_to_body("Pinned room note, up to 10,000 characters. Save before leaving.", 18, MUTED)
	note_editor = TextEdit.new()
	note_editor.custom_minimum_size = Vector2(0, 200)
	note_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_editor.placeholder_text = "Write a clue, sketch a theory, or remember a route..."
	note_editor.text = game.active_run().notes.get(note_room, "")
	note_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.add_child(note_editor)
	_button_to_body("Save note", _save_note)
	_button_to_body("Delete note", _delete_note)
	_button_to_body("Back to room notes", _navigate.bind("notes"))


func _save_note() -> void:
	if game.save_note(note_room, note_editor.text):
		_set_status("Note saved.")
	else:
		_set_status(game.error_message, true)


func _delete_note() -> void:
	if game.save_note(note_room, ""):
		note_editor.text = ""
		_set_status("Note deleted.")
	else:
		_set_status(game.error_message, true)


func _build_quests() -> void:
	_label_to_body("Quest inscriptions", 28, ACCENT)
	_label_to_body("Your marks are theories. Dungeon progress is derived separately from recorded events.", 18, MUTED)
	var quest = game.quest_for_active()
	if quest.is_empty():
		_label_to_body("This older delve has no quest inscriptions.", 18)
	else:
		for goal in quest.goals:
			body.add_child(HSeparator.new())
			_label_to_body(goal.text, 20)
			var marked = game.active_run().markedGoals.has(goal.id)
			var mark = CheckBox.new()
			mark.text = "Marked by you"
			mark.button_pressed = marked
			mark.custom_minimum_size.y = 48
			mark.toggled.connect(_mark_goal.bind(goal.id))
			body.add_child(mark)
			var progress = game.goal_progress(goal, game.active_run())
			_label_to_body("Dungeon state: " + progress.replace("_", " ").capitalize(), 16, MUTED)
	_button_to_body("Back to journal", _navigate.bind("journal"))


func _mark_goal(marked: bool, goal_id: String) -> void:
	if game.mark_goal(goal_id, marked):
		_clear_status()
	else:
		status = game.error_message
	_rebuild()


func _build_record() -> void:
	_label_to_body("Run record", 28, ACCENT)
	_label_to_body("Ledger facts. Steps include the initial entrance visit.", 18, MUTED)
	_add_record(game.current_record())
	_button_to_body("Back to journal", _navigate.bind("journal"))


func _add_record(record: Dictionary) -> void:
	if record.is_empty():
		_label_to_body("Run record unavailable.", 18)
		return
	_label_to_body("Rooms visited: %s" % record.rooms)
	_label_to_body("Steps: %s" % record.steps)
	_label_to_body("Sessions: %s" % record.sessions)
	var discoveries: Array[String] = []
	for id in record.discoveries:
		discoveries.append(_title(id))
	_label_to_body("Discoveries: " + ("none recorded" if discoveries.is_empty() else ", ".join(discoveries)))


func _open_data() -> void:
	return_screen = screen
	_navigate("data")


func _build_data() -> void:
	_label_to_body("Your data", 28, ACCENT)
	_label_to_body("Backups include run ledgers, notes, quest marks, and settings. CSV contains journal notes and quest progress.", 18, MUTED)
	_button_to_body("Save JSON backup", _choose_file.bind("backup"))
	_button_to_body("Save journal and quest CSV", _choose_file.bind("csv"))
	body.add_child(HSeparator.new())
	_label_to_body("Restore", 22, ACCENT)
	_label_to_body("Restoring replaces all local saves and settings. Review the changes before confirming.", 18, MUTED)
	_button_to_body("Choose backup for preview", _choose_file.bind("restore"))
	body.add_child(HSeparator.new())
	_label_to_body("Settings", 22, ACCENT)
	var confirm = CheckBox.new()
	confirm.text = "Confirm before replacing an active delve"
	confirm.button_pressed = game.archive.settings.confirmNewRun
	confirm.custom_minimum_size.y = 52
	confirm.toggled.connect(_set_confirm)
	body.add_child(confirm)
	_button_to_body("Done", _navigate.bind(return_screen))


func _set_confirm(value: bool) -> void:
	if game.set_confirm_new_run(value):
		status = "Setting saved."
	else:
		status = game.error_message
	_rebuild()


func _choose_file(operation: String) -> void:
	file_operation = operation
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if operation == "restore" else FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.title = "Choose a Delve backup" if operation == "restore" else "Save Delve export"
	file_dialog.filters = PackedStringArray(["*.csv ; CSV files"] if operation == "csv" else ["*.json ; JSON files"])
	file_dialog.current_file = "Delve-journal.csv" if operation == "csv" else ("Delve-backup.json" if operation == "backup" else "")
	file_dialog.popup_centered_ratio(0.85)


func _file_selected(path: String) -> void:
	match file_operation:
		"backup":
			if game.export_backup(path):
				_set_status("Backup saved.")
			else:
				_set_status(game.error_message, true)
		"csv":
			if game.export_csv(path):
				_set_status("Journal CSV saved.")
			else:
				_set_status(game.error_message, true)
		"restore":
			var preview = game.preview_restore(path)
			if preview.is_empty():
				_set_status(game.error_message, true)
				return
			restore_dialog.dialog_text = (
				"Runs: %d added, %d removed, %d changed, %d unchanged\n" % [preview.added, preview.removed, preview.changed, preview.unchanged]
				+ "Events: %d → %d\n" % [preview.events_before, preview.events_after]
				+ "Notes: %d → %d\n" % [preview.notes_before, preview.notes_after]
				+ "Quest marks: %d → %d\n" % [preview.marks_before, preview.marks_after]
				+ "Active run: %s → %s\n" % [_active_name(preview.active_before), _active_name(preview.active_after)]
				+ "Settings: %s\n\n" % ["will change" if preview.settings_changed else "unchanged"]
				+ "Replace all local data with this backup?"
			)
			restore_dialog.popup_centered()


func _active_name(value) -> String:
	return "none" if value == null else str(value)


func _restore() -> void:
	if game.restore_confirmed():
		screen = "home"
		return_screen = "home"
		paused = false
		status = "Backup restored."
	else:
		status = game.error_message
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or screen == "note":
		return
	if screen == "explore":
		if event.keycode == KEY_J:
			_open_journal()
		elif event.keycode == KEY_P or event.keycode == KEY_ESCAPE:
			_toggle_pause()
		elif not paused and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var index = event.keycode - KEY_1
			if index < move_buttons.size() and not move_buttons[index].disabled:
				move_buttons[index].pressed.emit()
	elif event.keycode == KEY_ESCAPE:
		match screen:
			"journal": _navigate("explore")
			"notes", "quests", "record": _navigate("journal")
			"data": _navigate(return_screen)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen == "explore" and game.ready and not paused:
		paused = true
		status = "Paused — progress is saved."
		_rebuild()
