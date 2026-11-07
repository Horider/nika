extends Node2D

const Flow = preload("res://scripts/story_flow.gd")
const SaveStore = preload("res://scripts/save_store.gd")
@export_range(0, 10) var start_day: int = 0
var flow: RefCounted
var catalog: Dictionary
var strings: Dictionary
var page_scene: Node2D
var evidence: Node
var audio_cursor: Line2D
var audio_start_seconds := 0.0
var playback_page := ""
var playback_elapsed := 0.0
var playback_duration := 0.0
var interaction := Control.new()
var overlay := Control.new()
var audio := AudioStreamPlayer.new()
var pan := AudioEffectPanner.new()
var audio_group := ""
var max_audio_seconds: float = -1.0
var muted := false
var show_trust := true
var running := false
var overlay_open := false
var autosave_enabled := true
var replaying := false
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
	if config.load("user://settings.cfg") == OK:
		muted = bool(config.get_value("audio", "muted", false))
		show_trust = bool(config.get_value("display", "show_trust", true))
	var args := OS.get_cmdline_user_args()
	if "--capture" in args:
		autosave_enabled = false
		_capture_pages.call_deferred(args)
	elif start_day > 0 and OS.is_debug_build():
		_start_game(start_day, true)
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

func _show_overlay(title: String, subtitle: String = "") -> Label:
	_clear(overlay)
	if audio.playing: audio.stream_paused = true
	if is_instance_valid(evidence): evidence.set_process(false)
	if is_instance_valid(page_scene) and page_scene.has_node("BookFilm"):
		page_scene.get_node("BookFilm").paused = true
	if is_instance_valid(page_scene) and page_scene.has_node("Art") and page_scene.get_node("Art").has_method("pose_at"):
		page_scene.get_node("Art").set_process(false)
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
	var heading := _label(overlay, title, Rect2(100, 90, 1400, 90), 52, true)
	if not subtitle.is_empty(): _label(overlay, subtitle, Rect2(104, 195, 1280, 85), 23)
	return heading

func _main_menu() -> void:
	running = false
	replaying = false
	audio.stop()
	audio_group = ""
	if is_instance_valid(page_scene): page_scene.free()
	var heading := _show_overlay("Пока идёт запись")
	heading.position.y = 190
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var saved := SaveStore.read(SaveStore.AUTO_PATH, catalog)
	var resume := _button(overlay, "Продолжить", Rect2(570, 340, 460, 64), _resume_save)
	resume.disabled = not saved.ok
	_button(overlay, "Новая игра", Rect2(570, 425, 460, 64), _start_game.bind(1))
	_button(overlay, "Настройки", Rect2(570, 510, 460, 64), _settings.bind(true))
	if OS.is_debug_build():
		_button(overlay, "Загрузка", Rect2(570, 595, 460, 64), _day_menu)
	if not menu_message.is_empty():
		_label(overlay, menu_message, Rect2(300, 710, 1000, 90), 22).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _day_menu() -> void:
	if not OS.is_debug_build(): return
	_show_overlay("Загрузка", "Выберите день для переигрывания. Основное сохранение останется на месте.")
	var row := 0
	for day in range(1, 11):
		if catalog.has("day%d" % day):
			_button(overlay, "День %d" % day, Rect2(104 + 650 * (row / 5), 290 + 74 * (row % 5), 460, 54), _start_game.bind(day, true))
			row += 1
	_button(overlay, "Назад", Rect2(104, 715, 260, 60), _main_menu)

func _start_game(day: int, as_replay: bool = false) -> void:
	replaying = as_replay
	menu_message = ""
	# Keep the previous run separately when explicitly beginning a new one.
	if autosave_enabled and not replaying and FileAccess.file_exists(SaveStore.AUTO_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SaveStore.AUTO_PATH), ProjectSettings.globalize_path("user://previous-run.json"))
	flow.new_game(day)
	running = true
	_save()
	_render_page()

