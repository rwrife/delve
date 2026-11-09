extends SceneTree

const Game = preload("res://godot/delve_game.gd")

var failures: Array[String] = []
var files: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func temp_path(name: String) -> String:
	var path = "user://delve-test-%s-%s" % [OS.get_process_id(), name]
	files.append(path)
	files.append(path + ".tmp")
	return path


func new_game(path: String):
	var game = Game.new()
	if not game.initialize(path):
		check(false, "initialize: " + game.error_message)
		return null
	return game


func visit(game, rooms: Array) -> bool:
	for room in rooms:
		if not game.perform("visit", room):
			check(false, "visit %s: %s" % [room, game.error_message])
			return false
	return true


func _run() -> void:
	test_content_and_save()
	test_patrol()
	test_quest_order_and_latched_doors()
	test_full_dungeon()
	test_backup_and_errors()
	test_native_archives()
	test_invalid_backups()
	for path in files:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures.is_empty():
		print("All Godot game tests passed.")
		quit(0)
	else:
		printerr("%d Godot game test(s) failed." % failures.size())
		quit(1)


func test_content_and_save() -> void:
	var path = temp_path("save.json")
	var game = new_game(path)
	if game == null:
		return
	print("Content fingerprints: ", game.fingerprints)
	check(game.tables_by_version[3].graph.rooms.size() == 45, "three wings contain 45 original rooms")
	check(game.start_new(), "start a new run")
	check(game.world.room == "entrance" and game.world.step == 1, "start visits the entrance")
	check(game.current_record().sessions == "1", "start records one session")
	check(game.perform("discovery", "lore-threshold"), "record entrance discovery")
	check(not game.perform("visit", "fork"), "reject nonadjacent movement")
	check(game.world.room == "entrance", "rejected event does not change the world")
	check(game.save_note("entrance", "A note, with \"quotes\"\nA second line"), "save a room note")
	check(not game._exceeds_character_limit("e\u0301".repeat(10000), 10000), "note limit counts composed characters")
	check(game._exceeds_character_limit("e\u0301".repeat(10001), 10000), "note limit rejects more than 10,000 composed characters")
	check(not game._exceeds_character_limit("👩🏽‍🚀".repeat(10000), 10000), "note limit counts emoji graphemes")
	var long_note = "e\u0301".repeat(10000)
	check(game.save_note("entrance", long_note), "save a note at the character limit")
	check(not game.save_note("entrance", long_note + "x"), "reject a note above the character limit")
	check(game.active_run().notes.entrance == long_note, "rejected note leaves the saved note unchanged")
	check(game.save_note("entrance", "A note, with \"quotes\"\nA second line"), "restore the test note")
	check(game.mark_goal("silence", true), "save a player quest mark")
	var loaded = new_game(path)
	if loaded == null:
		return
	check(loaded.world == game.world, "reopen replays the saved ledger")
	check(loaded.active_run().notes.entrance == "A note, with \"quotes\"\nA second line", "reopen preserves notes")
	check(loaded.active_run().markedGoals.has("silence"), "reopen preserves quest marks")
	check(loaded.resume_session(), "resume records a session")
	check(loaded.current_record().sessions == "2", "record includes resumed session")
	check(visit(loaded, ["brazier-hall", "sealed-vault", "dust-corridor", "fork"]), "reach the fork")
	check(not loaded.can_visit("sentinel-arch"), "arch is locked without its key")
	check(loaded.goal_progress(loaded.quest_for_active().goals[0], loaded.active_run()) == "in_progress", "quest progress uses first evidence")
	check(visit(loaded, ["amber-alcove", "fork"]), "obtain the bronze key")
	check(loaded.can_visit("sentinel-arch"), "key unlocks the arch")


func test_patrol() -> void:
	var game = new_game(temp_path("patrol.json"))
	if game == null:
		return
	check(game.start_new(), "start patrol test")
	if not visit(game, ["brazier-hall", "sealed-vault", "dust-corridor", "fork", "blind-crypt", "ossuary", "blind-crypt", "fork"]):
		return
	check(game.active_run() != null and not game.world.dead, "direct crypt route is safely recoverable")
	check(game.start_new(), "start fatal patrol route")
	if not visit(game, ["brazier-hall", "sealed-vault", "dust-corridor", "fork", "amber-alcove", "fork", "west-gallery", "bell-niche", "west-gallery", "fork", "blind-crypt", "ossuary"]):
		return
	check(game.world.dead and game.active_run() == null, "contact atomically records death and clears active run")
	check(game.last_ending.contains("patrol"), "death displays the ending")
	var finished_run = game.archive.runs.back()
	check(game._decode_event(finished_run.ledger.entries.back(), finished_run.ledger.entries.size() - 1).event.has("death"), "death is present in the ledger")


