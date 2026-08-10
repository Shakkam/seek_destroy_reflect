class_name TurretNode
extends Node2D

## Story 2.4 — a turret weapon places this instead of firing a traveling
## projectile. Once placed it fires autonomously at `target` using its own
## weapon's damage/fire_rate, with no further player input. No dedicated art
## exists yet (2026-08-02) — rendered as a simple colored placeholder shape,
## same "engine-side, no art needed yet" approach used elsewhere in Epic 2.
##
## Destructible (2026-08-05 playtest: "faudrait qu'elle soit destructible") —
## any enemy projectile passing through its hitbox chips its HP (weapon.turret_hp)
## and is consumed. A turret sits on its owner's side, roughly in the path of
## incoming enemy fire toward the owner's ship, so this reads as "shoot the
## turret down" without needing dedicated turret-targeting AI/aim.
##
## Deflects the ball too (2026-08-09 playtest, Contrôleur: "vu qu'on parle
## d'un contrôleur, les tourelles pourraient renvoyer la balle aussi !") —
## see BallNode._resolve_turrets(), a stationary mirror-bounce off
## HALF_EXTENTS just like a ship's paddle, but with no aim/lift.

const SHOT_SPEED := 480.0
const HALF_EXTENTS := Vector2(15, 15) # 1.5x (2026-08-09 playtest: "les tourelles soient un peu plus grosses (1.5) histoire de pouvoir les viser")

var weapon: WeaponData
var target: ShipNode
var owner_side: int = 0
var hp: float = 0.0

# Controleur's charged turret (2026-08-10): "pose une tourelle ephemere, qui
# tire 4x plus vite, mais ne dure que 5 secondes" — set by MatchArenaNode._
# spawn_turret() before add_child() when this is the CHARGED release; a
# normal turret leaves both at their defaults (1.0 / 0.0, i.e. no override).
var fire_rate_multiplier: float = 1.0
var lifetime_override: float = 0.0 # 0 = use weapon.turret_lifetime unmodified

var _visual: Polygon2D
var _lifetime_left := 0.0 # set from weapon.turret_lifetime in _ready() — weapon isn't assigned yet at field-init time
var _fire_cooldown := 0.0
var _flash_timer := 0.0
const FLASH_DURATION := 0.08

func _ready() -> void:
	hp = weapon.turret_hp
	_lifetime_left = lifetime_override if lifetime_override > 0.0 else weapon.turret_lifetime
	_visual = Polygon2D.new()
	_visual.polygon = PackedVector2Array([
		Vector2(-12, -12), Vector2(12, -12), Vector2(12, 12), Vector2(-12, 12),
	]) # 1.5x the old 8x8 (2026-08-09 playtest, matches HALF_EXTENTS)
	_visual.color = Color(0.4, 0.9, 0.4) if owner_side == 0 else Color(0.9, 0.4, 0.9)
	if fire_rate_multiplier > 1.0:
		_visual.color = _visual.color.lightened(0.4) # visibly distinct from a normal turret — "tire 4x plus vite" should read as different at a glance
	add_child(_visual)
	_fire_cooldown = 1.0 / (weapon.fire_rate * fire_rate_multiplier)

func _physics_process(delta: float) -> void:
	_lifetime_left -= delta
	if _lifetime_left <= 0.0 or not is_instance_valid(target):
		queue_free()
		return

	_fire_cooldown -= delta
	if _fire_cooldown <= 0.0:
		_fire_cooldown = 1.0 / (weapon.fire_rate * fire_rate_multiplier)
		_fire_at_target()

	_flash_timer = maxf(_flash_timer - delta, 0.0)
	if _visual:
		_visual.modulate = Color(1.7, 1.7, 1.7) if _flash_timer > 0.0 else Color(1.0, 1.0, 1.0)

## 2026-08-10: hit detection moved to ProjectileNode's own physics step (see
## its swept _segment_crosses_rect() check) so it can never race this node's
## _physics_process order — a turret polling with a point-only check here
## used to silently swallow most incoming shots ("j'ai l'impression que tous
## les tirs ne touchent pas les tourelles de controleur"). This is now just
## the damage application the projectile calls into once it confirms a hit.
func take_damage(amount: float) -> void:
	hp -= amount
	_flash_timer = FLASH_DURATION
	if hp <= 0.0:
		queue_free()

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
