class_name BeamNode
extends Node2D

## "Shmup juice pass" (2026-08-05) — a continuous damage-over-time ray,
## replacing the laser's old single-shot behavior. Spawned/freed by
## MatchArenaNode._sync_beam() while ShipNode.beam_active is true (see
## WeaponSystemState.beam_tick()); follows the shooter's Y every frame and
## deals weapon.damage PER SECOND (not per hit, see weapon_data.gd) to
## whatever ship stands in its path on the opponent's side.

var shooter: ShipNode
var target: ShipNode
var weapon: WeaponData
var arena_bounds: Rect2
var color := Color(0.4, 1.0, 0.5, 0.7)

const THICKNESS := 6.0
const TICK_INTERVAL := 0.1 # apply damage in small ticks rather than every physics frame

var _visual: ColorRect
var _hit_timer := 0.0

func _ready() -> void:
	_visual = ColorRect.new()
	_visual.color = color
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visual)
	_update_shape()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(shooter):
		queue_free()
		return
	position = shooter.position
	_update_shape()

	if not is_instance_valid(target):
		return
	_hit_timer -= delta
	if _hit_timer > 0.0:
		return
	_hit_timer = TICK_INTERVAL
	var in_range := absf(target.position.x - shooter.position.x) <= weapon.beam_range
	var y_aligned := absf(target.position.y - shooter.position.y) < target.half_extents.y + THICKNESS
	if in_range and y_aligned:
		target.apply_damage(weapon.damage * TICK_INTERVAL)

func _update_shape() -> void:
	if not _visual or not is_instance_valid(shooter):
		return
	var direction := 1.0 if shooter.side == 0 else -1.0
	var wall_x := arena_bounds.position.x + arena_bounds.size.x if direction > 0.0 else arena_bounds.position.x
	var max_reach_x := shooter.position.x + direction * weapon.beam_range
	# Whichever is closer: the arena wall or the weapon's own range limit.
	var far_x := minf(wall_x, max_reach_x) if direction > 0.0 else maxf(wall_x, max_reach_x)
	var length := absf(far_x - shooter.position.x)
	_visual.size = Vector2(length, THICKNESS)
	_visual.position = Vector2(0.0 if direction > 0.0 else -length, -THICKNESS / 2.0)
