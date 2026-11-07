extends Node2D

const DURATION := 1.65
var elapsed := 0.0

func _ready() -> void: pose_at(0)

func _process(delta: float) -> void: pose_at(elapsed + delta)

func pose_at(seconds: float) -> void:
	elapsed = clampf(seconds,0,DURATION)
	var t := smoothstep(0.0, DURATION, elapsed)
	var step := sin(t * TAU * 2)
	$Carrier.position = Vector2(807,42).lerp(Vector2(550,38),t) + Vector2(0,-absf(step)*4)
	$Carrier.scale = Vector2.ONE * lerpf(1.00,.883,t)
	$Carrier.rotation = .008*step
	set_process(elapsed < DURATION)