func test_quest_order_and_latched_doors() -> void:
	var game = new_game(temp_path("ordering.json"))
	if game == null:
		return
	check(game.start_new(), "start quest ordering test")
	if not visit(game, ["brazier-hall", "sealed-vault", "dust-corridor", "fork", "west-gallery", "bell-niche"]):
		return
	check(game.perform("action", "resonant-bell"), "ring bell before discovering the clue")
	check(game.goal_progress(game.quest_for_active().goals[1], game.active_run()) == "unknown", "completion without first evidence remains unknown")
	if not visit(game, ["west-gallery", "fork", "amber-alcove", "fork", "sentinel-arch", "echo-steps", "stair-landing", "reliquary", "heart-chamber", "reliquary", "stair-landing", "echo-steps", "sentinel-arch", "fork", "west-gallery", "bell-niche"]):
		return
	check(game.perform("action", "resonant-bell"), "turn the bell off again")
	check(not game.world.flags.has("bell-lit"), "bell flag is off")
	if not visit(game, ["west-gallery", "fork", "sentinel-arch", "echo-steps", "stair-landing", "reliquary"]):
		return
	check(game.can_visit("heart-chamber"), "previously opened door stays latched")


func test_full_dungeon() -> void:
	var game = new_game(temp_path("full.json"))
	if game == null:
		return
	check(game.start_new(), "start full dungeon")
	if not visit(game, ["brazier-hall", "sealed-vault", "dust-corridor", "fork", "amber-alcove", "fork", "west-gallery", "bell-niche"]):
		return
	check(game.perform("action", "resonant-bell"), "ring the bell")
	if not visit(game, ["west-gallery", "fork", "sentinel-arch", "echo-steps", "stair-landing", "reliquary"]):
		return
	check(game.perform("discovery", "lore-echo"), "record the echo")
	if not visit(game, ["heart-chamber", "ash-threshold", "ink-gallery", "chronicle-aisle"]):
		return
	check(game.perform("discovery", "lore-ink"), "record the ink")
	if not visit(game, ["quiet-stacks", "tide-landing", "lantern-bridge", "slate-crossing", "underkeep-bridge", "night-gate", "basalt-foyer", "moth-court", "glass-corridor", "ember-walk", "spiral-steps"]):
		return
	check(not game.can_visit("star-anteroom"), "memory door requires key and flag")
	if not visit(game, ["ember-walk", "glass-corridor", "moth-court", "basalt-foyer", "prism-chapel"]):
		return
	check(game.perform("discovery", "lore-prism"), "record the prism")
	if not visit(game, ["basalt-foyer", "night-gate", "underkeep-bridge", "slate-crossing", "lantern-bridge", "tide-landing", "quiet-stacks", "chronicle-aisle", "memory-seat"]):
		return
	check(game.perform("action", "memory-latch"), "activate the memory latch")
	check(game.goal_progress(game.quest_for_active().goals[4], game.active_run()) == "achieved", "cross-wing quest follows ordered evidence")
	if not visit(game, ["chronicle-aisle", "quiet-stacks", "tide-landing", "lantern-bridge", "slate-crossing", "underkeep-bridge", "night-gate", "basalt-foyer", "moth-court", "glass-corridor", "ember-walk", "spiral-steps", "star-anteroom", "last-aperture"]):
		return
	check(not game.can_visit("dawn-well"), "dawn door requires the orrery")
	if not visit(game, ["star-anteroom", "spiral-steps", "broken-orbit"]):
		return
	check(game.perform("action", "orrery-lens"), "activate the orrery")
	if not visit(game, ["spiral-steps", "star-anteroom", "last-aperture", "dawn-well"]):
		return
	check(game.perform("discovery", "lore-dawn"), "record the dawn")
	check(game.goal_progress(game.quest_for_active().goals[5], game.active_run()) == "achieved", "final goal is achieved")
	check(game.perform("finish"), "finish at the dawn well")
	check(game.world.finished and game.active_run() == null, "finish is terminal")
	check(game.last_record.rooms > 20 and game.last_record.steps > game.last_record.rooms, "epilogue reflects the ledger")
	var loaded = new_game(game.save_path)
	if loaded != null:
		check(loaded.active_run() == null and loaded.archive.runs.size() == 1, "terminal history persists")