func _save(path: String = SaveStore.AUTO_PATH) -> bool:
	if not autosave_enabled or replaying: return true
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
	audio.stream_paused = false
	overlay.visible = false
	overlay_open = false
	interaction.visible = true
	if flow.state.finished:
		_show_end()
		return
	var page: Dictionary = flow.current()
	if playback_page != page.id:
		playback_page = page.id
		playback_elapsed = 0.0
	playback_duration = float(page.get("playback_duration",0))
	if is_instance_valid(evidence) and is_instance_valid(page_scene) and page_scene.get_meta("page_id","") == page.id:
		evidence.set_process(not evidence.is_complete())
		return
	if page.get("entry_movie",false) and is_instance_valid(page_scene) and page_scene.get_meta("page_id","")==page.id and page_scene.has_node("BookFilm") and page_scene.get_node("BookFilm").paused:
		page_scene.get_node("BookFilm").paused = false
		return
	var bird_time := -1.0
	var video_time := -1.0
	var book_time := -1.0
	if is_instance_valid(page_scene) and str(page_scene.get_meta("page_id","")) == page.id and page_scene.has_node("Art") and page_scene.get_node("Art").has_method("pose_at"):
		book_time = page_scene.get_node("Art").elapsed
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
	evidence = page_scene.find_child("Evidence", true, false) if page.has("evidence") else null
	audio_cursor = page_scene.get_node_or_null("InterfaceShapes/AudioCursor")
	if book_time >= 0:
		page_scene.get_node("Art").pose_at(book_time)
	if video_time >= 0 and page_scene.has_node("VideoPlayback"):
		page_scene.get_node("VideoPlayback").flight.seek(video_time)
	# This branch has already packed the test pouches during the camera cross-cuts.
	if flow.state.results == "promise" and page.has("packing_state") and page_scene.has_node("Art/PackingStage/Equipment"):
		page_scene.get_node("Art/PackingStage/Equipment").visible = false
	if bird_time >= 0.0 and page_scene.has_node("Art/BirdFlight"):
		var flight := page_scene.get_node("Art/BirdFlight")
		flight.seek(maxf(bird_time, [0.0, 6.0, 8.0][flight.phase]))
	_clear(interaction)
	if page.get("entry_movie",false):
		var film: VideoStreamPlayer = page_scene.get_node("BookFilm")
		film.volume_db = -80.0 if muted else 0.0
		film.finished.connect(_film_finished.bind(film), CONNECT_DEFERRED | CONNECT_ONE_SHOT)
		film.play()
		_button(interaction, "Пропустить  ›", Rect2(1330,826,222,51), _next)
	elif page.choices.is_empty() and not page.has("auto_seconds"):
		var area: Array = page.get("next_rect",[1394,826,158,51])
		_button(interaction, "", Rect2(area[0],area[1],area[2],area[3]), _next, true).tooltip_text = str(strings[page.id].get("next","Далее"))
	elif not page.choices.is_empty():
		for choice in page.choices:
			var caption := str(strings[page.id][choice.text_field])
			var drawn := bool(choice.get("native_label",false))
			_button(interaction, caption if drawn else "", Rect2(choice.x, choice.y, choice.width, choice.height), _choose.bind(str(choice.value)), not drawn).tooltip_text = caption
		if page.choices[0].get("native_label",false):
			for child in page_scene.get_node("Art").get_children():
				if "navigation" in str(child.name): child.hide()
			for child in page_scene.get_node("Text").get_children():
				if child.name == &"next" or str(child.name).begins_with("item_"): child.hide()
	if page.get("archive_reports",false):
		_button(interaction, "", Rect2(48,538,410,51), _archive_reports, true).tooltip_text = "Читать отправленные отчёты"
	if page.has("replay_rect"):
		var box: Array = page.replay_rect
		_button(interaction, "", Rect2(box[0], box[1], box[2], box[3]), _replay_audio, true).tooltip_text = str(strings[page.id].get("replay","Прослушать сигналы"))
	if is_instance_valid(evidence) and evidence.start_seconds < evidence.end_seconds:
		var next_button: Button = interaction.get_child(0)
		var navigation: Node = page_scene.get_node("InterfaceShapes").get_children()[-1]
		var next_label: Node = page_scene.get_node("Text/next")
		var replay := _button(interaction, strings[page.id].replay, Rect2(48,538,345,51), func(): evidence.restart(); _set_audio(page,true))
		var set_ready := func(ready: bool):
			next_button.visible = ready
			navigation.visible = ready
			next_label.visible = ready
			replay.visible = ready
		replay.pressed.connect(set_ready.bind(false))
		evidence.completed.connect(set_ready.bind(true))
		set_ready.call(false)
	_set_audio(page)
	_playback_controls()

