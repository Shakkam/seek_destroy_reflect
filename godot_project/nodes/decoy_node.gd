class_name DecoyNode
extends Node2D

## Epic 4, Story 4.5 — "visual_decoy" twist ("Double moi"): a copy of the
## opponent's appearance that wanders erratically. Zero damage, zero HP,
## no collision with anything — pure confusion about which ship is the real
## target, per the brainstorm's decision to start with the leurre-only
## version rather than a real threat (Indie: "quasi gratuit").

var wander_speed := 180.0
var half_extents := Vector2(14, 28)
var arena_bounds: Rect2
var color := Color(1, 1, 1)

var _wander_target: Vector2
var _wander_timer := 0.0
const WANDER_INTERVAL_MIN := 0.6
const WANDER_INTERVAL_MAX := 1.6

func _ready() -> void:
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		Vector2(-half_extents.x, -half_extents.y), Vector2(half_extents.x, -half_extents.y),
		Vector2(half_extents.x, half_extents.y), Vector2(-half_extents.x, half_extents.y),
	])
	visual.color = color
	visual.modulate.a = 0.85 # very slightly translucent — a subtle tell that rewards close attention, without giving it away outright
	add_child(visual)
	_pick_new_wander_target()

func _physics_process(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_new_wander_target()
	var to_target := _wander_target - position
	if to_target.length() > 4.0:
		position += to_target.normalized() * wander_speed * delta

func _pick_new_wander_target() -> void:
	_wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)
	if arena_bounds.size == Vector2.ZERO:
		return
	var min_x := arena_bounds.position.x + half_extents.x
	var max_x := arena_bounds.position.x + arena_bounds.size.x - half_extents.x
	var min_y := arena_bounds.position.y + half_extents.y
	var max_y := arena_bounds.position.y + arena_bounds.size.y - half_extents.y
	_wander_target = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
