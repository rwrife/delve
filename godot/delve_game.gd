extends RefCounted

const RESOURCE_DIR = "res://Packages/DelveKit/Sources/DelveKit/Resources/"
const MAX_BACKUP_BYTES = 32 * 1024 * 1024
const CURRENT_CONTENT = 3

var tables_by_version: Dictionary = {}
var quests_by_version: Dictionary = {}
var fingerprints: Dictionary = {}
var archive: Dictionary = {}
var world: Dictionary = {}
var save_path = "user://delve.json"
var disk_revision = ""
var error_message = ""
var ready = false
var last_ending = ""
var last_record: Dictionary = {}
var restore_preview: Dictionary = {}


func initialize(path = "user://delve.json") -> bool:
	save_path = path
	ready = false
	error_message = ""
	tables_by_version.clear()
	quests_by_version.clear()
	fingerprints.clear()
	for version in [1, 2, 3]:
		var data = _read_json(RESOURCE_DIR + "content-v%d.json" % version)
		if not data.ok:
			return _fail("Cannot load dungeon content: " + data.error)
		if not _validate_tables(data.value, version):
			return false
		tables_by_version[version] = data.value
		fingerprints[version] = _tables_fingerprint(data.value)
		if version >= 2:
			var quest = _read_json(RESOURCE_DIR + "quest-v%d.json" % version)
			if not quest.ok:
				return _fail("Cannot load quest content: " + quest.error)
			if not _validate_quest(quest.value, data.value):
				return false
			quests_by_version[version] = quest.value
	archive = _empty_archive()
	world = _empty_world()
	if FileAccess.file_exists(save_path):
		var saved = _read_json(save_path)
		if not saved.ok:
			return _fail("Could not read the saved game; it has not been changed. " + saved.error)
		var checked = _validate_archive(saved.value)
		if not checked.ok:
			return _fail("Could not load the saved game; it has not been changed. " + checked.error)
		archive = checked.archive
		if archive.activeRunID != null:
			var replay = _replay(_active_run(), tables_for_active())
			world = replay.world
	disk_revision = _disk_revision()
	if disk_revision == "":
		return _fail("Cannot read the saved game file.")
	ready = true
	return true


func _empty_archive() -> Dictionary:
	return {"version": 2, "runs": [], "activeRunID": null, "settings": {"confirmNewRun": true}}


func _empty_world() -> Dictionary:
	return {
		"room": "", "visited": [], "flags": [], "keys": [], "locks": [],
		"discoveries": [], "step": 0, "dead": false, "retreated": false, "finished": false
	}


func _read_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "%s (error %s)" % [path, FileAccess.get_open_error()]}
	if file.get_length() > MAX_BACKUP_BYTES:
		return {"ok": false, "error": "File exceeds the 32 MiB limit."}
	var length = file.get_length()
	var bytes = file.get_buffer(length)
	if bytes.size() != length:
		return {"ok": false, "error": "Could not read the entire JSON file."}
	if bytes.has(0):
		return {"ok": false, "error": "JSON contains a NUL byte."}
	if bytes.size() >= 3 and bytes[0] == 0xef and bytes[1] == 0xbb and bytes[2] == 0xbf:
		bytes = bytes.slice(3)
	var text = bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		return {"ok": false, "error": "JSON is not valid UTF-8."}
	if _contains_nul_escape(text):
		return {"ok": false, "error": "JSON contains a NUL character."}
	var parser = JSON.new()
	if parser.parse(text) != OK:
		return {"ok": false, "error": "%s, line %s: %s" % [path, parser.get_error_line(), parser.get_error_message()]}
	return {"ok": true, "value": parser.data}


func _contains_nul_escape(text: String) -> bool:
	var position = text.find("\\u0000")
	while position >= 0:
		var preceding_slashes = 0
		var previous = position - 1
		while previous >= 0 and text[previous] == "\\":
			preceding_slashes += 1
			previous -= 1
		if preceding_slashes % 2 == 0:
			return true
		position = text.find("\\u0000", position + 6)
	return false


func _fail(message: String) -> bool:
	error_message = message
	return false


func _is_integer(value) -> bool:
	return (value is int) or (value is float and is_finite(value) and value == floor(value))


