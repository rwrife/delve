extends Control

var world: Dictionary = {}
var tables: Dictionary = {}
var exits: Array = []
var available: Array = []


func configure(state: Dictionary, rules: Dictionary, connections: Array, allowed: Array) -> void:
	world = state
	tables = rules
	exits = connections
	available = allowed
	queue_redraw()


func _draw() -> void:
	if world.is_empty():
		return
	var frame = Rect2(Vector2(4, 4), size - Vector2(8, 8))
	var floor_rect = Rect2(Vector2(17, 17), size - Vector2(34, 34))
	draw_rect(frame, Color("#564b3e"))
	draw_rect(floor_rect, Color("#262a2e"))
	for x in range(40, int(size.x) - 20, 54):
		draw_line(Vector2(x, 20), Vector2(x, size.y - 20), Color("#323438"), 1.0)
	for y in range(42, int(size.y) - 20, 42):
		draw_line(Vector2(20, y), Vector2(size.x - 20, y), Color("#323438"), 1.0)
	var font = ThemeDB.fallback_font
	for index in range(exits.size()):
		var x = size.x * float(index + 1) / float(exits.size() + 1)
		var door_color = Color("#d8c493") if available[index] else Color("#926860")
		draw_rect(Rect2(x - 20, 13, 40, 35), Color("#111719"))
		draw_rect(Rect2(x - 20, 13, 40, 35), door_color, false, 3.0)
		draw_string(font, Vector2(x - 6, 39), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, door_color)
	var center = Vector2(size.x * 0.5, size.y * 0.57)
	draw_circle(center + Vector2(0, 5), 18, Color("#111719"))
	draw_circle(center, 14, Color("#f0e2bc"))
	draw_circle(center - Vector2(4, 4), 4, Color("#ffffff"))
	var room = world.room
	var icon_x = size.x * 0.24
	for key in tables.keySpawns:
		if tables.keySpawns[key] == room:
			_diamond(Vector2(icon_x, size.y * 0.70), Color("#ddbc68") if not world.keys.has(key) else Color("#8f8b77"))
			draw_string(font, Vector2(icon_x - 17, size.y * 0.88), "KEY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#e6d9ba"))
			icon_x += 35
	icon_x = size.x * 0.76
	for element in tables.get("switchRooms", {}):
		if tables.switchRooms[element] == room:
			var on = true
			for effect in tables.switchEffects[element]:
				on = on and world.flags.has(effect)
			var point = Vector2(icon_x, size.y * 0.70)
			draw_colored_polygon(PackedVector2Array([point + Vector2(0, -13), point + Vector2(13, 11), point + Vector2(-13, 11)]), Color("#e5ad68") if on else Color("#877363"))
			draw_string(font, Vector2(icon_x - 24, size.y * 0.88), "SWITCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#e6d9ba"))
			icon_x += 35
	for id in tables.discoverySpawns:
		if tables.discoverySpawns[id] == room:
			var point = Vector2(size.x * 0.25, size.y * 0.38)
			var tint = Color("#829c9e") if world.discoveries.has(id) else Color("#b5e0dc")
			draw_line(point + Vector2(-10, 0), point + Vector2(10, 0), tint, 3.0)
			draw_line(point + Vector2(0, -10), point + Vector2(0, 10), tint, 3.0)
			draw_circle(point, 3, tint)


func _diamond(point: Vector2, tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([point + Vector2(0, -12), point + Vector2(10, 0), point + Vector2(0, 12), point + Vector2(-10, 0)]), tint)
