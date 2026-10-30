@tool
extends Node2D
@export var playback_mode: String = "before"
var flight: Node2D
func _ready() -> void:
	var screen := SubViewportContainer.new()
	screen.position = Vector2(1132, 200)
	screen.size = Vector2(500, 282)
	screen.scale = Vector2(346.0/500.0, 195.0/282.0)
	screen.stretch = false
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(500,282)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	screen.add_child(viewport)
	var world := Node2D.new()
	world.position = Vector2(-500,-30)
	viewport.add_child(world)
	var background := Sprite2D.new()
	background.centered = false
	background.texture = preload("res://assets/shared/evidence-three-a584983c9bf8.png")
	background.scale = Vector2(0.956938,0.956429)
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/evidence_sky.gdshader")
	background.material = material
	world.add_child(background)
	flight = preload("res://scenes/BirdFlight.tscn").instantiate()
	world.add_child(flight)
	flight.set_process(false)
	flight.seek(7.2 if playback_mode == "after" else 6.3 if playback_mode == "before" else 0.0)
func _process(delta: float) -> void:
	if not is_instance_valid(flight) or Engine.is_editor_hint(): return
	if playback_mode == "play": flight.seek(minf(flight.elapsed+delta,8.0))