func _exceeds_character_limit(text: String, limit: int) -> bool:
	if text.length() <= limit:
		return false
	return TextServerManager.get_primary_interface().string_get_character_breaks(text).size() > limit


func _validate_tables(tables, version: int) -> bool:
	if not tables is Dictionary or tables.get("contentVersion") != version:
		return _fail("Dungeon content has an invalid version.")
	for key in ["graph", "spawnRoom", "switchEffects", "lockKeys", "keySpawns", "discoverySpawns", "patrolCycles"]:
		if not tables.has(key):
			return _fail("Dungeon content is missing " + key + ".")
	if not tables.graph is Dictionary:
		return _fail("Dungeon graph is invalid.")
	var graph = tables.graph
	if not graph.get("rooms") is Array or not graph.get("doors") is Array or not graph.get("wings") is Array:
		return _fail("Dungeon graph is incomplete.")
	for key in ["switchEffects", "lockKeys", "keySpawns", "discoverySpawns", "patrolCycles"]:
		if not tables[key] is Dictionary:
			return _fail("Dungeon table is invalid: " + key + ".")
	var rooms = {}
	for room in graph.rooms:
		if not room is Dictionary or not room.get("id") is String or rooms.has(room.id):
			return _fail("Dungeon has an invalid or duplicate room.")
		rooms[room.id] = true
	if not rooms.has(tables.spawnRoom):
		return _fail("Dungeon spawn room is missing.")
	if tables.has("goalRoom") and not rooms.has(tables.goalRoom):
		return _fail("Dungeon goal room is missing.")
	for door in graph.doors:
		if not door is Dictionary or not rooms.has(door.get("from")) or not rooms.has(door.get("to")):
			return _fail("Dungeon contains an invalid door.")
		var lock_id = door.get("lock")
		if lock_id != null and not tables.lockKeys.has(lock_id):
			return _fail("Dungeon contains an unknown lock.")
	for group in ["keySpawns", "discoverySpawns"]:
		for id in tables[group]:
			if not rooms.has(tables[group][id]):
				return _fail("Dungeon contains an invalid " + group + " location.")
	for lock_id in tables.lockKeys:
		if not tables.keySpawns.has(tables.lockKeys[lock_id]):
			return _fail("Dungeon lock refers to an unknown key.")
	for element in tables.switchEffects:
		if not tables.switchEffects[element] is Array:
			return _fail("Dungeon switch effects are invalid.")
		if tables.has("switchRooms") and (not tables.switchRooms is Dictionary or not rooms.has(tables.switchRooms.get(element))):
			return _fail("Dungeon switch location is invalid.")
	if tables.has("lockFlags"):
		if not tables.lockFlags is Dictionary:
			return _fail("Dungeon lock conditions are invalid.")
		for lock_id in tables.lockFlags:
			if not tables.lockKeys.has(lock_id) or not tables.lockFlags[lock_id] is Array:
				return _fail("Dungeon lock conditions are invalid.")
	for patrol in tables.patrolCycles.values():
		if not patrol is Array or patrol.is_empty():
			return _fail("Dungeon patrol is invalid.")
		for room in patrol:
			if not rooms.has(room):
				return _fail("Dungeon patrol refers to an unknown room.")
	return true


func _validate_quest(quest, tables: Dictionary) -> bool:
	if not quest is Dictionary or quest.get("contentVersion") != tables.contentVersion or not quest.get("goals") is Array or quest.goals.is_empty():
		return _fail("Quest content is invalid.")
	var ids = []
	for goal in quest.goals:
		if not goal is Dictionary or not goal.get("id") is String or goal.id.is_empty() or ids.has(goal.id) or not goal.get("text") is String or goal.text.is_empty():
			return _fail("Quest goal is invalid.")
		ids.append(goal.id)
		for name in ["firstEvidence", "completionEvidence"]:
			var evidence = goal.get(name)
			if not evidence is Dictionary or not evidence.get("id") is String:
				return _fail("Quest evidence is invalid.")
			match evidence.get("kind"):
				"visit":
					if not _room_exists(tables, evidence.id):
						return _fail("Quest references an unknown room.")
				"discovery":
					if not tables.discoverySpawns.has(evidence.id):
						return _fail("Quest references an unknown discovery.")
				"action":
					if not tables.switchEffects.has(evidence.id):
						return _fail("Quest references an unknown switch.")
				_:
					return _fail("Quest evidence kind is invalid.")
	return true


