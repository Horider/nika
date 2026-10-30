@tool
extends Node2D
## One timeline shared by the three consecutive evidence pages.
## Art is sampled from the original painting; no replacement city or bird design.
const SOURCE = preload("res://assets/shared/evidence-three-a584983c9bf8.png")
const BIRD_SHADER = preload("res://scripts/bird_cutout.gdshader")
const STARTS := [Vector2(610, 153), Vector2(686, 137), Vector2(724, 134)]
const REGIONS := [Rect2(818, 139, 26, 26), Rect2(897, 125, 26, 26), Rect2(934, 122, 26, 26)]
const VANISH_TIME := 6.8
@export_range(0, 2) var phase: int = 0
var elapsed: float = 0.0
var birds: Array[Sprite2D] = []

func _ready() -> void:
	for i in range(3):
		var bird := Sprite2D.new()
		bird.name = "TrailingBird" if i == 0 else "LeadingBird%d" % i
		var atlas := AtlasTexture.new()
		atlas.atlas = SOURCE
		atlas.region = REGIONS[i]
		bird.texture = atlas
		var cutout := ShaderMaterial.new()
		cutout.shader = BIRD_SHADER
		cutout.set_shader_parameter("bird_center", REGIONS[i].get_center())
		bird.material = cutout
		add_child(bird)
		birds.append(bird)
	seek([0.0, 6.0, 8.0][phase])

func seek(seconds: float) -> void:
	elapsed = seconds
	for i in range(birds.size()):
		var bird := birds[i]
		bird.visible = i != 0 or elapsed < VANISH_TIME
		bird.position = STARTS[i] + Vector2(elapsed * 31.0, -elapsed * 0.7 + sin(elapsed * 2.4 + i) * 2.0)
		# Small out-of-phase wing beats; the body remains at its flight anchor.
		bird.material.set_shader_parameter("wing_phase", elapsed * 15.0 + i * 2.1)
		bird.rotation = sin(elapsed * 2.0 + i) * 0.055

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	seek(elapsed + delta)

func phase_finished() -> bool:
	return elapsed >= (6.0 if phase == 0 else 8.0) and phase < 2
