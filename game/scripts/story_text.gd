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
	if text_key == "dialogue" and _fit_dialogue_panel():
		queue_redraw()
		return
	# Descriptions share a column. Fit and space the whole column together:
	# shrinking each paragraph to its old line count produced mismatched type.
	if text_key.begins_with("description_"):
		var paragraphs: Array[Node] = []
		for sibling in get_parent().get_children():
			if sibling.get_script() == get_script() and sibling.text_key.begins_with("description_"):
				paragraphs.append(sibling)
		if paragraphs.back() == self:
			_layout_descriptions(paragraphs)
		return
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

func _fit_dialogue_panel() -> bool:
	var art := get_parent().get_parent().get_node_or_null("Art")
	if not art: return false
	var panel: Sprite2D
	for layer in art.get_children():
		if layer is Sprite2D and layer.texture and layer.texture.resource_path.get_file().begins_with("panel-"):
			panel = layer
			break
	if not panel: return false
	var speaker := get_parent().get_node_or_null("speaker")
	var original_position := panel.position
	var original_scale := panel.scale
	var original_size := panel.texture.get_size() * panel.scale
	var original_dialogue := position - original_position
	var original_speaker: Vector2 = speaker.position - original_position if speaker else Vector2.ZERO
	var original_width := wrap_width
	var width := original_size.x
	var maximum_width := maxf(width, minf(1040.0, 1552.0 - original_position.x))
	var minimum_font := maxf(18.0, floorf(font_px * 0.8))
	while true:
		var ratio := width / original_size.x
		panel.scale = original_scale * ratio
		# Grow the existing artwork proportionally, keeping its bottom fixed.
		panel.position.y = original_position.y + original_size.y * (1.0 - ratio)
		position = panel.position + original_dialogue * ratio
		wrap_width = original_width * ratio
		if speaker: speaker.position = panel.position + original_speaker * ratio
		var bottom: float = position.y + max(0, get_lines().size() - 1) * font_px * line_spacing + get_font().get_descent(roundi(font_px))
		var inner_bottom := panel.position.y + panel.texture.get_height() * panel.scale.y - 20.0 * width / 720.0
		var below_speaker: bool = not speaker or position.y - get_font().get_ascent(roundi(font_px)) >= speaker.position.y + speaker.get_font().get_descent(roundi(speaker.font_px)) + 5.0
		if bottom <= minf(875.0, inner_bottom) and below_speaker and get_lines().size() <= max_lines: break
		if width < maximum_width:
			width = minf(maximum_width, width + 16.0)
		elif font_px > minimum_font:
			font_px -= 1.0
		else: break
	return true

func _layout_descriptions(paragraphs: Array[Node]) -> void:
	var authored_y: Array[float] = []
	var size: float = paragraphs[0].font_px
	var limit := 800.0
	for paragraph in paragraphs:
		authored_y.append(paragraph.position.y)
		size = minf(size, paragraph.font_px)
	# The artwork's dialogue panel is the lower boundary, not a desktop
	# estimate of how many lines a particular paragraph should contain.
	var art := get_parent().get_parent().get_node_or_null("Art")
	if art:
		for layer in art.get_children():
			if layer is Sprite2D and "dialogue" in str(layer.name):
				limit = minf(limit, layer.position.y - 20.0)
	for sibling in get_parent().get_children():
		if sibling.get_script() != get_script() or sibling.text_key != "sound": continue
		limit = minf(limit, sibling.position.y - sibling.get_font().get_ascent(roundi(sibling.font_px)) - 16.0)
	var minimum := maxf(18.0, floorf(size * 0.8))
	while true:
		var bottom := 0.0
		for i in paragraphs.size():
			var paragraph := paragraphs[i]
			paragraph.font_px = size
			paragraph.position.y = authored_y[i]
			if i > 0:
				paragraph.position.y = maxf(paragraph.position.y, bottom + paragraph.get_font().get_ascent(roundi(size)) + 17.0)
			bottom = paragraph.position.y + max(0, paragraph.get_lines().size() - 1) * size * paragraph.line_spacing + paragraph.get_font().get_descent(roundi(size))
		if bottom <= limit or size <= minimum: break
		size -= 1.0
	for paragraph in paragraphs:
		# Line count is now determined by the actual font and available column.
		paragraph.max_lines = maxi(paragraph.max_lines, paragraph.get_lines().size())
		paragraph.queue_redraw()

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
