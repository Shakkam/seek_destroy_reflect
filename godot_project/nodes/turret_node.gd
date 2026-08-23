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

# 2026-08-18 (Breakout mini-jeu — Camil, looking at a reference screenshot:
# "briques plus longues, serrees") — every real Controleur turret still
# gets exactly HALF_EXTENTS (unchanged behavior/hitbox), but a brick needs
# a bigger, custom footprint. Instance field so BallNode/ProjectileNode's
# hit-detection and this node's own visual/hitbox-overlay all agree on
# the SAME size per-instance, rather than a class-wide constant lying
# about a resized brick's real collision rect.
var half_extents := HALF_EXTENTS

# 2026-08-18 (Breakout mini-jeu) — see _ready()'s comment on visual_half.
# 0.8 (default) matches every real turret's current look exactly.
var visual_fill_ratio := 0.8

var weapon: WeaponData
var target: ShipNode
var owner_side: int = 0
var hp: float = 0.0

# Mitrailleur's Ultra "Mitrailleuses Satellites" (2026-08-15 rework, Camil:
# "les petites tourelles se mettent au bon endroit mais doivent suivre le
# vaisseau. Ensuite elles ne doivent pas tirer toutes seules : elles
# envoient des tirs de mitraillette quand on tire normalement"). A normal
# placed turret (Controleur) leaves both at their defaults — static
# position, autonomous cooldown-driven fire, unchanged. When follow_ship
# is set, position tracks it every tick instead of staying where it was
# placed; when autofire is false, _physics_process skips its own cooldown
# entirely and firing must be triggered externally via fire_now() (see
# MatchArenaNode._ultra_mitrailleuses_satellites(), which connects this
# straight to the owner's ShipNode.weapon_fired signal).
var follow_ship: ShipNode
var follow_offset := Vector2.ZERO
var autofire := true

# Controleur's charged turret (2026-08-10): "pose une tourelle ephemere, qui
# tire 4x plus vite, mais ne dure que 5 secondes" — set by MatchArenaNode._
# spawn_turret() before add_child() when this is the CHARGED release; a
# normal turret leaves both at their defaults (1.0 / 0.0, i.e. no override).
var fire_rate_multiplier: float = 1.0
var lifetime_override: float = 0.0 # 0 = use weapon.turret_lifetime unmodified

# 2026-08-18 (Breakout mini-jeu — bricks/popup enemies reuse THIS node
# wholesale for their HP/destruction/ball-deflection/projectile-hit
# behavior, all already working) — an unset (alpha 0) override leaves the
# normal green/pink owner_side coloring untouched everywhere else.
var color_override := Color(0.0, 0.0, 0.0, 0.0)

# 2026-08-18 (Breakout mini-jeu) — BallNode._resolve_turrets() only ever
# DEFLECTS the ball off a turret, never damages it (correct for a real
# Controleur turret — the ball bouncing off shouldn't chip it, only
# enemy projectiles should). Bricks need the opposite: every ball bounce
# should also chip them, classic Breakout. 0 (default, every real turret)
# = unchanged deflect-only behavior; >0 opts a specific instance in.
var ball_bounce_damage: float = 0.0

# 2026-08-22 (Space Invaders mini-jeu — real alien art) — an opt-in list of
# textures replaces the plain colored polygon with a Sprite2D instead, sized
# to fill half_extents*2 (assumes a square source texture). More than one
# texture animates as a simple flipbook (SPRITE_FRAME_DURATION per frame,
# looping) — used for the two alien frames Camil supplied. Empty (default)
# leaves every other turret/brick untouched.
var sprite_textures: Array[Texture2D] = []
const SPRITE_FRAME_DURATION := 0.4

var _visual: Polygon2D
var _sprite: Sprite2D
var _sprite_frame_index := 0
var _sprite_frame_timer := 0.0
var _lifetime_left := 0.0 # set from weapon.turret_lifetime in _ready() — weapon isn't assigned yet at field-init time
var _fire_cooldown := 0.0
var _flash_timer := 0.0
const FLASH_DURATION := 0.08