func _room_exists(tables: Dictionary, room_id: String) -> bool:
	for room in tables.graph.rooms:
		if room.id == room_id:
			return true
	return false


# Matches Swift's sorted-key JSONEncoder representation of RuleTables.
func _tables_fingerprint(tables: Dictionary) -> String:
	var canonical_tables = tables.duplicate(true)
	for door in canonical_tables.graph.doors:
		if door.get("lock") == null:
			door.erase("lock")
	var bytes = _canonical_json(canonical_tables).to_utf8_buffer()
	var hash_value: int = -3750763034362895579
	for byte in bytes:
		hash_value = (hash_value ^ byte) * 1099511628211
	var hex = "0123456789abcdef"
	var result = ""
	for shift in range(60, -1, -4):
		result += hex[(hash_value >> shift) & 15]
	return result


func _canonical_json(value) -> String:
	if value is Dictionary:
		var keys = value.keys()
		keys.sort()
		var fields: Array[String] = []
		for key in keys:
			fields.append(JSON.stringify(str(key)) + ":" + _canonical_json(value[key]))
		return "{" + ",".join(fields) + "}"
	if value is Array:
		var items: Array[String] = []
		for item in value:
			items.append(_canonical_json(item))
		return "[" + ",".join(items) + "]"
	if value is float and _is_integer(value):
		return str(int(value))
	return JSON.stringify(value)


func _event(kind: String, id = "", effects = []) -> Dictionary:
	match kind:
		"visit":
			return {"visit": {"room": id}}
		"action":
			return {"action": {"element": id, "effects": effects}}
		"discovery":
			return {"discovery": {"id": id}}
		_:
			return {kind: {}}


func _entry(event: Dictionary, sequence: int) -> Dictionary:
	return {"sequence": sequence, "eventBase64": Marshalls.utf8_to_base64(_canonical_json(event))}


func _decode_event(entry, sequence: int) -> Dictionary:
	if not entry is Dictionary or not _is_integer(entry.get("sequence")) or int(entry.sequence) != sequence or not entry.get("eventBase64") is String:
		return {"ok": false, "error": "Invalid ledger sequence or event."}
	var encoded = entry.eventBase64
	var text = Marshalls.base64_to_utf8(encoded)
	if Marshalls.utf8_to_base64(text) != encoded:
		return {"ok": false, "error": "Invalid ledger event encoding."}
	var parser = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "Invalid ledger event JSON."}
	var event = parser.data
	if event.size() != 1 or _canonical_json(event) != text:
		return {"ok": false, "error": "Ledger event is not canonical."}
	var kind = event.keys()[0]
	var payload = event[kind]
	if not payload is Dictionary:
		return {"ok": false, "error": "Invalid ledger event payload."}
	match kind:
		"visit":
			if payload.size() != 1 or not payload.get("room") is String:
				return {"ok": false, "error": "Invalid visit."}
		"discovery":
			if payload.size() != 1 or not payload.get("id") is String:
				return {"ok": false, "error": "Invalid discovery."}
		"action":
			if payload.size() != 2 or not payload.get("element") is String or not payload.get("effects") is Array:
				return {"ok": false, "error": "Invalid action."}
			for effect in payload.effects:
				if not effect is String:
					return {"ok": false, "error": "Invalid action effect."}
		"sessionStart", "death", "retreat", "finish":
			if not payload.is_empty():
				return {"ok": false, "error": "Invalid ledger event payload."}
		_:
			return {"ok": false, "error": "Unknown ledger event."}
	return {"ok": true, "event": event}


func _is_terminal(state: Dictionary) -> bool:
	return state.dead or state.retreated or state.finished


func _in_contact(state: Dictionary, tables: Dictionary) -> bool:
	if state.room == "" or _is_terminal(state):
		return false
	for cycle in tables.patrolCycles.values():
		if not cycle.is_empty() and cycle[state.step % cycle.size()] == state.room:
			return true
	return false


