extends Node2D
## Registration against the unscaled city plate. The van reaches the pole before the pedestrian.
var van: Sprite2D
var walker: Sprite2D

func _ready() -> void:
	position = Vector2(882,750) * Vector2(0.956938,0.956429)
	scale = Vector2(0.956938,0.956429)
	add_part(preload("res://assets/day05/street-patch.png"))
	walker = add_part(preload("res://assets/day05/walker.png"))
	van = add_part(preload("res://assets/day05/van.png"))

func add_part(texture: Texture2D) -> Sprite2D:
	var part := Sprite2D.new()
	part.centered = false
	part.texture = texture
	add_child(part)
	return part

func seek(seconds: float) -> void:
	var drive := smoothstep(5.7,10.7,seconds)
	var step := clampf((seconds-6.8)/4.2,0.0,1.0)
	van.position = Vector2(-116,-15) * drive
	walker.position = Vector2(30*step,3*step-absf(sin(step*TAU*4))*0.8)