func _ready() -> void:
	hp = weapon.turret_hp
	_lifetime_left = lifetime_override if lifetime_override > 0.0 else weapon.turret_lifetime
	if is_instance_valid(follow_ship):
		position = follow_ship.position + follow_offset
	if sprite_textures.size() > 0:
		_sprite = Sprite2D.new()
		_sprite.texture = sprite_textures[0]
		_sprite.centered = true
		var tex_size := sprite_textures[0].get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			_sprite.scale = Vector2(half_extents.x * 2.0 / tex_size.x, half_extents.y * 2.0 / tex_size.y)
		add_child(_sprite)
	else:
		_visual = Polygon2D.new()
		# 0.8x half_extents (2026-08-09 playtest) — sits a hair inside the real
		# hitbox so the debug hitbox-overlay stroke (_draw() below) reads as
		# visibly distinct from the fill. Fine for a lone Controleur turret,
		# but Breakout's bricks are packed edge-to-edge on the FULL hitbox
		# (zero gap) — that same 20% margin then shows up as a visible gap
		# BETWEEN adjacent bricks where the real (untouched) collision boxes
		# still connect, so shots/the ball appeared to stop in "empty" space
		# (2026-08-18 bug report: "des fois les tirs s'arretent sur du vide,
		# comme s'ils touchaient un ennemi ou une brique qui ont disparu").
		# visual_fill_ratio (opt-in, defaults to the same 0.8) lets a packed
		# instance close that gap without changing a real turret's look.
		var visual_half := half_extents * visual_fill_ratio
		_visual.polygon = PackedVector2Array([
			Vector2(-visual_half.x, -visual_half.y), Vector2(visual_half.x, -visual_half.y),
			Vector2(visual_half.x, visual_half.y), Vector2(-visual_half.x, visual_half.y),
		])
		_visual.color = Color(0.4, 0.9, 0.4) if owner_side == 0 else Color(0.9, 0.4, 0.9)
		if color_override.a > 0.0:
			_visual.color = color_override
		if fire_rate_multiplier > 1.0:
			_visual.color = _visual.color.lightened(0.4) # visibly distinct from a normal turret — "tire 4x plus vite" should read as different at a glance
		add_child(_visual)
	_fire_cooldown = 1.0 / (weapon.fire_rate * fire_rate_multiplier)

func _physics_process(delta: float) -> void:
	_lifetime_left -= delta
	if _lifetime_left <= 0.0 or not is_instance_valid(target):
		queue_free()
		return

	if is_instance_valid(follow_ship):
		position = follow_ship.position + follow_offset

	if autofire:
		_fire_cooldown -= delta
		if _fire_cooldown <= 0.0:
			_fire_cooldown = 1.0 / (weapon.fire_rate * fire_rate_multiplier)
			_fire_at_target()

	if _sprite and sprite_textures.size() > 1:
		_sprite_frame_timer -= delta
		if _sprite_frame_timer <= 0.0:
			_sprite_frame_timer = SPRITE_FRAME_DURATION
			_sprite_frame_index = (_sprite_frame_index + 1) % sprite_textures.size()
			_sprite.texture = sprite_textures[_sprite_frame_index]

	_flash_timer = maxf(_flash_timer - delta, 0.0)
	var flash_tint := Color(1.7, 1.7, 1.7) if _flash_timer > 0.0 else Color(1.0, 1.0, 1.0)
	if _sprite:
		_sprite.modulate = flash_tint
	elif _visual:
		_visual.modulate = flash_tint
	queue_redraw() # cheap even when DebugOverlay.show_hitboxes is false — _draw() below just no-ops

## 2026-08-10 (see ShipNode._draw() for the full note on why the stroke is
## wide, not thin, and why this is a get_node_or_null() lookup rather than
## a direct DebugOverlay reference) — draws the EXACT rect ProjectileNode's
## swept hit-check tests against.
func _draw() -> void:
	var debug := get_node_or_null("/root/DebugOverlay")
	if debug and debug.show_hitboxes:
		draw_rect(Rect2(-half_extents, half_extents * 2.0), Color(1.0, 0.15, 0.15, 0.9), false, 4.0)

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

## Fires immediately regardless of the cooldown, ignoring `autofire` — the
## satellite-turret escort path (see the follow_ship/autofire block above).
## Accepts an (unused) WeaponData so it can bind directly to ShipNode's
## weapon_fired(weapon) signal without a wrapping lambda.
func fire_now(_weapon: WeaponData = null) -> void:
	if is_instance_valid(target):
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