func connections(tables: Dictionary, room_id: String) -> Array:
	var result = []
	for door in tables.graph.doors:
		if door.from == room_id:
			result.append({"room": door.to, "lock": door.get("lock")})
		elif door.to == room_id:
			result.append({"room": door.from, "lock": door.get("lock")})
	return result


func _step(state: Dictionary, event: Dictionary, tables: Dictionary) -> Dictionary:
	if _is_terminal(state):
		return {"ok": false, "error": "This delve has ended."}
	var kind = event.keys()[0]
	var payload = event[kind]
	var contact = _in_contact(state, tables)
	if kind == "death":
		if not contact:
			return {"ok": false, "error": "Death requires patrol contact."}
	elif contact:
		return {"ok": false, "error": "Patrol contact must end the delve."}
	var next = state.duplicate(true)
	match kind:
		"sessionStart":
			pass
		"death":
			next.dead = true
		"retreat":
			if state.room == "":
				return {"ok": false, "error": "The delve has not started."}
			next.retreated = true
		"finish":
			if tables.contentVersion < 3 or state.room == "" or state.room != tables.get("goalRoom"):
				return {"ok": false, "error": "The final room has not been reached."}
			next.finished = true
		"visit":
			var room = payload.room
			if not _room_exists(tables, room):
				return {"ok": false, "error": "That room does not exist."}
			if state.room == "":
				if room != tables.spawnRoom:
					return {"ok": false, "error": "A delve must start at the entrance."}
			else:
				var matched = false
				for connection in connections(tables, state.room):
					if connection.room != room:
						continue
					matched = true
					var lock_id = connection.lock
					if lock_id != null and not state.locks.has(lock_id):
						if not state.keys.has(tables.lockKeys[lock_id]):
							return {"ok": false, "error": "This door is locked."}
						for flag in tables.get("lockFlags", {}).get(lock_id, []):
							if not state.flags.has(flag):
								return {"ok": false, "error": "This door is locked."}
						next.locks.append(lock_id)
					break
				if not matched:
					return {"ok": false, "error": "That room is not connected."}
			next.room = room
			if not next.visited.has(room):
				next.visited.append(room)
			next.step += 1
			for key in tables.keySpawns:
				if tables.keySpawns[key] == room and not next.keys.has(key):
					next.keys.append(key)
		"action":
			var element = payload.element
			if state.room == "" or not tables.switchEffects.has(element) or payload.effects != tables.switchEffects[element]:
				return {"ok": false, "error": "This action is not available."}
			if tables.has("switchRooms") and tables.switchRooms.get(element) != state.room:
				return {"ok": false, "error": "This action is in a different room."}
			for effect in tables.switchEffects[element]:
				if next.flags.has(effect):
					next.flags.erase(effect)
				else:
					next.flags.append(effect)
		"discovery":
			var id = payload.id
			if not tables.discoverySpawns.has(id) or not state.visited.has(tables.discoverySpawns[id]):
				return {"ok": false, "error": "This discovery has not been reached."}
			if not next.discoveries.has(id):
				next.discoveries.append(id)
		_:
			return {"ok": false, "error": "Unknown action."}
	return {"ok": true, "world": next}


func _replay(run: Dictionary, tables: Dictionary) -> Dictionary:
	var state = _empty_world()
	var events = []
	for index in range(run.ledger.entries.size()):
		var decoded = _decode_event(run.ledger.entries[index], index)
		if not decoded.ok:
			return decoded
		var result = _step(state, decoded.event, tables)
		if not result.ok:
			return {"ok": false, "error": "Illegal ledger event %d: %s" % [index, result.error]}
		state = result.world
		events.append(decoded.event)
	return {"ok": true, "world": state, "events": events}


