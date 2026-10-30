extends Node2D

const Flow = preload("res://scripts/story_flow.gd")
const SaveStore = preload("res://scripts/save_store.gd")
@export_range(0, 3) var start_day: int = 0
var flow: RefCounted
var catalog: Dictionary
var strings: Dictionary
var page_scene: Node2D
var interaction := Control.new()
var overlay := Control.new()
var audio := AudioStreamPlayer.new()
var pan := AudioEffectPanner.new()
var audio_group := ""
var max_audio_seconds: float = -1.0
var muted := false
var running := false
var overlay_open := false
var autosave_enabled := true
var menu_font: Font
var title_font: Font
var menu_message := ""

func _ready() -> void:
	if has_node("EditorPreview"): get_node("EditorPreview").free()
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
	strings = JSON.parse_string(FileAccess.get_file_as_string("res://data/text.json"))
	flow = Flow.new(catalog)
	menu_font = preload("res://scripts/game_fonts.gd").get_font("sans")
	title_font = preload("res://scripts/game_fonts.gd").get_font("serif")
	interaction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(interaction)
	overlay.visible = false
	add_child(overlay)
	add_child(audio)
	if AudioServer.get_bus_index("SceneSFX") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SceneSFX")
	AudioServer.add_bus_effect(AudioServer.get_bus_index("SceneSFX"), pan)
	audio.bus = "SceneSFX"
	if OS.has_feature("web"): audio.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK: muted = bool(config.get_value("audio", "muted", false))
	var args := OS.get_cmdline_user_args()
	if "--capture" in args:
		autosave_enabled = false
		_capture_pages.call_deferred(args)
	elif start_day > 0:
		_start_game(start_day)
	else:
		_main_menu()

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _label(parent: Node, text: String, box: Rect2, size: int = 24, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = box.position
	label.size = box.size
	label.add_theme_font_override("font", title_font if heading else menu_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("f3ecdf"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, box: Rect2, callback: Callable, transparent: bool = false) -> Button:
	var button := Button.new()
	button.position = box.position
	button.size = box.size
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", menu_font)
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", Color("26323d"))
	button.add_theme_color_override("font_hover_color", Color("26323d"))
	button.add_theme_color_override("font_pressed_color", Color("26323d"))
	button.add_theme_color_override("font_focus_color", Color("26323d"))
	button.add_theme_color_override("font_disabled_color", Color("74756e"))
	for style in ["normal", "hover", "pressed", "focus", "disabled"]:
		var background := StyleBoxFlat.new()
		background.bg_color = Color(1, 0.88, 0.65, .09) if transparent and style in ["hover", "focus"] else Color(0, 0, 0, 0) if transparent else Color("f0dfbb") if style == "hover" else Color("dfd3ba")
		background.set_corner_radius_all(2)
		button.add_theme_stylebox_override(style, background)
	button.pressed.connect(callback, CONNECT_DEFERRED)
	parent.add_child(button)
	return button

func _show_overlay(title: String, subtitle: String = "") -> void:
	_clear(overlay)
	if is_instance_valid(page_scene) and page_scene.has_node("VideoPlayback"):
		page_scene.get_node("VideoPlayback").set_process(false)
	if is_instance_valid(page_scene) and page_scene.has_node("Art/BirdFlight"):
		page_scene.get_node("Art/BirdFlight").set_process(false)
	overlay_open = true
	overlay.visible = true
	interaction.visible = false
	var shade := ColorRect.new()
	shade.size = Vector2(1600, 900)
	shade.color = Color(0.055, .09, .115, .96)
	overlay.add_child(shade)
	_label(overlay, title, Rect2(100, 90, 1380, 90), 52, true)
	if not subtitle.is_empty(): _label(overlay, subtitle, Rect2(104, 195, 1280, 85), 23)

func _main_menu() -> void:
	audio.stop()
	audio_group = ""
	_show_overlay("Пока идёт запись", "Ника · три визита")
	var saved := SaveStore.read(SaveStore.AUTO_PATH, catalog)
	var resume := _button(overlay, "Продолжить", Rect2(104, 310, 460, 64), _resume_save)
	resume.disabled = not saved.ok
	_button(overlay, "Новая игра · день 1", Rect2(104, 395, 460, 64), _start_game.bind(1))
	_button(overlay, "Начать с дня 2", Rect2(104, 480, 460, 64), _start_game.bind(2))
	_button(overlay, "День 3 · отдельный просмотр", Rect2(770, 720, 670, 62), _start_game.bind(3))
	_button(overlay, "Звук: " + ("выключен" if muted else "включён"), Rect2(104, 565, 460, 64), _menu_mute)
	if not OS.has_feature("web"): _button(overlay, "Выход", Rect2(104, 650, 460, 64), get_tree().quit)
	_label(overlay, "Пробел / Enter / стрелка вправо — далее\nEsc — меню паузы\nH — прочитанное · J — отчёты\nM — звук · F11 — полный экран", Rect2(770, 330, 670, 260), 25)
	if saved.ok:
		_label(overlay, "Сохранение: день " + str(int(saved.state.day)) + (" · визит завершён" if saved.state.finished else ""), Rect2(770, 630, 670, 60), 22)
	if not menu_message.is_empty(): _label(overlay, menu_message, Rect2(104, 770, 1330, 70), 22)

func _start_game(day: int) -> void:
	# Keep the previous run separately when explicitly beginning a new one.
	if autosave_enabled and FileAccess.file_exists(SaveStore.AUTO_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SaveStore.AUTO_PATH), ProjectSettings.globalize_path("user://previous-run.json"))
	flow.new_game(day)
	running = true
	_save()
	_render_page()

func _save(path: String = SaveStore.AUTO_PATH) -> bool:
	if not autosave_enabled: return true
	var error := SaveStore.write(path, flow.snapshot())
	if error != OK:
		menu_message = "Не удалось сохранить игру: " + error_string(error)
		push_error(menu_message)
		return false
	return true

func _resume_save(path: String = SaveStore.AUTO_PATH) -> void:
	var saved := SaveStore.read(path, catalog)
	if not saved.ok or not flow.restore(saved.state):
		menu_message = "Сохранение недоступно. Можно начать новую игру."
		_main_menu()
		return
	running = true
	if path != SaveStore.AUTO_PATH: _save()
	_render_page()

func _render_page() -> void:
	overlay.visible = false
	overlay_open = false
	interaction.visible = true
	if flow.state.finished:
		_show_end()
		return
	var page: Dictionary = flow.current()
	var bird_time := -1.0
	var video_time := -1.0
	if is_instance_valid(page_scene) and page_scene.has_node("VideoPlayback") and str(page_scene.get_meta("page_id", "")) == page.id:
		video_time = page_scene.get_node("VideoPlayback").flight.elapsed
	if is_instance_valid(page_scene) and page_scene.has_node("Art/BirdFlight"):
		var previous_id := str(page_scene.get_meta("page_id", ""))
		if previous_id == page.id or (previous_id == "D02-S08-01" and page.id == "D02-S08-02") or (previous_id == "D02-S08-02" and page.id == "D02-S08-03"):
			bird_time = page_scene.get_node("Art/BirdFlight").elapsed
	if is_instance_valid(page_scene): page_scene.free()
	var scene_path: String = page.get("packed_scene_promise", page.packed_scene) if flow.state.results == "promise" else page.packed_scene
	var packed: PackedScene = load(scene_path)
	page_scene = packed.instantiate()
	add_child(page_scene)
	move_child(page_scene, 0)
	if video_time >= 0 and page_scene.has_node("VideoPlayback"):
		page_scene.get_node("VideoPlayback").flight.seek(video_time)
	# This branch has already packed the test pouches during the camera cross-cuts.
	if flow.state.results == "promise" and page.has("packing_state") and page_scene.has_node("Art/PackingStage/Equipment"):
		page_scene.get_node("Art/PackingStage/Equipment").visible = false
	if bird_time >= 0.0 and page_scene.has_node("Art/BirdFlight"):
		var flight := page_scene.get_node("Art/BirdFlight")
		flight.seek(maxf(bird_time, [0.0, 6.0, 8.0][flight.phase]))
	_clear(interaction)
	if page.choices.is_empty():
		_button(interaction, "", Rect2(1394, 826, 158, 51), _next, true).tooltip_text = "Далее"
	else:
		for choice in page.choices:
			_button(interaction, "", Rect2(choice.x, choice.y, choice.width, choice.height), _choose.bind(str(choice.value)), true).tooltip_text = str(strings[page.id][choice.text_field])
	if page.has("replay_rect"):
		var box: Array = page.replay_rect
		_button(interaction, "", Rect2(box[0], box[1], box[2], box[3]), _replay_audio, true).tooltip_text = "Прослушать сигналы"
	_set_audio(page)

func _next(automatic: bool = false) -> void:
	if overlay_open: return
	if not automatic and is_instance_valid(page_scene) and page_scene.has_node("Art/BirdFlight"):
		var flight := page_scene.get_node("Art/BirdFlight")
		if flight.elapsed < flight.VANISH_TIME and flow.skip_bird_flight():
			_save()
			_render_page()
			return
	if flow.advance():
		_save()
		_render_page()

func _choose(value: String) -> void:
	if overlay_open: return
	if flow.choose(value):
		_save()
		_render_page()

func _set_audio(page: Dictionary, replay: bool = false) -> void:
	var spec: Dictionary = page.get("audio", {})
	if spec.is_empty() or muted:
		audio.stop()
		audio_group = ""
		return
	var group := str(spec.get("group", page.id))
	if group == audio_group and not replay: return
	audio.stop()
	audio_group = group
	audio.stream = load(catalog.assets[spec.assetId].path)
	if bool(spec.get("loop", false)) and audio.stream is AudioStreamWAV:
		audio.stream = audio.stream.duplicate()
		audio.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		audio.stream.loop_begin = 0
		audio.stream.loop_end = roundi(audio.stream.get_length() * audio.stream.mix_rate)
	audio.volume_db = float(spec.get("volume_db", -7))
	pan.pan = float(spec.get("pan", 0))
	max_audio_seconds = float(spec.get("max_seconds", -1))
	audio.play()

func _process(_delta: float) -> void:
	if audio.playing and max_audio_seconds > 0 and audio.get_playback_position() >= max_audio_seconds:
		audio.stop()
	if running and not overlay_open and is_instance_valid(page_scene) and page_scene.has_node("Art/BirdFlight"):
		if page_scene.get_node("Art/BirdFlight").phase_finished():
			_next(true)

func _replay_audio() -> void:
	_set_audio(flow.current(), true)

func _mute() -> void:
	muted = not muted
	if muted: audio.stop()
	elif running and not overlay_open: _set_audio(flow.current(), true)
	var config := ConfigFile.new()
	config.set_value("audio", "muted", muted)
	config.save("user://settings.cfg")

func _menu_mute() -> void:
	_mute()
	_main_menu()

func _pause() -> void:
	if not running:
		_main_menu()
		return
	_show_overlay("Пауза", "Прогресс и решения сохраняются после каждого шага.")
	_button(overlay, "Вернуться", Rect2(104, 310, 460, 62), _render_page)
	_button(overlay, "Сохранить вручную", Rect2(104, 390, 460, 62), _manual_save)
	_button(overlay, "Загрузить вручную", Rect2(104, 470, 460, 62), _resume_save.bind(SaveStore.MANUAL_PATH)).disabled = not SaveStore.read(SaveStore.MANUAL_PATH, catalog).ok
	_button(overlay, "Прочитанное", Rect2(104, 550, 460, 62), _history)
	_button(overlay, "Отчёты", Rect2(104, 630, 460, 62), _journal)
	_button(overlay, "Главное меню", Rect2(104, 710, 460, 62), _main_menu)

func _manual_save() -> void:
	if _save(SaveStore.MANUAL_PATH):
		_pause()
		_label(overlay, "Сохранено", Rect2(770, 390, 500, 60), 25)

func _reading_panel(title: String, content: String) -> void:
	_show_overlay(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(104, 205)
	scroll.size = Vector2(1392, 540)
	overlay.add_child(scroll)
	var label := RichTextLabel.new()
	label.custom_minimum_size = Vector2(1340, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.fit_content = true
	label.bbcode_enabled = false
	label.text = content
	label.add_theme_font_override("normal_font", menu_font)
	label.add_theme_font_size_override("normal_font_size", 24)
	scroll.add_child(label)
	_button(overlay, "Вернуться", Rect2(104, 785, 260, 60), _render_page)

func _history() -> void:
	if not running: return
	var content := ""
	for entry in flow.state.history:
		var text: Dictionary = entry.text
		content += str(text.get("title", "")) + "\n"
		for field in ["description_1", "description_2"]:
			if text.has(field): content += str(text[field]) + "\n"
		if text.has("dialogue"): content += str(text.get("speaker", "")) + ": " + str(text.dialogue) + "\n"
		content += "\n"
	_reading_panel("Прочитанное", content if not content.is_empty() else "Здесь появятся завершённые реплики.")

func _journal() -> void:
	if not running: return
	var content := ""
	for day in flow.state.reports:
		content += "День " + day + "\n"
		var report: Dictionary = flow.state.reports[day]
		for field in report:
			if str(field).begins_with("document_line_"): content += str(report[field]) + "\n"
		content += "\n"
	_reading_panel("Отправленные отчёты", content if not content.is_empty() else "Отправленных отчётов пока нет. Результаты появятся после завершения визита.")

func _show_end() -> void:
	audio.stop()
	var text := "Ваши решения и отчёты сохранены."
	if flow.state.facts.get("employer_dismissed", false): text = "Допуск к следующим визитам прекращён. Отчёт и история сохранены."
	_show_overlay("Третий визит завершён" if flow.state.day == 3 else "Второй визит завершён", text)
	_button(overlay, "Отчёты", Rect2(104, 330, 460, 64), _journal)
	_button(overlay, "Прочитанное", Rect2(104, 420, 460, 64), _history)
	_button(overlay, "Главное меню", Rect2(104, 510, 460, 64), _main_menu)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_ESCAPE:
			if overlay_open and running: _render_page()
			else: _pause()
		KEY_H: _history()
		KEY_J: _journal()
		KEY_M: _mute()
		KEY_F11:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_SPACE, KEY_ENTER, KEY_RIGHT:
			if running and not overlay_open: _next()
		_: return
	get_viewport().set_input_as_handled()

func _capture_pages(args: PackedStringArray) -> void:
	# Isolated render audit: no save file, decision or event is written.
	var target := "res://review/captures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target))
	var selected := PackedStringArray(["D01-01", "D01-10", "D01-12", "D01-14", "D01-15", "D01-17", "D01-23", "D01-27", "D01-35", "D01-40", "D02-S00-07", "D02-S02-03", "D02-S02-07", "D02-S03-06", "D02-S05-02", "D02-S06-03", "D02-S07-05", "D02-S08-unseen-04", "D02-S09-02", "D02-S10-07"])
	if "--all-pages" in args: selected = PackedStringArray(catalog.pages.keys())
	overlay.visible = false
	interaction.visible = false
	for pid in selected:
		if is_instance_valid(page_scene): page_scene.free()
		page_scene = load(catalog.pages[pid].packed_scene).instantiate()
		add_child(page_scene)
		move_child(page_scene, 0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(target + "/" + pid + ".png")
	print("CAPTURE_OK ", selected.size())
	get_tree().quit()