func test_backup_and_errors() -> void:
	var path = temp_path("backup-save.json")
	var backup = temp_path("backup.json")
	var csv = temp_path("journal.csv")
	var game = new_game(path)
	if game == null:
		return
	check(game.start_new(), "start backup test")
	check(game.save_note("entrance", "=SUM(1,2)\n\"quoted\""), "save CSV test note")
	check(game.export_backup(backup), "export JSON backup")
	check(game.export_csv(csv), "export CSV")
	var csv_text = FileAccess.get_file_as_string(csv)
	check(csv_text.contains("\"'=SUM(1,2)\n\"\"quoted\"\"\""), "CSV quotes and neutralizes formulas")
	check(game._csv_row(["\u00a0+3"]) == "\"'\u00a0+3\"", "CSV neutralizes formulas after Unicode whitespace")
	var preview = game.preview_restore(backup)
	check(not preview.is_empty() and preview.unchanged == 1, "preview identical backup")
	check(game.save_note("entrance", "changed after preview"), "change after preview")
	check(not game.restore_confirmed(), "reject stale preview")
	check(game.active_run().notes.entrance == "changed after preview", "stale restore preserves data")
	check(not game.preview_restore(backup).is_empty(), "preview backup again")
	check(game.restore_confirmed(), "restore confirmed backup")
	check(game.active_run().notes.entrance == "=SUM(1,2)\n\"quoted\"", "restore replaces data")
	var other = new_game(path)
	if other != null:
		check(game.save_note("entrance", "first window"), "first window saves")
		check(not other.save_note("entrance", "second window"), "stale window cannot overwrite another window")
		check(other.active_run().notes.entrance != "second window", "failed stale write does not publish changes")
	var impossible = new_game("user://delve-test-missing-directory/save.json")
	if impossible != null:
		check(not impossible.start_new(), "write failure is surfaced")
		check(impossible.archive.runs.is_empty(), "write failure does not publish a run")
	var locked_path = temp_path("locked.json")
	var locked = new_game(locked_path)
	if locked != null:
		var lock_path = ProjectSettings.globalize_path(locked_path + ".lock")
		check(DirAccess.make_dir_absolute(lock_path) == OK, "create a competing save lock")
		check(not locked.start_new() and locked.archive.runs.is_empty(), "competing save lock prevents writes")
		check(DirAccess.remove_absolute(lock_path) == OK, "remove the test lock")
		check(locked.start_new(), "saving succeeds after the competing lock is released")


func test_native_archives() -> void:
	var game = new_game(temp_path("native.json"))
	if game == null:
		return
	var expected = {
		1: "e4a8d1f9e5749c8d",
		2: "2a4b4cc2b0d8ceb0",
		3: "d631b2c3c2665c0b"
	}
	for version in [1, 2, 3]:
		check(game.fingerprints[version] == expected[version], "native content fingerprint %d" % version)
		var entries = [
			{"sequence": 0, "eventBase64": Marshalls.utf8_to_base64('{"sessionStart":{}}')},
			{"sequence": 1, "eventBase64": Marshalls.utf8_to_base64('{"visit":{"room":"entrance"}}')}
		]
		var native = {
			"version": 1,
			"runs": [{
				"id": "native-%d" % version,
				"ledger": {"contentVersion": version, "tablesFingerprint": expected[version], "entries": entries},
				"notes": {"entrance": "Snow 雪"}, "markedGoals": []
			}],
			"activeRunID": "native-%d" % version
		}
		var checked = game._validate_archive(native)
		check(checked.ok, "accept native v1 backup with content v%d" % version)
		if not checked.ok:
			continue
		check(checked.archive.version == 2 and checked.archive.settings.confirmNewRun, "migrate v1 settings")
		var path = temp_path("native-v%d.json" % version)
		var file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(native))
		file.close()
		check(not game.preview_restore(path).is_empty(), "preview native content v%d" % version)
		check(game.restore_confirmed(), "restore native content v%d" % version)
		check(game.world.room == "entrance" and game.active_run().notes.entrance == "Snow 雪", "native content v%d replays with notes" % version)
		check(game.resume_session(), "native content v%d resumes" % version)