func _validate_archive(input) -> Dictionary:
	if not input is Dictionary or not _is_integer(input.get("version")) or int(input.version) not in [1, 2]:
		return {"ok": false, "error": "Unsupported or missing backup version."}
	if not input.get("runs") is Array or input.runs.size() > 10000:
		return {"ok": false, "error": "Invalid or excessive saved runs."}
	var normalized = _empty_archive()
	if int(input.version) == 2:
		if not input.get("settings") is Dictionary or not input.settings.get("confirmNewRun") is bool:
			return {"ok": false, "error": "Backup settings are invalid."}
		normalized.settings.confirmNewRun = input.settings.confirmNewRun
	var active = input.get("activeRunID")
	if active != null and not active is String:
		return {"ok": false, "error": "Active run identity is invalid."}
	normalized.activeRunID = active
	var seen = []
	for run in input.runs:
		if not run is Dictionary or not run.get("id") is String or run.id.is_empty() or _exceeds_character_limit(run.id, 200) or run.id.to_utf8_buffer().has(0) or seen.has(run.id):
			return {"ok": false, "error": "Invalid or duplicate run identity."}
		seen.append(run.id)
		if not run.get("ledger") is Dictionary or not _is_integer(run.ledger.get("contentVersion")):
			return {"ok": false, "error": "Invalid run ledger."}
		var version = int(run.ledger.contentVersion)
		if not tables_by_version.has(version) or run.ledger.get("tablesFingerprint") != fingerprints[version]:
			return {"ok": false, "error": "Unsupported dungeon content or fingerprint."}
		if not run.ledger.get("entries") is Array or run.ledger.entries.is_empty():
			return {"ok": false, "error": "A saved run has an empty ledger."}
		if not run.get("notes") is Dictionary or not run.get("markedGoals") is Array:
			return {"ok": false, "error": "Invalid journal."}
		var replay = _replay(run, tables_by_version[version])
		if not replay.ok:
			return replay
		for room in run.notes:
			var text = run.notes[room]
			if not room is String or not replay.world.visited.has(room) or not text is String or _exceeds_character_limit(text, 10000) or text.to_utf8_buffer().has(0):
				return {"ok": false, "error": "Invalid room note."}
		var marks = []
		var valid_goal_ids = []
		if quests_by_version.has(version):
			for goal in quests_by_version[version].goals:
				valid_goal_ids.append(goal.id)
		for goal in run.markedGoals:
			if not goal is String or marks.has(goal) or not valid_goal_ids.has(goal):
				return {"ok": false, "error": "Invalid or duplicate quest mark."}
			marks.append(goal)
		marks.sort()
		var clean_entries = []
		for entry in run.ledger.entries:
			clean_entries.append({"sequence": int(entry.sequence), "eventBase64": entry.eventBase64})
		var clean_run = {
			"id": run.id,
			"ledger": {"contentVersion": version, "tablesFingerprint": fingerprints[version], "entries": clean_entries},
			"notes": run.notes.duplicate(true),
			"markedGoals": marks
		}
		normalized.runs.append(clean_run)
		if run.id == active and _is_terminal(replay.world):
			return {"ok": false, "error": "The active run has already ended."}
	if active != null and not seen.has(active):
		return {"ok": false, "error": "The active run is missing."}
	return {"ok": true, "archive": normalized}


func _active_run():
	if archive.get("activeRunID") == null:
		return null
	for run in archive.runs:
		if run.id == archive.activeRunID:
			return run
	return null


func active_run():
	return _active_run()


func tables_for_active() -> Dictionary:
	var run = _active_run()
	if run == null:
		return tables_by_version.get(CURRENT_CONTENT, {})
	return tables_by_version[run.ledger.contentVersion]


func quest_for_active() -> Dictionary:
	var run = _active_run()
	if run == null:
		return {}
	return quests_by_version.get(run.ledger.contentVersion, {})


func _disk_revision() -> String:
	if not FileAccess.file_exists(save_path):
		return "<missing>"
	return FileAccess.get_sha256(save_path)


func _commit(next: Dictionary) -> bool:
	var lock_path = ProjectSettings.globalize_path(save_path + ".lock")
	var lock_error = DirAccess.make_dir_absolute(lock_path)
	if lock_error != OK:
		if DirAccess.dir_exists_absolute(lock_path):
			return _fail("The save is locked by another game or an interrupted write. If no other copy is running, remove the lock directory: " + lock_path)
		return _fail("Could not lock the saved game (error %s)." % lock_error)
	var committed = _commit_locked(next)
	var unlock_error = DirAccess.remove_absolute(lock_path)
	if unlock_error != OK:
		var result = "The change was saved, but" if committed else "The change was not saved, and"
		ready = false
		return _fail("%s the save lock could not be removed (error %s): %s" % [result, unlock_error, lock_path])
	return committed


