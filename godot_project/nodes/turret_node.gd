class_name TurretNode
extends Node2D

## Story 2.4 — a turret weapon places this instead of firing a traveling
## projectile. Once placed it fires autonomously at `target` using its own
## weapon's damage/fire_rate, with no further player input. No dedicated art
## exists yet (2026-08-02) — rendered as a simple colored placeholder shape,
## same "engine-side, no art needed yet" approach used elsewhere in Epic 2.

const LIFETIME := 6.0 # placeholder duration — not specified by the AC, tuned later
const SHOT_SPEED := 480.0

var weapon: WeaponData
var target: ShipNode
var owner_side: int = 0

var _lifetime_left := LIFETIME
var _fire_cooldown := 0.0

func _ready() -> void:
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
	])
	visual.color = Color(0.4, 0.9, 0.4) if owner_side == 0 else Color(0.9, 0.4, 0.9)
	add_child(visual)
	_fire_cooldown = 1.0 / weapon.fire_rate

func _physics_process(delta: float) -> void:
	_lifetime_left -= delta
	if _lifetime_left <= 0.0 or not is_instance_valid(target):
		queue_free()
		return

	_fire_cooldown -= delta
	if _fire_cooldown <= 0.0:
		_fire_cooldown = 1.0 / weapon.fire_rate
		_fire_at_target()

func _fire_at_target() -> void:
	var projectile := ProjectileNode.new()
	projectile.position = position
	projectile.velocity = (target.position - position).normalized() * SHOT_SPEED
	projectile.damage = weapon.damage
	projectile.effect_type = weapon.effect_type if weapon.effect_type == "stun" else "damage"
	projectile.effect_duration = weapon.effect_duration
	projectile.fallback_color = Color(0.4, 0.9, 0.4) if owner_side == 0 else Color(0.9, 0.4, 0.9)
	projectile.target = target
	get_parent().add_child(projectile)
