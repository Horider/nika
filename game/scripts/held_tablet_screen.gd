@tool
extends Node2D

## The small, foreshortened screen remains text, separate from the tablet art.
func _draw() -> void:
	var page := get_parent()
	while page and not page.has_meta("page_id"):
		page = page.get_parent()
	var key := str(page.get_meta("page_id")) if page else "D02-S05-03"
	var text: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/text.json"))
	var content: Dictionary = text.get(key, {})
	# The same results remain open during the following spoken replies.
	var results: Dictionary = text.get("D02-S05-03", {})
	var font: Font = preload("res://scripts/game_fonts.gd").get_font("sans")
	draw_string(font, Vector2(0, 0), str(content.get("document_title", "Результаты · день 2")), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("33464c"))
	for i in 5:
		var field := "document_line_" + str(i)
		var line := str(content.get(field, results.get(field, "")))
		draw_string(font, Vector2(0, 30 + i * 25), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("42525a"))