func _playback_controls() -> void:
	if playback_duration <= 0 or not is_instance_valid(page_scene): return
	var ready := playback_elapsed >= playback_duration
	if interaction.get_child_count() > 0: interaction.get_child(0).disabled = not ready
	if page_scene.has_node("Text/next"): page_scene.get_node("Text/next").modulate.a = 1.0 if ready else 0.35
	if is_instance_valid(audio_cursor): audio_cursor.position.x = 1025 + 422 * clampf(playback_elapsed/playback_duration,0,1)

func _next(automatic: bool = false) -> void:
	if overlay_open: return
	if not automatic and flow.current().has("auto_seconds"): return
	if playback_duration > playback_elapsed: return
	if is_instance_valid(evidence) and not evidence.is_complete(): return
	if not automatic and is_instance_valid(page_scene) and page_scene.has_node("Art/BirdFlight"):
		var flight := page_scene.get_node("Art/BirdFlight")
		if flight.elapsed < flight.VANISH_TIME and flow.skip_bird_flight():
			_save()
			_render_page()
			return
	if flow.advance():
		_save()
		_render_page()

func _film_finished(film: VideoStreamPlayer) -> void:
	if running and not overlay_open and is_instance_valid(film) and film.get_parent() == page_scene:
		_next(true)

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
	audio_start_seconds = float(spec.get("start_seconds",0))
	audio.play(audio_start_seconds)

func _process(_delta: float) -> void:
	if running and not overlay_open and not flow.state.finished and playback_duration > 0:
		playback_elapsed = minf(playback_duration,playback_elapsed+_delta)
		_playback_controls()
		if is_instance_valid(page_scene) and page_scene.has_node("FinalFade"):
			page_scene.get_node("FinalFade").color.a = clampf(playback_elapsed/playback_duration,0,1)
		if flow.current().has("auto_seconds") and playback_elapsed >= playback_duration:
			_next(true)
	if is_instance_valid(audio_cursor) and audio.playing and not overlay_open:
		var progress := inverse_lerp(audio_start_seconds, max_audio_seconds, audio.get_playback_position())
		audio_cursor.position.x = 1025 + 422 * clampf(progress,0,1)
	if audio.playing and max_audio_seconds > 0 and audio.get_playback_position() >= max_audio_seconds:
		audio.stop()
	if running and not overlay_open and is_instance_valid(page_scene) and page_scene.has_node("Art/BirdFlight"):
		if page_scene.get_node("Art/BirdFlight").phase_finished():
			_next(true)

func _replay_audio() -> void:
	if playback_duration > 0:
		playback_elapsed = 0.0
		_playback_controls()
	_set_audio(flow.current(), true)

func _mute() -> void:
	muted = not muted
	if muted: audio.stop()
	elif running and not overlay_open: _set_audio(flow.current(), true)
	if is_instance_valid(page_scene) and page_scene.has_node("BookFilm"):
		page_scene.get_node("BookFilm").volume_db = -80.0 if muted else 0.0
	_save_settings()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("audio", "muted", muted)
	config.set_value("display", "show_trust", show_trust)
	config.save("user://settings.cfg")

func _settings(from_menu: bool) -> void:
	_show_overlay("Настройки")
	var values: Dictionary = flow.state
	var source := "Текущее прохождение"
	if from_menu:
		var saved := SaveStore.read(SaveStore.AUTO_PATH,catalog)
		values = saved.state if saved.ok else Flow.new(catalog).state
		source = "Последнее сохранение" if saved.ok else "Начало новой игры"
	_button(overlay, "Звук " + ("выключен" if muted else "включён"), Rect2(104,230,590,60), func(): _mute(); _settings(from_menu))
	_button(overlay, "Шкалы доверия " + ("видны" if show_trust else "скрыты"), Rect2(104,310,590,60), func(): show_trust = not show_trust; _save_settings(); _settings(from_menu))
	_label(overlay, "Управление", Rect2(970,230,550,55), 30, true)
	_label(overlay, "Пробел / Enter / → — далее\nEsc — пауза\nH — прочитанное · J — отчёты\nM — звук · F11 — полный экран", Rect2(970,305,565,220), 23)
	if show_trust:
		_label(overlay,source,Rect2(104,403,840,46),22)
		_trust_bar("Доверие Ники",values.nika_trust,Flow.Trust.config.nika_max,475)
		_trust_bar("Доверие работодателя",values.employer_trust,Flow.Trust.config.employer_start,595)
	_button(overlay, "Вернуться", Rect2(104,785,270,60), _main_menu if from_menu else _pause)

