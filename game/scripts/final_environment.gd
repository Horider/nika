extends Node2D
## The same street actors as day 5, sampled at one shared timestamp.
signal completed
@export var layout := "double"
@export var start_seconds := 6.8
@export var end_seconds := 11.0
var elapsed := 0.0
var tracks: Array[Node2D] = []
var flights: Array[Node2D] = []

func _ready() -> void:
	for i in (2 if layout=="double" else 1):
		var world := Node2D.new()
		if layout=="wide":
			add_child(world)
		else:
			var panel := SubViewportContainer.new()
			panel.position=Vector2(1024,207+i*278)
			panel.size=Vector2(500,282)
			panel.scale=Vector2(434.0/500,237.0/282)
			panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
			add_child(panel)
			var viewport := SubViewport.new()
			viewport.size=Vector2i(500,282)
			viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			panel.add_child(viewport)
			viewport.add_child(world)
			world.position=Vector2(-698,-562)
		var picture := Sprite2D.new()
		picture.centered=false
		picture.texture=preload("res://assets/shared/evidence-three-a584983c9bf8.png")
		picture.scale=Vector2(.956938,.956429)
		var shader := ShaderMaterial.new()
		shader.shader=preload("res://scripts/evidence_sky.gdshader")
		picture.material=shader
		world.add_child(picture)
		var street := preload("res://scripts/day05_street.gd").new()
		world.add_child(street);tracks.append(street)
		var flight := preload("res://scenes/BirdFlight.tscn").instantiate()
		world.add_child(flight);flight.set_process(false);flights.append(flight)
	restart()

func restart() -> void:
	seek(start_seconds)
	set_process(not is_complete())

func seek(seconds: float) -> void:
	elapsed=clampf(seconds,start_seconds,end_seconds)
	for street in tracks: street.seek(elapsed)
	for flight in flights: flight.seek(elapsed)

func is_complete() -> bool:
	return elapsed>=end_seconds

func _process(delta: float) -> void:
	seek(elapsed+delta)
	if is_complete():
		set_process(false)
		completed.emit()