func _commit_locked(next: Dictionary) -> bool:
	var current_revision = _disk_revision()
	if current_revision == "" or current_revision != disk_revision:
		return _fail("The saved game changed outside this window. Reload before continuing.")
	var text = JSON.stringify(next, "\t", true) + "\n"
	if text.to_utf8_buffer().size() > MAX_BACKUP_BYTES:
		return _fail("The save exceeds the 32 MiB limit.")
	var suffix = Crypto.new().generate_random_bytes(16).hex_encode()
	if suffix.length() != 32:
		return _fail("Could not create a temporary save identity.")
	var temp_path = save_path + ".tmp-" + suffix
	if FileAccess.file_exists(temp_path):
		return _fail("Could not create a unique temporary save file.")
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("Could not write the saved game (error %s)." % FileAccess.get_open_error())
	file.store_string(text)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return _fail("Could not write the saved game (error %s)." % write_error)
	if _disk_revision() != disk_revision:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return _fail("The saved game changed outside this window. Reload before continuing.")
	var result = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(save_path))
	if result != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return _fail("Could not replace the saved game (error %s)." % result)
	archive = next
	disk_revision = text.sha256_text()
	error_message = ""
	return true


func start_new() -> bool:
	if not ready:
		return _fail("The game is not ready.")
	var id = Crypto.new().generate_random_bytes(16).hex_encode()
	if id.length() != 32:
		return _fail("Could not create a run identity.")
	for old in archive.runs:
		if old.id == id:
			return _fail("Could not create a unique run identity; try again.")
	var tables = tables_by_version[CURRENT_CONTENT]
	var run = {
		"id": id,
		"ledger": {"contentVersion": CURRENT_CONTENT, "tablesFingerprint": fingerprints[CURRENT_CONTENT], "entries": []},
		"notes": {}, "markedGoals": []
	}
	var state = _empty_world()
	for event in [_event("sessionStart"), _event("visit", tables.spawnRoom)]:
		var result = _step(state, event, tables)
		if not result.ok:
			return _fail(result.error)
		state = result.world
		run.ledger.entries.append(_entry(event, run.ledger.entries.size()))
	if _in_contact(state, tables):
		var death = _event("death")
		state = _step(state, death, tables).world
		run.ledger.entries.append(_entry(death, run.ledger.entries.size()))
	var next = archive.duplicate(true)
	next.runs.append(run)
	next.activeRunID = null if _is_terminal(state) else id
	if not _commit(next):
		return false
	world = state
	last_ending = ""
	last_record = {}
	return true


func resume_session() -> bool:
	return perform("sessionStart")


func can_visit(room: String) -> bool:
	if _active_run() == null:
		return false
	return _step(world, _event("visit", room), tables_for_active()).ok


func perform(kind: String, id = "") -> bool:
	var current = _active_run()
	if not ready or current == null:
		return _fail("There is no active delve.")
	var tables = tables_for_active()
	var effects = tables.switchEffects.get(id, []) if kind == "action" else []
	var event = _event(kind, id, effects)
	var decoded = _decode_event(_entry(event, 0), 0)
	if not decoded.ok:
		return _fail(decoded.error)
	var result = _step(world, event, tables)
	if not result.ok:
		return _fail(result.error)
	var state = result.world
	var next = archive.duplicate(true)
	var next_run = null
	for run in next.runs:
		if run.id == current.id:
			next_run = run
			break
	next_run.ledger.entries.append(_entry(event, next_run.ledger.entries.size()))
	if _in_contact(state, tables):
		var death = _event("death")
		var death_result = _step(state, death, tables)
		if not death_result.ok:
			return _fail(death_result.error)
		state = death_result.world
		next_run.ledger.entries.append(_entry(death, next_run.ledger.entries.size()))
	if _is_terminal(state):
		next.activeRunID = null
	if not _commit(next):
		return false
	world = state
	if _is_terminal(state):
		last_record = _record(next_run, state)
		if state.finished:
			last_ending = "You reached the dawn well. The delve is complete."
		elif state.dead:
			last_ending = "The patrol ended your delve. Your run is preserved."
		else:
			last_ending = "You retreated. Your run is preserved."
	return true