func test_invalid_backups() -> void:
	var corrupt_path = temp_path("corrupt-save.json")
	var corrupt_file = FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt_file.store_string("{not valid json")
	corrupt_file.close()
	var corrupt_game = Game.new()
	check(not corrupt_game.initialize(corrupt_path), "corrupt local save is reported")
	check(not corrupt_game.start_new(), "a corrupt local save cannot be overwritten by starting a run")
	check(FileAccess.get_file_as_string(corrupt_path) == "{not valid json", "corrupt local save is preserved for recovery")
	var game = new_game(temp_path("invalid-save.json"))
	if game == null:
		return
	check(game.start_new(), "start invalid backup test")
	var original = game.archive.duplicate(true)
	var cases = []
	var bad = original.duplicate(true)
	bad.version = 3
	cases.append(bad)
	bad = original.duplicate(true)
	bad.erase("settings")
	cases.append(bad)
	bad = original.duplicate(true)
	bad.runs[0].ledger.tablesFingerprint = "incorrect"
	cases.append(bad)
	bad = original.duplicate(true)
	bad.runs[0].ledger.entries[0].sequence = 7
	cases.append(bad)
	bad = original.duplicate(true)
	bad.runs[0].ledger.entries[0].eventBase64 = Marshalls.utf8_to_base64('{"sessionStart":{},"extra":true}')
	cases.append(bad)
	bad = original.duplicate(true)
	bad.runs[0].ledger.entries[1].eventBase64 = Marshalls.utf8_to_base64('{"visit":{"room":"fork"}}')
	cases.append(bad)
	bad = original.duplicate(true)
	bad.runs[0].notes["not-visited"] = "note"
	cases.append(bad)
	bad = original.duplicate(true)
	bad.runs[0].markedGoals = ["unknown-goal"]
	cases.append(bad)
	bad = original.duplicate(true)
	bad.runs.append(bad.runs[0].duplicate(true))
	cases.append(bad)
	bad = original.duplicate(true)
	bad.activeRunID = "missing"
	cases.append(bad)
	bad = original.duplicate(true)
	bad.runs[0].ledger.entries.append(game._entry(game._event("retreat"), bad.runs[0].ledger.entries.size()))
	cases.append(bad)
	for index in range(cases.size()):
		check(not game._validate_archive(cases[index]).ok, "reject malformed backup case %d" % index)
	check(game.archive == original, "invalid backups do not change local data")
	var escaped = temp_path("escaped.json")
	bad = original.duplicate(true)
	bad.runs[0].notes["entrance"] = "placeholder"
	var document = JSON.stringify(bad).replace("placeholder", "bad\\u0000note")
	var file = FileAccess.open(escaped, FileAccess.WRITE)
	file.store_string(document)
	file.close()
	check(not game._read_json(escaped).ok, "reject escaped NUL before JSON decoding")
	bad.runs[0].notes["entrance"] = "literal \\u0000"
	file = FileAccess.open(escaped, FileAccess.WRITE)
	file.store_string(JSON.stringify(bad))
	file.close()
	check(game._read_json(escaped).ok, "accept a literal escaped backslash in a note")
	file = FileAccess.open(escaped, FileAccess.WRITE)
	var bom = PackedByteArray([0xef, 0xbb, 0xbf])
	bom.append_array(JSON.stringify(original).to_utf8_buffer())
	file.store_buffer(bom)
	file.close()
	check(game._read_json(escaped).ok, "accept a UTF-8 byte-order mark")
	var large = temp_path("large.json")
	file = FileAccess.open(large, FileAccess.WRITE)
	var padding = PackedByteArray()
	padding.resize(game.MAX_BACKUP_BYTES)
	padding.fill(32)
	var prefix = '{"version":2,"runs":[],"settings":{"confirmNewRun":true}}'.to_utf8_buffer()
	for index in range(prefix.size()):
		padding[index] = prefix[index]
	file.store_buffer(padding)
	file.close()
	check(game._read_json(large).ok, "accept JSON at the 32 MiB size boundary")
	file = FileAccess.open(large, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_8(32)
	file.close()
	var too_large = game._read_json(large)
	check(not too_large.ok and too_large.error.contains("32 MiB"), "reject JSON above the 32 MiB limit")
