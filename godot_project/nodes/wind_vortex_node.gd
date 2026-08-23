class_name WindVortexNode
extends Node2D

## Vif's Ultra — "Bourrasque" (2026-08-13 Epic 4 party-mode memlog: "vortex
## de vent facon Air Man/Mega Man 2 qui repousse en continu"). Same
## self-contained continuous-effect pattern as BlackHoleNode/
## HazardZoneNode, just pushing instead of pulling (no slow debuff — kept
## deliberately different in flavor from Controleur's Trou noir, pure
## continuous knockback): while the target is inside `radius`, shoves it
## AWAY from this node's position every tick via the same
## ShipNode.apply_knockback() every other push/pull effect already uses.

var radius := 90.0
var push_speed := 160.0 # px/s of push while inside the radius
var duration := 3.0
var target: ShipNode

var _visual: Polygon2D
var _pulse_time := 0.0

func _ready() -> void:
	_visual = Polygon2D.new()
	var points := PackedVector2Array()
	for i in 24:
		var angle := TAU * i / 24.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	_visual.polygon = points
	_visual.color = Color(0.55, 0.85, 1.0, 0.4) # pale cyan-white — reads as wind/air, distinct from the black hole's dark purple
	add_child(_visual)

func _physics_process(delta: float) -> void:
	duration -= delta
	if duration <= 0.0:
		queue_free()
		return
	_pulse_time += delta
	if _visual:
		_visual.scale = Vector2.ONE * (1.0 + sin(_pulse_time * 5.0) * 0.08) # a faster, airier pulse than the black hole's slow "breathing"

	if not is_instance_valid(target):
		return
	if target.position.distance_to(position) >= radius:
		return
	var direction := (target.position - position)
	if direction.length() < 1.0:
		direction = Vector2(1.0 if target.side == 0 else -1.0, 0.0) # degenerate case: target exactly on the vortex's center — push it back toward its own side rather than doing nothing
	target.apply_knockback(direction.normalized() * push_speed * delta)
