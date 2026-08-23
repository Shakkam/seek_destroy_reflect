class_name ProjectileFactory
extends RefCounted

## Extracted from MatchArenaNode._spawn_projectile()/_weapon_tint()
## (2026-08-18, Breakout mini-jeu) — Camil, after seeing the mini-jeu's
## first trimmed-visuals pass: "pas mal mais il faut que le joueur garde
## ses armes habituelles." A generic tinted-shape/straight-line fallback
## isn't good enough; the mini-jeu needs the EXACT same textures/
## trajectories (vortex sine, boomerang arc, real sprites) the real match
## already has. Rather than duplicate that per-weapon branching a second
## time (guaranteed to drift out of sync), it's pulled out into this pure
## factory that both MatchArenaNode and BreakoutNode call — single source
## of truth. MatchArenaNode's own _spawn_projectile() is now a thin
## wrapper wired to ship_1/ship_2 (unchanged external behavior/call
## sites); BreakoutNode calls this directly with its own shooter/target.

const MACHINE_GUN_TEX_P1 := preload("res://assets/art/vfx/mitraillette_shot_bleu.png")
const MACHINE_GUN_TEX_P2 := preload("res://assets/art/vfx/mitraillette_shot_rose.png")
const BAZOOKA_TEXTURES := [
	preload("res://assets/art/vfx/bazook.png"),
]
const VORTEX_TEXTURES := [
	preload("res://assets/art/vfx/wind1.png"),
]
const BONBON_TEXTURES := [
	preload("res://assets/art/vfx/bonbon.png"),
]
const BOOMERANG_TEXTURES := [
	preload("res://assets/art/vfx/boomerang.png"),
]

const LA_MEUTE_LIFETIME := 4.0
const LA_MEUTE_EXPLOSION_RADIUS := 60.0
const LA_MEUTE_EXPLOSION_DAMAGE := 3.0

## The exact same per-weapon color used for the HUD swatch AND every
## projectile of that weapon — see MatchArenaNode._weapon_tint()'s own
## doc comment for why stun_boomerang keeps its filename/id despite the
## stun->damage rework.
static func weapon_tint(weapon_id: String) -> Color:
	match weapon_id:
		"stun_boomerang":
			return Color(0.6, 0.8, 1.0)
		"homing_missile", "ultra_la_meute":
			return Color(1.0, 0.6, 0.2)
		"laser":
			return Color(0.4, 1.0, 0.5)
		"mini_shot", "ultra_pluie_de_bonbons":
			return Color(1.0, 1.0, 0.4)
		_:
			return Color.WHITE

## Builds a fully-configured ProjectileNode — NOT yet added to any parent
## (the caller does that, same as MatchArenaNode always has, since only
## the caller knows the right tree to add it to). `target` is now passed
## explicitly instead of assumed to be "the other of ship_1/ship_2" —
## the one thing that genuinely differs between a real match (target =
## the opponent ship) and BreakoutNode (target = a bare non-rendered
## ShipNode anchor, side 1, purely so the existing turret-hit-check's
## `target.side` filter resolves against bricks/enemies).
static func spawn(weapon: WeaponData, shooter: ShipNode, target: ShipNode, angle_offset_deg: float, speed_multiplier: float = 1.0, position_offset: Vector2 = Vector2.ZERO, boomerang_out_duration_override: float = 0.0, damage_multiplier: float = 1.0, size_multiplier: float = 1.0, force_no_burst_shrink: bool = false) -> ProjectileNode:
	var projectile := ProjectileNode.new()
	projectile.position = shooter.position + position_offset
	var shooter_side := shooter.side
	var direction := 1.0 if shooter_side == 0 else -1.0
	var spread_deg := angle_offset_deg
	if not weapon.is_heavy and weapon.projectile_count <= 1:
		spread_deg += randf_range(-weapon.spread_deg, weapon.spread_deg)
	var shot_velocity := Vector2(direction * weapon.projectile_speed * speed_multiplier, 0.0).rotated(deg_to_rad(spread_deg))
	projectile.velocity = shot_velocity
	projectile.spin_speed = weapon.projectile_spin_speed
	projectile.is_looping = weapon.is_looping
	projectile.loop_radius = weapon.loop_radius
	projectile.loop_angular_speed = weapon.loop_angular_speed
	projectile.is_sine = weapon.is_sine
	projectile.sine_amplitude = weapon.sine_amplitude
	projectile.sine_angular_speed = weapon.sine_angular_speed
	projectile.flip_h = direction < 0.0
	if weapon.id == "vortex":
		projectile.textures = VORTEX_TEXTURES
		projectile.visual_scale = 2.4
	elif weapon.id == "mini_shot" or weapon.id == "ultra_pluie_de_bonbons":
		projectile.textures = BONBON_TEXTURES
		projectile.visual_scale = 1.0
	elif weapon.id == "stun_boomerang":
		projectile.textures = BOOMERANG_TEXTURES
		projectile.visual_scale = 1.4
	elif weapon.is_heavy:
		projectile.textures = BAZOOKA_TEXTURES
		projectile.flip_h = direction > 0.0
		projectile.visual_scale = 1.4
	else:
		projectile.textures = [MACHINE_GUN_TEX_P1] if shooter_side == 0 else [MACHINE_GUN_TEX_P2]
		projectile.visual_scale = 1.4
	if weapon.projectile_count > 1 and not force_no_burst_shrink:
		projectile.visual_scale *= 0.7
	projectile.visual_scale *= weapon.visual_scale_multiplier * size_multiplier
	projectile.homing_strength = weapon.homing_strength
	projectile.homing_full_turn = weapon.id == "ultra_la_meute"
	if weapon.id == "ultra_la_meute":
		projectile.lifetime = LA_MEUTE_LIFETIME
		projectile.expiry_explosion_radius = LA_MEUTE_EXPLOSION_RADIUS
		projectile.expiry_explosion_damage = LA_MEUTE_EXPLOSION_DAMAGE
	projectile.damage = int(round(weapon.damage * damage_multiplier))
	projectile.effect_type = weapon.effect_type
	projectile.effect_duration = weapon.effect_duration
	projectile.tint = weapon_tint(weapon.id)
	if weapon.id == "stun_boomerang":
		projectile.tint = Color(0.27, 0.85, 1.0) if shooter_side == 0 else Color(1.0, 0.55, 0.7)
	projectile.target = target
	if weapon.is_boomerang:
		projectile.is_boomerang = true
		projectile.shooter = shooter
		projectile.boomerang_descending_throw = shooter.get_last_move_direction().y > 0.01
		var out_duration := boomerang_out_duration_override
		if out_duration <= 0.0:
			out_duration = weapon.boomerang_out_duration
		if out_duration > 0.0:
			projectile.boomerang_out_duration = out_duration
		var effective_out := projectile.boomerang_out_duration
		projectile.lifetime = maxf(3.0, effective_out * 4.0 + 1.0)
		if weapon.id == "stun_boomerang" and boomerang_out_duration_override > 0.0:
			projectile.leaves_fire_trail = true
	return projectile