func _trust_bar(title: String, amount: int, maximum: int, y: int) -> void:
	_label(overlay,"%s   %d / %d" % [title,amount,maximum],Rect2(104,y,950,52),28)
	var bar := ProgressBar.new()
	bar.position = Vector2(104,y+58)
	bar.size = Vector2(790,20)
	bar.show_percentage = false
	bar.max_value = maximum
	bar.value = amount
	overlay.add_child(bar)

func _pause() -> void:
	if not running:
		_main_menu()
		return
	_show_overlay("Пауза", "Переигрывание. Прогресс сохраняется до выхода в главное меню." if replaying else "Прогресс и решения сохраняются после каждого шага.")
	_button(overlay, "Вернуться", Rect2(104, 310, 460, 62), _render_page)
	if not replaying:
		_button(overlay, "Сохранить вручную", Rect2(104, 390, 460, 62), _manual_save)
		_button(overlay, "Загрузить вручную", Rect2(104, 470, 460, 62), _resume_save.bind(SaveStore.MANUAL_PATH)).disabled = not SaveStore.read(SaveStore.MANUAL_PATH, catalog).ok
	_button(overlay, "Прочитанное", Rect2(104, 550, 460, 62), _history)
	_button(overlay, "Отчёты", Rect2(104, 630, 460, 62), _journal)
	_button(overlay, "Главное меню", Rect2(104, 710, 460, 62), _main_menu)
	_button(overlay, "Настройки", Rect2(770, 310, 460, 62), _settings.bind(false))

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
		for field in ["description", "description_1", "description_2"]:
			if text.has(field): content += str(text[field]) + "\n"
		if text.has("dialogue"): content += str(text.get("speaker", "")) + ": " + str(text.dialogue) + "\n"
		content += "\n"
	_reading_panel("Прочитанное", content if not content.is_empty() else "Здесь появятся завершённые реплики.")

func _archive_reports() -> void:
	var content := ""
	var archive: Dictionary = flow.state.facts.get("day10_archive_reports",{})
	for day in range(1,10):
		if not archive.has(str(day)): continue
		content += "День %d\n" % day
		for field in archive[str(day)]:
			if str(field).begins_with("document_line_"): content += str(archive[str(day)][field]) + "\n"
		content += "\n"
	_reading_panel("Архив Ники · отправленные отчёты",content if not content.is_empty() else "В отдельном просмотре нет отчётов предыдущих визитов. Они доступны в полном прохождении.")

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
	var text := "Отчёты этого переигрывания доступны до выхода в главное меню." if replaying else "Ваши решения и отчёты сохранены."
	var dismissed: bool = flow.state.facts.get("employer_dismissed", false)
	if dismissed: text = "Работодатель уволил вас за систематическое нарушение правил работы. Допуск к дальнейшим визитам прекращён."
	var title: String = {2:"Второй визит завершён",3:"Третий визит завершён",4:"Четвёртый визит завершён",5:"Пятый визит завершён",6:"Шестой визит завершён",7:"Седьмой визит завершён",8:"Восьмой визит завершён",9:"Девятый визит завершён",10:"Свой следующий шаг"}.get(int(flow.state.day),"Визит завершён")
	if int(flow.state.day) == 10 and not dismissed: text = "Ника завершила участие. Материалы и управление остались у неё. Запись «Комната» сохранена."
	_show_overlay("Допуск отозван" if dismissed else title, text)
	if flow.can_continue_visit():
		_button(overlay, "Продолжить · день %d" % (int(flow.state.day)+1), Rect2(750,330,590,64), _continue_visit)
	_button(overlay, "Отчёты", Rect2(104, 330, 460, 64), _journal)
	_button(overlay, "Прочитанное", Rect2(104, 420, 460, 64), _history)
	_button(overlay, "Главное меню", Rect2(104, 510, 460, 64), _main_menu)

func _continue_visit() -> void:
	if flow.continue_visit():
		_save()
		_render_page()

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
