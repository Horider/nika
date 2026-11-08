extends Node2D
## All transparent tracks share one frame clock. The background and UI stay editable.

@export var reading := false
var elapsed := 0.0
var frame_count := 0
var fps := 18
var current_frame := -1
var tracks: Array = []
var sprites: Array[Sprite2D] = []
var textures: Array = []

func _ready() -> void:
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/book_motion.json"))
	var clip: Dictionary = library["reading" if reading else "shelving"]
	fps = int(clip.fps)
	frame_count = int(clip.frames)
	tracks = clip.tracks
	for track in tracks:
		var key := ("book_reading_" if reading else "book_shelving_") + str(track.name)
		var sprite: Sprite2D = find_child("*_" + key, false, false)
		assert(sprite != null, "Missing book-scene track " + key)
		var pages: Array[Texture2D] = []
		for file in track.atlases:
			pages.append(load("res://assets/book-motion/" + str(file)))
		textures.append(pages)
		sprite.region_enabled = true
		sprite.region_filter_clip_enabled = true
		sprites.append(sprite)
	pose_at(0.0)

func _process(delta: float) -> void:
	pose_at(elapsed + delta)

func is_complete() -> bool:
	return current_frame >= frame_count - 1

func pose_at(seconds: float) -> void:
	elapsed = clampf(seconds, 0.0, float(frame_count - 1) / fps)
	var frame := mini(frame_count - 1, floori(elapsed * fps + 0.0001))
	set_process(frame < frame_count - 1)
	if frame == current_frame:
		return
	current_frame = frame
	for i in range(tracks.size()):
		var track: Dictionary = tracks[i]
		var cell := frame % int(track.per_atlas)
		var column := cell % int(track.columns)
		@warning_ignore("integer_division")
		var row := cell / int(track.columns)
		var size_px := Vector2(float(track.frame_size[0]),float(track.frame_size[1]))
		var origin := Vector2.ONE + Vector2(column,row) * (size_px + Vector2(2,2))
		@warning_ignore("integer_division")
		var page := frame / int(track.per_atlas)
		sprites[i].texture = textures[i][page]
		sprites[i].region_rect = Rect2(origin,size_px)
