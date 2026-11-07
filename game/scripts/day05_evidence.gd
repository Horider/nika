extends Node2D
## The view through the window and both camera recordings sample the day-two flight.
signal completed
@export var layout := "single"
@export var start_seconds := 0.0
@export var end_seconds := 8.0
var elapsed := 0.0
var tracks: Array[Node] = []
var street: Node2D

func _ready() -> void:
	if layout == "wide":
		var flight := preload("res://scenes/BirdFlight.tscn").instantiate()
		add_child(flight)
		flight.set_process(false)
		tracks.append(flight)
		street = preload("res://scripts/day05_street.gd").new()
		add_child(street)
	else:
		for i in (2 if layout == "double" else 1):
			var screen := preload("res://scripts/day03_video.gd").new()
			screen.screen_position = Vector2(1024, 207 + i * 278)
			screen.screen_size = Vector2(434, 237)
			# Slight change of camera framing across visits; both clips keep the antenna in view.
			screen.picture_offset += Vector2(13 * i, -5 * i)
			add_child(screen)
			screen.set_process(false)
			tracks.append(screen.flight)
	restart()

func restart() -> void:
	seek(start_seconds)
	set_process(not is_complete())

func seek(seconds: float) -> void:
	elapsed = clampf(seconds, start_seconds, end_seconds)
	for flight in tracks: flight.seek(elapsed)
	if is_instance_valid(street): street.seek(elapsed)

func is_complete() -> bool:
	return elapsed >= end_seconds

func _process(delta: float) -> void:
	seek(elapsed + delta)
	if is_complete():
		set_process(false)
		completed.emit()