func save_note(room: String, text: String) -> bool:
	var current = _active_run()
	if current == null or not world.visited.has(room):
		return _fail("Notes can only be saved for visited rooms.")
	if _exceeds_character_limit(text, 10000) or text.to_utf8_buffer().has(0):
		return _fail("A note must be at most 10,000 characters and cannot contain NUL.")
	var next = archive.duplicate(true)
	for run in next.runs:
		if run.id == current.id:
			if text.is_empty():
				run.notes.erase(room)
			else:
				run.notes[room] = text
			break
	return _commit(next)


func mark_goal(goal_id: String, marked: bool) -> bool:
	var current = _active_run()
	var quest = quest_for_active()
	if current == null or quest.is_empty():
		return _fail("There is no quest for this run.")
	var valid = false
	for goal in quest.goals:
		if goal.id == goal_id:
			valid = true
	if not valid:
		return _fail("Unknown quest goal.")
	var next = archive.duplicate(true)
	for run in next.runs:
		if run.id == current.id:
			if marked and not run.markedGoals.has(goal_id):
				run.markedGoals.append(goal_id)
			elif not marked:
				run.markedGoals.erase(goal_id)
			run.markedGoals.sort()
			break
	return _commit(next)


func set_confirm_new_run(enabled: bool) -> bool:
	var next = archive.duplicate(true)
	next.settings.confirmNewRun = enabled
	return _commit(next)


func goal_progress(goal: Dictionary, run: Dictionary) -> String:
	var progress = "unknown"
	for entry in run.ledger.entries:
		var decoded = _decode_event(entry, int(entry.sequence))
		if not decoded.ok:
			return "unavailable"
		var event = decoded.event
		if progress == "unknown" and _evidence_matches(goal.firstEvidence, event):
			progress = "in_progress"
		elif progress == "in_progress" and _evidence_matches(goal.completionEvidence, event):
			progress = "achieved"
	return progress


func _evidence_matches(evidence: Dictionary, event: Dictionary) -> bool:
	match evidence.kind:
		"visit":
			return event.has("visit") and event.visit.room == evidence.id
		"action":
			return event.has("action") and event.action.element == evidence.id
		"discovery":
			return event.has("discovery") and event.discovery.id == evidence.id
	return false


func current_record() -> Dictionary:
	var run = _active_run()
	if run == null:
		return {}
	return _record(run, world)


func _record(run: Dictionary, state: Dictionary) -> Dictionary:
	var sessions = 0
	var first_is_session = false
	for index in range(run.ledger.entries.size()):
		var decoded = _decode_event(run.ledger.entries[index], index)
		if decoded.ok and decoded.event.has("sessionStart"):
			sessions += 1
			if index == 0:
				first_is_session = true
	var found = state.discoveries.duplicate()
	found.sort()
	return {
		"rooms": state.visited.size(), "steps": state.step,
		"sessions": str(sessions) if first_is_session else "unknown", "discoveries": found
	}


func export_backup(path: String) -> bool:
	return _write_export(path, JSON.stringify(archive, "\t", true) + "\n")


func export_csv(path: String) -> bool:
	var rows: Array[String] = []
	rows.append(_csv_row(["run_id", "content_version", "kind", "id", "text", "marked_by_player", "dungeon_progress"]))
	var runs = archive.runs.duplicate()
	runs.sort_custom(func(a, b): return a.id < b.id)
	for run in runs:
		var version = run.ledger.contentVersion
		var rooms = run.notes.keys()
		rooms.sort()
		for room in rooms:
			rows.append(_csv_row([run.id, str(version), "note", room, run.notes[room], "", ""]))
		if quests_by_version.has(version):
			for goal in quests_by_version[version].goals:
				rows.append(_csv_row([run.id, str(version), "quest", goal.id, goal.text, str(run.markedGoals.has(goal.id)).to_lower(), goal_progress(goal, run)]))
	return _write_export(path, "\r\n".join(rows) + "\r\n")


