class_name BeamNode
extends Node2D

## 2026-08-09 redesign (Zoneur: "le tir normal de zoneur n'est pas bien. je
## propose un laser qui traverse toute la map, mais qui ne dure que 0.5
## secondes (avec petit effet visuel fade in fade out tres rapide).
## cooldown : 0.8 seconde. Le tir charge en revanche lache le gros laser,
## qui dure 3 secondes, traverse toute la map, et est 2 fois plus epais.")
## A self-contained, timed damage ray: spawned once by
## MatchArenaNode._spawn_timed_beam() (through the normal fired()/charge
## dispatch, same as any other weapon), counts down its own `lifetime`,
## fades in/out quickly, and despawns itself — no external polling/
## lifecycle ownership needed anymore (replaces the old continuous
## hold-to-channel model driven by ShipNode.beam_active).

var shooter: ShipNode
var target: ShipNode
var weapon: WeaponData
var arena_bounds: Rect2
var color := Color(0.4, 1.0, 0.5, 0.7)
var lifetime := 0.5 # seconds this pulse persists — set by the spawner (WeaponData.beam_duration/charged_beam_duration)
var thickness_multiplier := 1.0

const BASE_THICKNESS := 6.0
const TICK_INTERVAL := 0.1 # apply damage in small ticks rather than every physics frame
const FADE_DURATION := 0.08 # quick fade in/out ("petit effet visuel fade in fade out tres rapide")

var _visual: ColorRect
var _hit_timer := 0.0
var _elapsed := 0.0

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
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	position = shooter.position
	_update_shape()
	_update_fade()

	if not is_instance_valid(target):
		return
	_hit_timer -= delta
	if _hit_timer > 0.0:
		return
	_hit_timer = TICK_INTERVAL
	var in_range := absf(target.position.x - shooter.position.x) <= weapon.beam_range
	var y_aligned := absf(target.position.y - shooter.position.y) < target.half_extents.y + BASE_THICKNESS * thickness_multiplier
	if in_range and y_aligned:
		target.apply_damage(weapon.damage * TICK_INTERVAL)

func _update_shape() -> void:
	if not _visual or not is_instance_valid(shooter):
		return
	var direction := 1.0 if shooter.side == 0 else -1.0
	var wall_x := arena_bounds.position.x + arena_bounds.size.x if direction > 0.0 else arena_bounds.position.x
	var max_reach_x := shooter.position.x + direction * weapon.beam_range
	# Whichever is closer: the arena wall or the weapon's own range limit —
	# with beam_range now set comfortably larger than the arena in data,
	# this always resolves to the wall ("traverse toute la map").
	var far_x := minf(wall_x, max_reach_x) if direction > 0.0 else maxf(wall_x, max_reach_x)
	var length := absf(far_x - shooter.position.x)
	var thickness := BASE_THICKNESS * thickness_multiplier
	_visual.size = Vector2(length, thickness)
	_visual.position = Vector2(0.0 if direction > 0.0 else -length, -thickness / 2.0)

func _update_fade() -> void:
	var alpha := 1.0
	if _elapsed < FADE_DURATION:
		alpha = _elapsed / FADE_DURATION
	elif _elapsed > lifetime - FADE_DURATION:
		alpha = clampf((lifetime - _elapsed) / FADE_DURATION, 0.0, 1.0)
	_visual.color = Color(color.r, color.g, color.b, color.a * alpha)
