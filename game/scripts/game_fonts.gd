extends RefCounted
static var cache: Dictionary = {}
static func portable() -> bool:
	return OS.has_feature("web") or "--web-font-check" in OS.get_cmdline_user_args()
static func get_font(kind: String) -> Font:
	if cache.has(kind): return cache[kind]
	var font: Font
	if portable():
		var variation := FontVariation.new()
		variation.base_font = load("res://assets/fonts/NotoSerif-Italic.ttf" if kind == "italic" else "res://assets/fonts/NotoSerif.ttf" if kind == "serif" else "res://assets/fonts/NotoSans.ttf")
		variation.variation_opentype = {"wght":700 if kind == "bold" else 400}
		font = variation
	else:
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["Cambria","Georgia","Times New Roman"]) if kind in ["serif","italic"] else PackedStringArray(["Segoe UI","Arial"])
		system.font_weight = 700 if kind == "bold" else 400
		system.font_italic = kind == "italic"
		font = system
	cache[kind] = font
	return font