func _csv_row(values: Array) -> String:
	var fields: Array[String] = []
	for item in values:
		var value = str(item)
		var index = 0
		while index < value.length() and _is_whitespace(value.unicode_at(index)):
			index += 1
		if (index < value.length() and "=+-@".contains(value[index])) or value.begins_with("\t") or value.begins_with("\r"):
			value = "'" + value
		fields.append("\"" + value.replace("\"", "\"\"") + "\"")
	return ",".join(fields)


func _is_whitespace(codepoint: int) -> bool:
	return (codepoint >= 0x09 and codepoint <= 0x0d) or codepoint in [
		0x20, 0x85, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000
	] or (codepoint >= 0x2000 and codepoint <= 0x200a)


func _write_export(path: String, text: String) -> bool:
	var absolute = ProjectSettings.globalize_path(path)
	var save_absolute = ProjectSettings.globalize_path(save_path)
	if OS.get_name() == "Windows":
		absolute = absolute.to_lower()
		save_absolute = save_absolute.to_lower()
	if absolute == save_absolute or absolute == save_absolute + ".tmp":
		return _fail("Choose a different file from the active game save.")
	var temp_path = path + ".delve-" + Crypto.new().generate_random_bytes(16).hex_encode() + ".tmp"
	if FileAccess.file_exists(temp_path):
		return _fail("Could not create a unique temporary export file.")
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("Could not open the export file (error %s)." % FileAccess.get_open_error())
	file.store_string(text)
	file.flush()
	var result = file.get_error()
	file.close()
	if result != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return _fail("Could not write the export file (error %s)." % result)
	result = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path))
	if result != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return _fail("Could not replace the export file (error %s)." % result)
	error_message = ""
	return true


func preview_restore(path: String) -> Dictionary:
	restore_preview = {}
	var data = _read_json(path)
	if not data.ok:
		_fail("Backup could not be previewed: " + data.error)
		return {}
	var checked = _validate_archive(data.value)
	if not checked.ok:
		_fail("Backup could not be previewed: " + checked.error)
		return {}
	var replacement = checked.archive
	var before = {}
	var after = {}
	for run in archive.runs:
		before[run.id] = run
	for run in replacement.runs:
		after[run.id] = run
	var added = 0
	var removed = 0
	var changed = 0
	var unchanged = 0
	for id in before:
		if not after.has(id):
			removed += 1
		elif _canonical_json(before[id]) != _canonical_json(after[id]):
			changed += 1
		else:
			unchanged += 1
	for id in after:
		if not before.has(id):
			added += 1
	restore_preview = {
		"replacement": replacement,
		"baseline": _canonical_json(archive),
		"disk_revision": disk_revision,
		"added": added, "removed": removed, "changed": changed, "unchanged": unchanged,
		"events_before": _count_rows(archive, "events"), "events_after": _count_rows(replacement, "events"),
		"notes_before": _count_rows(archive, "notes"), "notes_after": _count_rows(replacement, "notes"),
		"marks_before": _count_rows(archive, "marks"), "marks_after": _count_rows(replacement, "marks"),
		"active_before": archive.activeRunID, "active_after": replacement.activeRunID,
		"settings_changed": archive.settings != replacement.settings
	}
	error_message = ""
	return restore_preview


func _count_rows(data: Dictionary, kind: String) -> int:
	var count = 0
	for run in data.runs:
		match kind:
			"events":
				count += run.ledger.entries.size()
			"notes":
				count += run.notes.size()
			"marks":
				count += run.markedGoals.size()
	return count


func restore_confirmed() -> bool:
	if restore_preview.is_empty():
		return _fail("Preview a backup before restoring.")
	if restore_preview.baseline != _canonical_json(archive) or restore_preview.disk_revision != disk_revision or _disk_revision() != disk_revision:
		restore_preview = {}
		return _fail("Local data changed after the preview. Preview the backup again.")
	var checked = _validate_archive(restore_preview.replacement)
	if not checked.ok:
		restore_preview = {}
		return _fail("Restore failed; local data was preserved. " + checked.error)
	if not _commit(checked.archive):
		restore_preview = {}
		return false
	restore_preview = {}
	world = _empty_world()
	if _active_run() != null:
		world = _replay(_active_run(), tables_for_active()).world
	last_ending = ""
	last_record = {}
	return true
