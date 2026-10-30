@tool
extends Node2D

## Text is loaded from data/text.json, independently of art and scene geometry.
@export var page_key: String = "":
	set(value):
		page_key = value
		queue_redraw()
@export var text_key: String = "":
	set(value):
		text_key = value
		queue_redraw()
@export var font_kind: String = "serif"
@export var font_px: float = 23.0
@export var wrap_width: float = 430.0
@export var line_spacing: float = 1.4
@export var max_lines: int = 12
@export var wrap_text: bool = true
@export var ink: Color = Color("f3ecdf")
static var text_cache: Dictionary = {}
static var text_modified: int = -1
static var fonts: Dictionary = {}

func _ready() -> void:
	# Packaged web fonts have different metrics from the desktop system fonts.
	# Fit the existing text box without changing the desktop staging or strings.
	if preload("res://scripts/game_fonts.gd").portable():
		var minimum := maxf(14.0, floorf(font_px * 0.8))
		while font_px > minimum:
			var lines := get_lines()
			var overflow := lines.size() > max_lines
			for line in lines:
				if get_font().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(font_px)).x > wrap_width: overflow = true
			if not overflow: break
			font_px -= 1.0
		# Tablet paragraphs are separate nodes. Reflow them using the actual
		# bundled-font metrics instead of desktop line-count assumptions.
		if text_key.begins_with("document_line_"):
			for previous in get_parent().get_children():
				if previous == self: break
				if not previous.text_key.begins_with("document_"): continue
				var bottom: float = previous.position.y + max(0, previous.get_lines().size() - 1) * previous.font_px * previous.line_spacing + previous.get_font().get_descent(roundi(previous.font_px))
				position.y = maxf(position.y, bottom + get_font().get_ascent(roundi(font_px)) + 8.0)
	queue_redraw()

func get_font() -> Font:
	return preload("res://scripts/game_fonts.gd").get_font(font_kind)

func get_text() -> String:
	var modified := FileAccess.get_modified_time("res://data/text.json")
	if text_modified != modified or text_cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/text.json"))
		text_cache = parsed if parsed is Dictionary else {}
		text_modified = modified
	return str(text_cache.get(page_key, {}).get(text_key, ""))

func get_lines() -> PackedStringArray:
	var value := get_text()
	if not wrap_text:
		return PackedStringArray([value])
	var lines := PackedStringArray()
	var font := get_font()
	for paragraph in value.split("\n"):
		var line := ""
		for word in paragraph.split(" ", false):
			var candidate := word if line.is_empty() else line + " " + word
			if not line.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(font_px)).x > wrap_width:
				lines.append(line)
				line = word
			else:
				line = candidate
		if not line.is_empty():
			lines.append(line)
	return lines

func _draw() -> void:
	var font := get_font()
	var lines := get_lines()
	for i in lines.size():
		draw_string(font, Vector2(0, i * font_px * line_spacing), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(font_px), ink)

func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray(["Текст превышает число строк; измените текст или область."]) if get_lines().size() > max_lines else PackedStringArray()
