extends SceneTree

## Headless smoke test for the "shmup juice pass" (2026-08-05) — exercises the
## pure simulation classes directly (no Input simulation needed/possible in
## headless mode) plus the node-level boomerang math via manual _physics_process
## calls. Run with:
##   Godot --headless --path godot_project -s res://tests/smoke_test.gd
## Not a permanent CI fixture — ad hoc verification for code written without
## a Godot runtime available. Safe to delete once trusted.

var _failures := 0

func _initialize() -> void:
	print("--- smoke test start ---")
	_test_laser_pulse()
	_test_missile_swarm_data()
	_test_boomerang_motion()
	_test_stun_also_deals_damage()
	_test_mini_shot_data()
	_test_turret_destructible()
	_test_turret_ball_deflection()
	_test_turbo_trail()
	_test_gauge_floor_twist()
	_test_hazard_zone()
	_test_decoy_wander()
	_test_energy_orb_pickup()
	_test_ball_hazard_bounce()
	_test_lift_spin_stays_returnable()
	_test_character_ship_art()
	_test_twist_pool_authoring()
	_test_campaign_data_resources()
	_test_campaign_save()
	_test_campaign_context_sequencing()
	_test_campaign_context_debug_fight()
	_test_campaign_save_progress_tracking()
	_test_vif_campaign_authoring()
	_test_gauges_reset_between_rounds()
	_test_weapon_heat_gauge()
	_test_mitrailleur_double_fire_rule()
	_test_dash_lift_rule()
	_test_lift_charge_rework()
	_test_vif_reverted_to_shared_lift()
	_test_weapon_exclusivity()
	_test_every_charge_capable_weapon_actually_slows()
	_test_vortex_weapon()
	_test_projectile_tunneling_fix()
	_test_hit_half_size_matches_sprite()
	_test_charged_fire_burst()
	_test_heavy_push_rule()
	_test_match_state()
	_test_floating_text_node()
	_test_ultra_meter()
	# NOTE: a round-end turret cleanup test belongs here in spirit, but
	# MatchArenaNode can't be loaded under this harness — this file runs via
	# `-s`, which does not initialize project autoloads (confirmed 2026-08-07),
	# and match_arena_node.gd references the MatchSetup autoload at compile
	# time. See tests/round_end_check.gd for the scene-boot-based equivalent.
	print("--- smoke test done: %d failure(s) ---" % _failures)
	quit(1 if _failures > 0 else 0)

func _check(label: String, condition: bool) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		_failures += 1

func _test_laser_pulse() -> void:
	# 2026-08-09 redesign (Zoneur: "le tir normal de zoneur n'est pas bien.
	# je propose un laser qui traverse toute la map, mais qui ne dure que
	# 0.5 secondes... cooldown 0.8 seconde. Le tir charge lache le gros
	# laser, qui dure 3 secondes... et est 2 fois plus epais.") — the laser
	# is no longer a continuous hold-to-channel weapon; it fires a discrete,
	# timed pulse through the exact same fired()/cooldown/charge flow as
	# every other weapon.
	var laser: WeaponData = load("res://data/weapons/laser.tres")
	_check("laser effect_type == beam", laser.effect_type == "beam")
	_check("laser reaches across the whole arena (no more 'must close distance')", laser.beam_range > 1200.0)
	_check("laser's normal pulse is short (~0.5s)", is_equal_approx(laser.beam_duration, 0.5))
	_check("laser's cooldown between pulses is ~0.8s", is_equal_approx(1.0 / laser.fire_rate, 0.8))
	_check("laser's charged pulse lasts much longer (3s)", is_equal_approx(laser.charged_beam_duration, 3.0))
	_check("laser's charged pulse is 2x thicker", is_equal_approx(laser.charged_beam_thickness_multiplier, 2.0))
	_check("laser's charge actually slows movement (the vortex.tres bug can never recur silently)", laser.charge_fire_slow_multiplier < 1.0 and laser.charge_fire_slow_multiplier > 0.0)

	# fired() now works for the laser exactly like any other weapon —
	# cooldown-gated, one-time gauge cost, no more continuous drain.
	var state := WeaponSystemState.new([laser])
	state = state.with_gauge_added(laser.gauge_max)
	var result := state.fired()
	_check("laser fires as a normal discrete shot", result.fired)
	state = result.state
	_check("laser's cooldown is set after firing", is_equal_approx(state.cooldown, 1.0 / laser.fire_rate))
	var immediate_refire := state.fired()
	_check("laser can't refire during its own cooldown", not immediate_refire.fired)

func _test_missile_swarm_data() -> void:
	var missile: WeaponData = load("res://data/weapons/homing_missile.tres")
	_check("missile projectile_count > 1", missile.projectile_count > 1)
	_check("missile burst_spread_deg > 0", missile.burst_spread_deg > 0.0)
	_check("missile still homes", missile.homing_strength > 0.0)
	# 2026-08-10 nerf: "le missile teleguide c'est vraiment fort... en lacher
	# que 3, et calmer le cote teleguide, -20% de precision".
	_check("missile swarm was trimmed to 3 (was 4)", missile.projectile_count == 3)
	_check("missile homing was calmed by 20% (was 2.5)", is_equal_approx(missile.homing_strength, 2.0))
	# Traqueur's charged fire (2026-08-10): "le tir charge de missiles
	# teleguides ne marche plus" — it never existed yet; a staggered rafale,
	# double the normal count, per the original brainstorm note.
	_check("Traqueur's charged fire is configured", missile.charge_fire_duration > 0.0)
	_check("Traqueur's charge actually slows movement", missile.charge_fire_slow_multiplier < 1.0)
	_check("Traqueur's charged burst doubles the missile count", missile.charged_projectile_count == missile.projectile_count * 2)
	_check("Traqueur's charged burst is staggered like a rafale, not simultaneous", missile.charged_stagger > 0.0)

func _test_mini_shot_data() -> void:
	# Redesigned 2026-08-06: "mini zonk" idea dropped in favor of a fan burst
	# (Air Zonk-style card weapons) — max 1 shot/sec, 5 projectiles fanned out,
	# reusing the same projectile_count/burst_spread_deg system as the missile
	# swarm rather than the earlier "rapid single bullets" bullet-rain tuning.
	var mini: WeaponData = load("res://data/weapons/mini_shot.tres")
	_check("mini_shot fires at most once per second", mini.fire_rate <= 1.0)
	_check("mini_shot fans out 5 projectiles per shot", mini.projectile_count == 5)
	# 2026-08-06 playtest: "je resserrerais l'angle" — narrowed from the
	# original 70° fan, but still a fan (not a single tight line).
	_check("mini_shot fan is narrower than the original 70°", mini.burst_spread_deg > 0.0 and mini.burst_spread_deg < 70.0)
	_check("mini_shot fan fires simultaneously, not staggered like the missile swarm", mini.burst_stagger == 0.0)
	_check("mini_shot has no per-shot angle jitter (2026-08-06: 'pas de random sur les angles')", mini.spread_deg == 0.0)
	# 2026-08-06 playtest: "tu peux doubler sa taille" (2x), then 2026-08-09
	# "un peu gros" trimmed it to 70% (2x*0.7=1.4x-equivalent effective
	# size). 2026-08-13: bonbon.png's native resolution doubled (20x16 ->
	# 40x32) and visual_scale_multiplier was halved to compensate (2.8 ->
	# 1.4) so the on-screen/hitbox footprint is unchanged — checked here as
	# the EFFECTIVE pixel size (texture_size * multiplier), which is the
	# actual invariant, not a raw multiplier value now tied to a specific
	# source asset's resolution.
	var bonbon_texture: Texture2D = preload("res://assets/art/vfx/bonbon.png")
	var mini_shot_effective_size := bonbon_texture.get_size() * mini.visual_scale_multiplier
	_check("mini_shot's effective on-screen size matches the tuned ~56x45px target, independent of the source art's own resolution", is_equal_approx(mini_shot_effective_size.x, 56.0) and is_equal_approx(mini_shot_effective_size.y, 44.8))
	_check("mini_shot spins in place (single-sprite art, no multi-frame cycle like the Tourbillon)", mini.projectile_spin_speed > 0.0)

	# 2026-08-09 — Mini's charged fire ("Tir charge : lance 10 des eventails
	# de haut en bas (un peu comme un arroseur automatique) avec un espace
	# de 1/8 de seconde entre chaque eventail"), reusing the same generic
	# charged_* burst framework as Lourd/Vif — no new engine code needed.
	_check("mini_shot has a charged fire configured", mini.charge_fire_duration > 0.0)
	_check("mini_shot's charged fire launches 10 shots", mini.charged_projectile_count == 10)
	_check("mini_shot's charged shots are staggered 1/8s apart", is_equal_approx(mini.charged_stagger, 0.125))
	_check("mini_shot's charged fire sweeps a wide vertical spread (top to bottom)", mini.charged_burst_spread_deg > 45.0)

	# 2026-08-09: "il faudrait resserer encore l'angle: 60, par contre
	# balayer de haut en bas puis remonter de bas en haut. ce serait bien
	# plus fun" — a triangle-wave sweep instead of one-way linear. The
	# actual burst spawn loop lives in MatchArenaNode (needs a scene/
	# autoloads), so just the formula is checked here directly, same
	# approach as the blink-period math above.
	_check("mini_shot's charged spread was narrowed to 60 deg", is_equal_approx(mini.charged_burst_spread_deg, 60.0))
	_check("mini_shot's charged sweep is a ping-pong (out and back), not one-way", mini.charged_burst_ping_pong)
	var count := mini.charged_projectile_count
	var mid := int(float(count - 1) / 2.0)
	var t_first := 1.0 - absf(2.0 * (0.0 / float(count - 1)) - 1.0)
	var t_mid := 1.0 - absf(2.0 * (float(mid) / float(count - 1)) - 1.0)
	var t_last := 1.0 - absf(2.0 * (float(count - 1) / float(count - 1)) - 1.0)
	_check("the ping-pong sweep starts at one extreme (t=0)", is_zero_approx(t_first))
	_check("the ping-pong sweep reaches near the other extreme around the middle shot", t_mid > 0.8) # an even shot count never lands exactly on the peak index
	_check("the ping-pong sweep returns to the start extreme by the last shot (t=0)", is_zero_approx(t_last))

func _test_boomerang_motion() -> void:
	var boomerang_data: WeaponData = load("res://data/weapons/stun_boomerang.tres")
	_check("stun_boomerang is_boomerang flag set", boomerang_data.is_boomerang)
	_check("stun_boomerang has a charged fire configured", boomerang_data.charge_fire_duration > 0.0)
	_check("stun_boomerang's charge actually slows movement", boomerang_data.charge_fire_slow_multiplier < 1.0)
	_check("stun_boomerang's charged release goes further (2026-08-10: 'plus on charge, plus le boomerang va loin')", boomerang_data.charged_boomerang_out_duration > 0.0)
	# 2026-08-10 redesign: "il faudrait que le boomerang aille plus loin...
	# et que je puisse tirer 3 boomerangs avant cooldown (un peu comme pour
	# les missiles)". Normal range extended enough to cross the whole arena
	# (1200px wide) from the shooter's own edge: at the default 620px/s,
	# boomerang_out_duration=2.0 covers ~1240px outbound.
	_check("stun_boomerang fires 3 per press, like the missile swarm", boomerang_data.projectile_count == 3)
	_check("stun_boomerang's normal range crosses the whole arena", boomerang_data.boomerang_out_duration * 620.0 > 1200.0)
	# "Tir charge: tire un enorme boomerang (5 fois la taille, 5x degats)".
	_check("stun_boomerang's charged release is a single giant boomerang", boomerang_data.charged_projectile_count == 1)
	_check("stun_boomerang's charged release is 5x damage", is_equal_approx(boomerang_data.charged_damage_multiplier, 5.0))
	_check("stun_boomerang's charged release is 5x size", is_equal_approx(boomerang_data.charged_visual_scale_multiplier, 5.0))

	var shooter := ShipNode.new()
	shooter.position = Vector2(200, 300)

	# 2026-08-10 bug reports, in order:
	# 1) "boomerang ne marche pas du tout" — the outbound leg used to curve a
	#    fixed direction no matter where the target was.
	# 2) "les boomerangs ne doivent pas etre teleguides !" — chasing the
	#    target's live position landed hits but read as a homing missile.
	# 3) Final design: "une trajectoire unique: ca part sur un angle a 30 deg
	#    et revient sur -30 deg. Par defaut ca part du haut (30 -> -30). Si
	#    je descends, ca part du bas (-30 -> 30). Si je monte, ca part du
	#    haut (30 -> -30)." — a fixed, deterministic arc with NO reference to
	#    the target at all (can't be "guided" by construction); only the
	#    shooter's own last movement direction picks which end it starts from.
	var target := ShipNode.new()
	target.position = Vector2(900, 500) # deliberately irrelevant to the outcome now — see the checks below

	var default_throw := ProjectileNode.new()
	default_throw.is_boomerang = true
	default_throw.shooter = shooter
	default_throw.target = target
	default_throw.position = shooter.position
	default_throw.velocity = Vector2(620, 0)
	default_throw.boomerang_descending_throw = false # neutral/"monte" case
	default_throw.lifetime = 3.0
	default_throw.textures = [] # forces the fallback Polygon2D path in _ready(), no art needed

	root.add_child(shooter)
	root.add_child(target)
	root.add_child(default_throw)
	# This synchronous harness never calls _ready() on its own (same gotcha
	# as the turret test above) — invoke it manually so _boomerang_base_
	# velocity/_boomerang_start_deg/_boomerang_end_deg get captured.
	default_throw._ready()
	var outbound_start := default_throw.position
	# `velocity` only gets rotated to the start angle once _update_boomerang()
	# actually runs — _ready() only captures the baseline/angles — so this
	# has to be checked after the first physics tick, not before it.
	default_throw._physics_process(1.0 / 30.0)
	_check("default (non-descending) throw starts angled UP (+30deg = negative y, Godot y-down)", default_throw.velocity.y < 0.0)
	for i in 4: # remaining frames up to ~0.17s in — still inside the default 0.45s outbound window
		default_throw._physics_process(1.0 / 30.0)
	_check("boomerang left its spawn point", default_throw.position.distance_to(outbound_start) > 1.0)

	# Move the target mid-flight — the outbound leg no longer references
	# `target` at all (see the sign-flip checks below for the real proof
	# that the arc is deterministic and unaffected by this).
	target.position = Vector2(900, 50)
	for i in 5: # remaining frames up to ~0.33s, still inside the 0.45s outbound window
		default_throw._physics_process(1.0 / 30.0)

	for i in 10: # push on past the 0.45s outbound window
		default_throw._physics_process(1.0 / 30.0)
	_check("boomerang has entered the return phase after 0.67s", default_throw._boomerang_returning)
	# By the end of the outbound leg it must have swept all the way to -30deg
	# (positive y, Godot y-down) — starts up, ends down, "revient sur -30 deg".
	_check("default throw ends the outbound leg angled DOWN (-30deg = positive y)", default_throw.velocity.y > 0.0)

	# "Si je descends, ca part du bas (-30 -> 30)" — the mirrored case.
	var descending_throw := ProjectileNode.new()
	descending_throw.is_boomerang = true
	descending_throw.shooter = shooter
	descending_throw.target = target
	descending_throw.position = shooter.position
	descending_throw.velocity = Vector2(620, 0)
	descending_throw.boomerang_descending_throw = true
	descending_throw.lifetime = 3.0
	descending_throw.textures = []
	root.add_child(descending_throw)
	descending_throw._ready() # see the note on default_throw._ready() above
	descending_throw._physics_process(1.0 / 30.0) # see the note on the same first-tick requirement above
	_check("a descending throw starts angled DOWN instead (-30deg = positive y)", descending_throw.velocity.y > 0.0)
	for i in 19: # push the rest of the way through the outbound window
		descending_throw._physics_process(1.0 / 30.0)
	_check("a descending throw ends the outbound leg angled UP (+30deg = negative y) — mirrored from the default", descending_throw.velocity.y < 0.0)
	descending_throw.queue_free()

	# queue_free() defers actual deallocation to the next idle frame, which
	# never happens here since we're driving _physics_process manually rather
	# than running the real engine loop — so track the closest approach
	# instead of relying on is_instance_valid() to observe the free() call.
	var closest := INF
	for i in 60: # give it time to actually arc back toward the shooter
		if not is_instance_valid(default_throw):
			break
		default_throw._physics_process(1.0 / 30.0)
		closest = minf(closest, default_throw.position.distance_to(shooter.position))
	_check("boomerang comes within catch distance of the shooter (closest=%.1f)" % closest, closest < ProjectileNode.BOOMERANG_CATCH_DISTANCE)

	# 2026-08-11, Camil: "les boomerangs, a leur retour, ne doivent pas
	# forcement revenir sur le joueur qui les a lance. Si le joueur bouge
	# trop vite et 'evite' son propre boomerang, alors celui-ci continue sa
	# trajectoire et part dans le fond du joueur." — get a throw engaged
	# (closing in) on the return leg, then have the shooter dodge (teleport
	# away, simulating a fast dash) — the boomerang must give up homing
	# instead of chasing forever.
	var dodge_shooter := ShipNode.new()
	dodge_shooter.position = Vector2(200, 300)
	var dodge_throw := ProjectileNode.new()
	dodge_throw.is_boomerang = true
	dodge_throw.shooter = dodge_shooter
	dodge_throw.target = target
	dodge_throw.position = dodge_shooter.position
	dodge_throw.velocity = Vector2(620, 0)
	dodge_throw.boomerang_out_duration = 0.2 # short outbound so the test reaches the return leg quickly
	dodge_throw.lifetime = 5.0
	dodge_throw.textures = []
	root.add_child(dodge_shooter)
	root.add_child(dodge_throw)
	dodge_throw._ready()
	for i in 15: # push well past the 0.2s outbound window into the return leg
		dodge_throw._physics_process(1.0 / 30.0)
	_check("dodge test setup: boomerang is on its return leg", dodge_throw._boomerang_returning)
	# Let it actually close in first — arms the miss-detection (see
	# BOOMERANG_MISS_ENGAGE_DISTANCE's comment: a real close pass is
	# required, not just "it hasn't turned around yet").
	for i in 30:
		if dodge_throw._boomerang_return_closest_dist <= ProjectileNode.BOOMERANG_MISS_ENGAGE_DISTANCE:
			break
		dodge_throw._physics_process(1.0 / 30.0)
	_check("dodge test setup: boomerang actually closed in on the shooter first", dodge_throw._boomerang_return_closest_dist <= ProjectileNode.BOOMERANG_MISS_ENGAGE_DISTANCE)
	# Now the dodge: teleport the shooter far away in one frame, well beyond
	# BOOMERANG_MISS_MARGIN — the boomerang can't possibly have "just not
	# turned around yet" from this.
	dodge_shooter.position += Vector2(400, 0)
	dodge_throw._physics_process(1.0 / 30.0)
	_check("boomerang detects a dodge (missed the catch)", dodge_throw._boomerang_missed_catch)
	var velocity_at_miss := dodge_throw.velocity
	for i in 10: # it should now coast in a straight line, not keep turning back toward the shooter
		dodge_throw._physics_process(1.0 / 30.0)
	_check("a missed boomerang stops homing and coasts straight (velocity unchanged)", dodge_throw.velocity.is_equal_approx(velocity_at_miss))
	dodge_shooter.queue_free()
	if is_instance_valid(dodge_throw):
		dodge_throw.queue_free()

	target.queue_free()

	shooter.queue_free()

## 2026-08-10: a "stun" hit used to ignore the projectile's `damage` field
## entirely, so Perturbateur's "tir charge: 5x degats" request had nothing to
## multiply. _apply_hit_effect() now also chips real HP on top of the stun
## whenever damage > 0.
func _test_stun_also_deals_damage() -> void:
	var target := ShipNode.new()
	target.position = Vector2(500, 300)
	target.half_extents = Vector2(14, 28)
	target.state = ShipState.new(target.position, 0, target.half_extents) # apply_damage() needs this — normally built in _ready(), never called by this harness
	var starting_hp := target.state.hp

	var stun_hit := ProjectileNode.new()
	stun_hit.effect_type = "stun"
	stun_hit.effect_duration = 1.0
	stun_hit.damage = 5 # e.g. a charged boomerang's 1 * charged_damage_multiplier(5.0)
	stun_hit.target = target
	stun_hit._apply_hit_effect()

	_check("a stun hit still stuns", target._stun_timer > 0.0)
	_check("a stun hit with damage>0 also chips real HP", target.state.hp == starting_hp - 5)

	var pure_stun := ProjectileNode.new()
	pure_stun.effect_type = "stun"
	pure_stun.effect_duration = 1.0
	pure_stun.damage = 0
	pure_stun.target = target
	var hp_before_pure_stun := target.state.hp
	pure_stun._apply_hit_effect()
	_check("a stun hit with damage==0 does not touch HP (a stun weapon can still be pure annoyance, no chip, by leaving damage unset)", target.state.hp == hp_before_pure_stun)

	target.queue_free()

func _test_turret_destructible() -> void:
	var turret_data: WeaponData = load("res://data/weapons/turret.tres")
	_check("turret has HP defined", turret_data.turret_hp > 0.0)
	_check("turret lifetime is 20-30s (2026-08-05 playtest: was a flat 6s)", turret_data.turret_lifetime >= 20.0 and turret_data.turret_lifetime <= 30.0)
	# Controleur's charged turret (2026-08-10): "il manque le tir charge de
	# controleur. idee: pose une tourelle ephemere, qui tire 4x plus vite,
	# mais ne dure que 5 secondes".
	_check("Controleur's charged fire is configured", turret_data.charge_fire_duration > 0.0)
	_check("Controleur's charge actually slows movement", turret_data.charge_fire_slow_multiplier < 1.0)
	_check("the charged turret fires 4x faster", is_equal_approx(turret_data.charged_turret_fire_rate_multiplier, 4.0))
	_check("the charged turret only lasts 5 seconds", is_equal_approx(turret_data.charged_turret_lifetime, 5.0))

	# The override fields must actually reach TurretNode's own timers, not
	# just sit on the WeaponData resource.
	var charged_turret := TurretNode.new()
	charged_turret.weapon = turret_data
	charged_turret.owner_side = 0
	charged_turret.fire_rate_multiplier = turret_data.charged_turret_fire_rate_multiplier
	charged_turret.lifetime_override = turret_data.charged_turret_lifetime
	var normal_turret := TurretNode.new()
	normal_turret.weapon = turret_data
	normal_turret.owner_side = 0
	root.add_child(charged_turret)
	root.add_child(normal_turret)
	charged_turret._ready() # this harness never calls _ready() on its own (see turret.hp comment above) — invoke it manually, same convention used elsewhere in this file
	normal_turret._ready()
	_check("a charged turret's fire cooldown is 4x shorter than a normal turret's", is_equal_approx(charged_turret._fire_cooldown, normal_turret._fire_cooldown / 4.0))
	_check("a charged turret's lifetime is overridden to 5s, not the normal 20-30s", is_equal_approx(charged_turret._lifetime_left, 5.0))
	_check("a normal turret keeps its full lifetime unaffected", is_equal_approx(normal_turret._lifetime_left, turret_data.turret_lifetime))
	charged_turret.queue_free()
	normal_turret.queue_free()

	var enemy_ship := ShipNode.new()
	enemy_ship.side = 0 # the turret below defends side 0, against fire aimed at a side-0 ship

	var turret := TurretNode.new()
	turret.weapon = turret_data
	turret.owner_side = 0
	turret.position = Vector2(300, 300)
	turret.target = enemy_ship
	turret.hp = turret_data.turret_hp # normally set in _ready(), which the engine never calls in this synchronous harness

	root.add_child(enemy_ship)
	root.add_child(turret)

	# 2026-08-10 bug report: "j'ai l'impression que tous les tirs ne touchent
	# pas les tourelles de controleur" — hit detection moved from a per-frame
	# TurretNode poll (a point-only check, plus order-dependent on top of
	# that) into ProjectileNode's own physics step, using the same swept
	# segment check as the ship/vortex tunneling fix. Exercise it with a shot
	# that starts clearly outside the turret's rect and ends clearly on the
	# other side in a single step — neither endpoint alone would register.
	var starting_hp := turret.hp
	var incoming := ProjectileNode.new()
	incoming.position = turret.position - Vector2(20, 0) # just left of the turret's rect (HALF_EXTENTS=15)
	incoming.velocity = Vector2(1200, 0) # far enough per-frame to land right of it too
	incoming.damage = 5
	incoming.target = enemy_ship # target.side == turret.owner_side -> recognized as a threat to this turret
	incoming.textures = []
	root.add_child(incoming)

	incoming._physics_process(1.0 / 30.0)
	_check("turret takes damage from a fast enemy shot that would tunnel past a point-only check", turret.hp == starting_hp - 5)
	_check("the consumed projectile is queued for deletion", incoming.is_queued_for_deletion())

	# A friendly shot (target on the OTHER side) passing through must NOT hurt it.
	var friendly := ProjectileNode.new()
	friendly.position = turret.position - Vector2(20, 0)
	friendly.velocity = Vector2(1200, 0)
	friendly.damage = 99
	var opponent_ship := ShipNode.new()
	opponent_ship.side = 1
	root.add_child(opponent_ship)
	friendly.target = opponent_ship
	friendly.textures = []
	root.add_child(friendly)
	var hp_before_friendly := turret.hp
	friendly._physics_process(1.0 / 30.0)
	_check("turret ignores an overlapping friendly-side projectile", turret.hp == hp_before_friendly)

	enemy_ship.queue_free()
	opponent_ship.queue_free()
	if is_instance_valid(turret):
		turret.queue_free()

func _test_turret_ball_deflection() -> void:
	# 2026-08-09 playtest (Contrôleur): "les tourelles pourraient renvoyer la
	# balle aussi ! ce serait genial" — a turret now acts like a stationary
	# paddle, mirror-bouncing the ball just like a ship would.
	_check("turret HALF_EXTENTS is 1.5x the old 10x10 (2026-08-09 playtest: easier to aim at)", TurretNode.HALF_EXTENTS == Vector2(15, 15))

	var turret_data: WeaponData = load("res://data/weapons/turret.tres")
	var turret := TurretNode.new()
	turret.weapon = turret_data
	turret.owner_side = 0
	turret.position = Vector2(200, 300)
	root.add_child(turret)

	var ball := BallNode.new()
	ball.arena_bounds = Rect2(0, 0, 1280, 720)
	ball.frontier_x = 640.0
	ball.state = BallState.new(turret.position, Vector2(-BallState.BASE_SPEED, 0.0)) # heading away from the opponent, into the turret
	root.add_child(ball)

	ball._resolve_turrets()
	_check("ball bounces off an overlapping turret (velocity reverses toward the opponent)", ball.state.velocity.x > 0.0)

	var velocity_after_first_bounce := ball.state.velocity
	ball._resolve_turrets()
	_check("a turret can't re-bounce the ball within the same cooldown/visit", ball.state.velocity == velocity_after_first_bounce)

	turret.queue_free()
	ball.queue_free()

func _test_turbo_trail() -> void:
	var ship := ShipNode.new()
	ship.position = Vector2(400, 300)
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([Vector2(-14, -28), Vector2(14, -28), Vector2(14, 28), Vector2(-14, 28)])
	ship.add_child(visual)
	root.add_child(ship)

	var children_before := root.get_child_count()
	ship._spawn_trail_ghost()
	_check("turbo trail spawns a ghost node", root.get_child_count() == children_before + 1)
	var ghost: Node = root.get_child(root.get_child_count() - 1)
	_check("ghost copies the ship's polygon", ghost is Polygon2D and (ghost as Polygon2D).polygon == visual.polygon)
	_check("ghost is translucent (not opaque)", (ghost as Polygon2D).color.a < 1.0)

	ghost.queue_free()
	ship.queue_free()

func _test_gauge_floor_twist() -> void:
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	var ship := ShipNode.new()
	ship.weapon_state = WeaponSystemState.new([machine_gun])

	ship.self_fill_locked = true
	ship.fill_selected_gauge(10.0)
	_check("gauge_floor twist never blocks the miss-fill path (Story 1.6)", ship.weapon_state.gauges[0] == 10.0)

	ship.fill_selected_gauge_from_return(10.0)
	_check("gauge_floor twist blocks the self-fill-on-return path when locked", ship.weapon_state.gauges[0] == 10.0)

	ship.self_fill_locked = false
	ship.fill_selected_gauge_from_return(10.0)
	_check("self-fill-on-return works normally once unlocked", ship.weapon_state.gauges[0] == 20.0)

	ship.weapon_state = WeaponSystemState.new([machine_gun]) # reset to 0
	ship.passive_trickle_rate = 100.0
	ship._apply_passive_trickle(0.5)
	var expected_trickle := machine_gun.gauge_max * 0.5
	_check(
		"passive trickle adds gauge over time (%.1f expected, got %.1f)" % [expected_trickle, ship.weapon_state.gauges[0]],
		is_equal_approx(ship.weapon_state.gauges[0], expected_trickle)
	)

	ship.queue_free()

func _test_hazard_zone() -> void:
	var target_ship := ShipNode.new()
	target_ship.position = Vector2(300, 300)
	target_ship.half_extents = Vector2(14, 28)

	var hazard := HazardZoneNode.new()
	hazard.position = Vector2(300, 300) # overlapping the ship
	hazard.radius = 24.0
	hazard.stuns_ships = true
	hazard.deflects_ball = false
	hazard.ships = [target_ship]

	root.add_child(target_ship)
	root.add_child(hazard)

	hazard._physics_process(1.0 / 30.0)
	_check("hazard zone stuns an overlapping ship", target_ship._stun_timer > 0.0)

	target_ship.queue_free()
	hazard.queue_free()

func _test_decoy_wander() -> void:
	var decoy := DecoyNode.new()
	decoy.arena_bounds = Rect2(Vector2(40, 60), Vector2(1200, 600))
	decoy.wander_speed = 500.0
	decoy.position = Vector2(640, 360)
	root.add_child(decoy)

	var start := decoy.position
	for i in 30:
		decoy._physics_process(1.0 / 30.0)
	_check("decoy moves over time (wanders)", decoy.position.distance_to(start) > 1.0)
	_check("decoy stays within arena bounds", decoy.arena_bounds.has_point(decoy.position))

	decoy.queue_free()

func _test_energy_orb_pickup() -> void:
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	var ship := ShipNode.new()
	ship.weapon_state = WeaponSystemState.new([machine_gun])
	ship.half_extents = Vector2(14, 28)
	ship.position = Vector2(300, 300)

	var orb := EnergyOrbNode.new()
	orb.position = Vector2(300, 300) # overlapping
	orb.gauge_bonus_percent = 20.0
	orb.ships = [ship]

	root.add_child(ship)
	root.add_child(orb)

	orb._physics_process(1.0 / 30.0)
	var expected_orb := machine_gun.gauge_max * 0.2
	_check("energy orb grants +20% gauge on pickup", is_equal_approx(ship.weapon_state.gauges[0], expected_orb))
	_check("energy orb despawns after pickup", orb.is_queued_for_deletion())

	ship.queue_free()

func _test_ball_hazard_bounce() -> void:
	var state := BallState.new(Vector2(100, 0), Vector2(200, 0)) # moving right, hazard just ahead
	var hazard_center := Vector2(120, 0)
	var bounced := state.bounced_off_hazard(hazard_center)
	_check("hazard bounce reverses velocity on a head-on hit", bounced.velocity.x < 0.0)
	_check("hazard bounce preserves speed", is_equal_approx(bounced.velocity.length(), state.velocity.length()))

func _test_lift_spin_stays_returnable() -> void:
	# 2026-08-14 bug report (Camil, screenshot): "lors d'un lift, il m'arrive
	# d'avoir la balle qui est quasi verticale, donc l'echange est presque
	# impossible." A full-charge lift's spin curves the ball by ~114 degrees
	# total (see comment on MAX_SPIN_ANGLE_FROM_HORIZONTAL_RAD), which was
	# enough to spin an already-angled return well past vertical.
	var state := BallState.new(Vector2.ZERO, Vector2(1.0, 0.0), 0.0, 0)
	state = state.returned(Vector2(1.0, 1.0), 1.0, 1) # full-charge lift, steepest allowed aim, sent right
	var min_angle_from_vertical := INF
	for _i in range(240): # a couple of seconds at 1/60 — long enough for the full spin decay
		state = state.update(1.0 / 60.0)
		var angle_from_horizontal := absf(state.velocity.angle())
		min_angle_from_vertical = min(min_angle_from_vertical, absf(PI / 2.0 - angle_from_horizontal))
	_check("a fully-charged lift's spin never curves the ball past the near-vertical clamp", min_angle_from_vertical >= deg_to_rad(19.0))
	_check("the spin-curved ball keeps heading toward the side it was sent to (no reversal into the sender's own camp)", state.velocity.x > 0.0)

func _test_character_ship_art() -> void:
	# 2026-08-14 (Sally/party-mode session) — per-character paddle art.
	# CharacterArt is a real scene child (Ship.tscn), which bare
	# ShipNode.new() (every other test's pattern in this file) doesn't have,
	# so this test instances the actual scene instead.
	var scene: PackedScene = load("res://scenes/Ship.tscn")
	var ship := scene.instantiate() as ShipNode
	var missiles: CharacterData = load("res://data/characters/missiles.tres") # Traqueur — has assets/art/characters/missiles/ship.png
	ship.set_character(missiles)
	var sprite := ship.get_node_or_null("Visual/CharacterArt") as Sprite2D
	_check("a character with dedicated ship art gets its CharacterArt sprite shown", sprite != null and sprite.visible)
	_check("the sprite's texture is actually loaded, not left null", sprite.texture != null)
	_check("the sprite is scaled to match the ship's half_extents (28x56), not left at native art resolution", is_equal_approx(sprite.scale.x * sprite.texture.get_width(), ship.half_extents.x * 2.0) and is_equal_approx(sprite.scale.y * sprite.texture.get_height(), ship.half_extents.y * 2.0))

	var lourd: CharacterData = load("res://data/characters/lourd.tres") # no ship.png authored yet — must fall back to the flat Visual polygon, not crash
	ship.set_character(lourd)
	_check("a character without dedicated ship art yet falls back cleanly (sprite hidden, no crash)", not sprite.visible)

	ship.queue_free()

func _test_twist_pool_authoring() -> void:
	# 2026-08-09 bug report (Camil, cheat-menu testing): "Le twist zone du
	# milieu bouge n'existe pas" — drifting_neutral_zone (and visual_decoy,
	# multi_ball) had full engine support in match_arena_node.gd but no
	# authored .tres, so the cheat menu (which lists whatever's actually on
	# disk under data/twists/) never offered them. Every twist_type in
	# TwistData's enum except "none" and the boss-exclusive
	# "energy_orb_pickup" (data/twists/energy_orb_boss.tres) should now have
	# exactly one authored resource here.
	var expected_types := ["multi_ball", "gauge_floor", "shrinking_arena", "invisible_opponent", "hazard_zones", "drifting_neutral_zone", "visual_decoy"]
	var dir := DirAccess.open("res://data/twists")
	var found_types := {}
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var twist: TwistData = load("res://data/twists/%s" % f)
			found_types[twist.twist_type] = true
		f = dir.get_next()
	dir.list_dir_end()
	for expected in expected_types:
		_check("twist pool has an authored .tres for '%s'" % expected, found_types.has(expected))

	var drift: TwistData = load("res://data/twists/drifting_neutral_zone.tres")
	_check("drifting_neutral_zone has a positive drift_speed and drift_range", drift.drift_speed > 0.0 and drift.drift_range > 0.0)

func _test_campaign_data_resources() -> void:
	var mook_data: WeaponData = load("res://data/weapons/machine_gun.tres")
	var lourd: CharacterData = load("res://data/characters/lourd.tres")
	var vif: CharacterData = load("res://data/characters/vif.tres")

	var mook_encounter := RivalEncounterData.new()
	mook_encounter.opponent = lourd
	mook_encounter.is_mook = true
	mook_encounter.mook_hp_multiplier = 0.6
	mook_encounter.reward_currency = 100

	var rival_encounter := RivalEncounterData.new()
	rival_encounter.opponent = lourd
	rival_encounter.is_mook = false
	var gauge_floor := TwistData.new()
	gauge_floor.twist_type = "gauge_floor"
	rival_encounter.twist = gauge_floor
	rival_encounter.unlock_reward = mook_data # placeholder unlock for the smoke test, not a real design choice

	var branch := MiniBranchData.new()
	branch.id = "vs_lourd"
	branch.display_name = "Contre Lourd"
	branch.mook_1 = mook_encounter
	branch.mook_2 = mook_encounter
	branch.rival = rival_encounter

	var campaign := CampaignData.new()
	campaign.character = vif
	campaign.mini_branches = [branch]
	campaign.required_branch_count = 3

	_check("CampaignData wires a character + mini-branches", campaign.character == vif and campaign.mini_branches.size() == 1)
	_check("MiniBranchData carries mook + rival encounters", branch.rival.opponent == lourd and branch.rival.twist.twist_type == "gauge_floor")
	_check("required_branch_count matches the brainstorm's 3-4 range", campaign.required_branch_count >= 3 and campaign.required_branch_count <= 4)

func _test_campaign_save() -> void:
	# Loaded directly rather than via the CampaignSave autoload — this -s
	# harness doesn't initialize project autoloads (see round_end_check.gd's
	# note), but campaign_save.gd doesn't reference any autoload itself, so
	# instancing its script directly works fine for testing the plain data
	# API in isolation.
	var save_script := load("res://nodes/campaign_save.gd")
	var save = save_script.new()
	save.load_from_disk() # picks up whatever real save (if any) already exists on this machine

	const TEST_CHARACTER := "_smoke_test_character" # underscore-prefixed so it can never collide with a real roster id

	_check("fresh character starts with 0 currency", save.get_currency(TEST_CHARACTER) == 0)
	save.add_currency(TEST_CHARACTER, 100)
	save.add_currency(TEST_CHARACTER, 50)
	_check("currency accumulates across calls", save.get_currency(TEST_CHARACTER) == 150)

	_check("branch starts uncompleted", not save.is_branch_completed(TEST_CHARACTER, "vs_lourd"))
	save.mark_branch_completed(TEST_CHARACTER, "vs_lourd", "trace_lourd")
	_check("branch is completed after marking", save.is_branch_completed(TEST_CHARACTER, "vs_lourd"))
	_check("completed_branch_count reflects it", save.completed_branch_count(TEST_CHARACTER) == 1)
	_check("unlock is recorded", "trace_lourd" in save.unlocks_for(TEST_CHARACTER))
	save.mark_branch_completed(TEST_CHARACTER, "vs_lourd", "trace_lourd") # re-marking the same branch must not duplicate it
	_check("re-completing the same branch does not duplicate it", save.completed_branch_count(TEST_CHARACTER) == 1)

	_check("organizer starts undefeated", not save.is_organizer_defeated(TEST_CHARACTER))
	save.mark_organizer_defeated(TEST_CHARACTER)
	_check("organizer marked defeated persists in memory", save.is_organizer_defeated(TEST_CHARACTER))

	# Round-trip through the real save file, then verify a fresh instance reads it back.
	var reloaded_script := load("res://nodes/campaign_save.gd")
	var reloaded = reloaded_script.new()
	reloaded.load_from_disk()
	_check("a fresh instance reloads persisted currency from disk", reloaded.get_currency(TEST_CHARACTER) == 150)
	_check("a fresh instance reloads persisted branch completion from disk", reloaded.is_branch_completed(TEST_CHARACTER, "vs_lourd"))

	# Clean up: this test's entry should never linger in the player's real save file.
	save._data.erase(TEST_CHARACTER)
	save.save_to_disk()
	save.free()
	reloaded.free()

func _test_campaign_context_sequencing() -> void:
	# Loaded directly rather than via the CampaignContext autoload — same
	# rationale as _test_campaign_save(): this script references no other
	# autoload itself, so instancing it works fine under the -s harness.
	var context_script := load("res://nodes/campaign_context.gd")
	var context = context_script.new()

	var mook_1 := RivalEncounterData.new()
	mook_1.is_mook = true
	var mook_2 := RivalEncounterData.new()
	mook_2.is_mook = true
	var rival := RivalEncounterData.new()
	rival.is_mook = false

	var branch := MiniBranchData.new()
	branch.id = "vs_test"
	branch.mook_1 = mook_1
	branch.mook_2 = mook_2
	branch.rival = rival

	var campaign := CampaignData.new()
	context.start_branch(campaign, branch)
	_check("branch starts at step 0 (mook_1)", context.branch_step == 0 and context.current_encounter() == mook_1)

	_check("advance from step 0 moves to mook_2, reports more fights left", context.advance_branch_step() and context.current_encounter() == mook_2)
	_check("advance from step 1 moves to the rival, reports more fights left", context.advance_branch_step() and context.current_encounter() == rival)
	_check("advance from the rival reports the branch is complete", not context.advance_branch_step())
	_check("branch_step reached 3 (complete)", context.branch_step == 3)

	# 2026-08-08 regression: even if mook_1 and mook_2 happened to be
	# authored as the same resource, step-based sequencing must still tell
	# them apart (identity-based comparison couldn't).
	var context2 = context_script.new()
	var shared_mook := RivalEncounterData.new()
	shared_mook.is_mook = true
	var branch2 := MiniBranchData.new()
	branch2.mook_1 = shared_mook
	branch2.mook_2 = shared_mook
	branch2.rival = rival
	context2.start_branch(campaign, branch2)
	_check("step 0 reads as mook_1 even when mook_1 == mook_2 by identity", context2.branch_step == 0)
	context2.advance_branch_step()
	_check("step 1 reads as mook_2 even when mook_1 == mook_2 by identity", context2.branch_step == 1)
	context2.free()

	context.free()

func _test_campaign_context_debug_fight() -> void:
	# Cheat menu (2026-08-09, Camil: "tu aurais un sous menu 'cheat' de la
	# campagne, pour que je puisse tester tous les twists ?") — a THIRD case
	# alongside branch/organizer fights, distinct from both (2026-08-09 bug:
	# _update_campaign_label() assumed "not organizer" implied "branch is
	# set", crashing on CampaignContext.branch being null during a debug
	# fight — this test guards the CampaignContext side of that regression).
	var context_script := load("res://nodes/campaign_context.gd")
	var context = context_script.new()
	var campaign := CampaignData.new()
	var encounter := RivalEncounterData.new()
	encounter.is_mook = false

	context.start_debug_fight(campaign, encounter)
	_check("debug fight registers as a pending encounter", context.has_pending_encounter())
	_check("debug fight is neither a branch nor the organizer", context.branch == null and not context.is_organizer_fight)
	_check("current_encounter() returns the debug encounter", context.current_encounter() == encounter)

	context.clear()
	_check("clear() resets debug_encounter too", context.debug_encounter == null and not context.has_pending_encounter())
	context.free()

func _test_campaign_save_progress_tracking() -> void:
	# Title screen (2026-08-09) — "Nouvelle partie" only warns/wipes when
	# there's real progress to lose; "Continuer la partie" needs to know
	# which character to resume.
	var save_script := load("res://nodes/campaign_save.gd")
	var save = save_script.new()
	save._data = {} # start from a clean slate, independent of any real save on disk

	const TEST_CHARACTER := "_smoke_test_progress_character"

	_check("no progress on a fresh save", not save.has_any_progress())
	_check("character_with_progress() is empty with nothing saved", save.character_with_progress() == "")

	save.add_currency(TEST_CHARACTER, 50)
	_check("has_any_progress() becomes true once currency is earned", save.has_any_progress())
	_check("character_with_progress() finds the right character", save.character_with_progress() == TEST_CHARACTER)

	save.reset_all()
	_check("reset_all() wipes progress back to none", not save.has_any_progress())
	_check("reset_all() clears character_with_progress() too", save.character_with_progress() == "")

func _test_vif_campaign_authoring() -> void:
	# Sanity-checks the one fully-authored example campaign (content for the
	# other 7 characters is tracked separately, not an engineering gap).
	var campaign: CampaignData = load("res://data/campaigns/vif_campaign.tres")
	var vif: CharacterData = load("res://data/characters/vif.tres")

	_check("Vif campaign is authored for the right character", campaign.character == vif)
	_check("Vif campaign has at least required_branch_count mini-branches", campaign.mini_branches.size() >= campaign.required_branch_count)
	_check("required_branch_count is in the brainstorm's 3-4 range", campaign.required_branch_count >= 3 and campaign.required_branch_count <= 4)

	for b in campaign.mini_branches:
		var branch: MiniBranchData = b
		_check("branch '%s' has both mooks set" % branch.id, branch.mook_1 != null and branch.mook_2 != null)
		# 2026-08-08 bug: mook_1 and mook_2 were the same resource instance in
		# every branch, which made _update_campaign_label()'s identity check
		# always report "Sous-adversaire 1/2" and read to the player as a
		# stuck loop rather than real progress.
		_check("branch '%s' mook_1 and mook_2 are distinct resources" % branch.id, branch.mook_1 != branch.mook_2)
		_check("branch '%s' rival has a twist assigned" % branch.id, branch.rival.twist != null)
		_check("branch '%s' rival grants an unlock" % branch.id, branch.rival.unlock_reward != null)

	_check("organizer encounter is set", campaign.organizer_encounter != null)
	_check("organizer encounter has its signature twist", campaign.organizer_encounter.twist != null and campaign.organizer_encounter.twist.twist_type == "energy_orb_pickup")

func _test_gauges_reset_between_rounds() -> void:
	# 2026-08-08 bug report: "quand un round se termine, les compteurs
	# d'armes ne se remettent pas à 0" — reset_for_new_round() rebuilt HP
	# but never touched weapon_state, so a maxed gauge from round 1 carried
	# straight into round 2.
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	var ship := ShipNode.new()
	ship.weapon_state = WeaponSystemState.new([machine_gun])
	ship.weapon_state = ship.weapon_state.with_gauge_added(machine_gun.gauge_max) # simulate a maxed gauge at round end
	_check("gauge is maxed before the round reset (test setup sanity check)", ship.weapon_state.gauges[0] == machine_gun.gauge_max)

	ship.reset_for_new_round()
	_check("gauge is back to 0 after reset_for_new_round()", ship.weapon_state.gauges[0] == 0.0)
	_check("cooldown is also reset", ship.weapon_state.cooldown == 0.0)
	_check("the kit itself is unchanged (still the same weapon)", ship.weapon_state.kit.size() == 1 and ship.weapon_state.kit[0] == machine_gun)

	ship.queue_free()

func _test_weapon_heat_gauge() -> void:
	# 2026-08-08 playtest: "Mitraillette, c'est trop fort. Il faudrait un
	# cooldown de 1s tous les... 6 tirs ?" — then 2026-08-09, after the
	# first (hard burst-limit) version: "je tire 4 balles, j'attends 3
	# secondes, et je ne peux tirer que 2 balles => frustrant". Redesigned
	# as a continuous heat gauge instead: any pause drains it a little,
	# rather than a flat shot counter that only ever resets after a full
	# lockout.
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	_check("machine_gun has a heat limit configured", machine_gun.heat_max > 0.0)
	_check("machine_gun's heat drains at 1 full cooldown's worth per second", is_equal_approx(machine_gun.heat_cooldown_rate, machine_gun.heat_max))

	var weapon := WeaponData.new()
	weapon.fire_rate = 10.0
	weapon.gauge_max = 1000.0
	weapon.gauge_cost_per_shot = 1.0
	weapon.heat_max = 6.0
	weapon.heat_per_shot = 1.0
	weapon.heat_cooldown_rate = 6.0 # full cool from max in 1s
	var state := WeaponSystemState.new([weapon])
	state = state.with_gauge_added(1000.0)

	for i in 6:
		var result := state.fired()
		_check("shot %d fires" % (i + 1), result.fired)
		state = result.state
		state = state.with_cooldown_ticked(state.cooldown) # fast-forward the normal per-shot cooldown; heat is the only remaining gate
		state = state.with_heat_ticked(0.1, true) # is_firing=true — heat must NOT drain mid-burst

	_check("after 6 shots the gauge is fully heated", is_equal_approx(state.heats[0], 6.0))
	var blocked_result := state.fired()
	_check("firing while fully heated is blocked", not blocked_result.fired)

	# 2026-08-09 regression: a SHORT pause (well under the full 1s cooldown)
	# must still measurably help, not be wasted like the old hard-lockout
	# counter — the exact "4 shots, wait 3s, still only 2 left" complaint.
	state = state.with_heat_ticked(0.5, false) # released fire for half a second
	_check("a partial pause drains heat proportionally, not all-or-nothing", is_equal_approx(state.heats[0], 3.0))
	var resumed_result := state.fired()
	_check("firing resumes as soon as heat drops below max, not only after a full cooldown", resumed_result.fired)

	# Heat must never drain while the trigger is still held.
	var still_firing_state := WeaponSystemState.new([weapon])
	still_firing_state = still_firing_state.with_gauge_added(1000.0)
	still_firing_state = still_firing_state.fired().state
	still_firing_state = still_firing_state.with_heat_ticked(1.0, true)
	_check("heat does not drain while is_firing is true", is_equal_approx(still_firing_state.heats[0], 1.0))

func _test_mitrailleur_double_fire_rule() -> void:
	# 2026-08-09 — Mitrailleur's charged fire, first tried as a heat-immunity
	# buff (Camil: "pas bien"), replaced with: "les 10 missiles suivants
	# seront doubles (paralleles, separes de 10px verticalement). Un petit
	# icone se met a cote de la barre pour indiquer qu'on est en mode double
	# tir."
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	_check("machine_gun has a charged fire configured", machine_gun.charge_fire_duration > 0.0)
	_check("machine_gun's charge actually slows movement (the vortex.tres bug can never recur silently)", machine_gun.charge_fire_slow_multiplier < 1.0 and machine_gun.charge_fire_slow_multiplier > 0.0)
	_check("machine_gun's charged fire grants 10 doubled shots", machine_gun.charged_double_fire_shots == 10)
	_check("machine_gun's doubled shots are separated 10px vertically", is_equal_approx(machine_gun.charged_double_fire_offset, 10.0))

	# ShipNode.grant_double_fire() — armed by _on_charged_weapon_fired(),
	# consumed one at a time by _on_weapon_fired().
	var ship := ShipNode.new()
	ship.grant_double_fire(machine_gun.charged_double_fire_shots)
	_check("grant_double_fire() arms the counter", ship._double_fire_shots_remaining == machine_gun.charged_double_fire_shots)
	ship.queue_free()

func _test_dash_lift_rule() -> void:
	# 2026-08-09 (Camil): "vif est pas interessant... chaque perso devrait
	# avoir une regle bien a lui. un + et un -. Proposition pour vif: il ne
	# peut pas charger pour faire des lift. en revanche, le bouton lift lui
	# permet de faire un petit dash... s'il tape en dashant, ca fait un
	# leger lift."
	#
	# 2026-08-13: reverted for Vif specifically (Camil: "il faudrait que la
	# touche de lift redevienne une touche de lift, comme les autres") —
	# see _test_vortex_weapon()/vif.tres for his rework. The dash_lift
	# MECHANISM itself is untouched in ShipNode (still a valid general
	# special_rule option, just unused by anyone right now), so it's still
	# tested here — decoupled from Vif's specific assignment, via a
	# synthetic CharacterData instead of loading vif.tres.
	var dash_character := CharacterData.new()
	dash_character.special_rule = "dash_lift"

	var ship := ShipNode.new()
	ship.character = dash_character
	_check("get_lift_charge() reads 0% for a dash character with no dash active (the MINUS: no charging at all)", ship.get_lift_charge() == 0.0)

	ship._dash_timer = 0.1
	_check("get_lift_charge() reads a fixed 'leger lift' while a dash is active (the PLUS)", ship.get_lift_charge() == ShipNode.DASH_LIFT_CHARGE)

	ship._dash_timer = 0.0
	_check("get_lift_charge() drops back to 0% once the dash window ends", ship.get_lift_charge() == 0.0)

	# A normal (non-dash) character is completely untouched by this rewrite.
	var lourd: CharacterData = load("res://data/characters/lourd.tres")
	var lourd_ship := ShipNode.new()
	lourd_ship.character = lourd
	lourd_ship._lift_charge_timer = ShipNode.LIFT_CHARGE_CAP # full charge
	_check("a normal character still uses the hold-to-charge tiers unaffected", lourd_ship.get_lift_charge() == 1.0)

	ship.queue_free()
	lourd_ship.queue_free()

func _test_lift_charge_rework() -> void:
	# 2026-08-13 (Camil, after the dash_lift revert put Vif back on the
	# shared lift): "le lift, pas assez interessant. J'abaisserais la
	# charge du lift max a 2 secondes. ensuite, j'augmenterais l'effet du
	# lift de 100%. Enfin, pendant la charge, il faut pouvoir se deplacer
	# un peu, 25% de la vitesse normale."
	_check("LIFT_CHARGE_CAP raised to 2 seconds (was 1.5)", is_equal_approx(ShipNode.LIFT_CHARGE_CAP, 2.0))
	_check("LIFT_CHARGE_MOVE_MULTIPLIER allows 25% movement while charging (used to be a full freeze)", is_equal_approx(ShipNode.LIFT_CHARGE_MOVE_MULTIPLIER, 0.25))
	# 2026-08-13: doubled to 3.0 first, then walked back to 2.0 after
	# Camil hit an actual reversal bug ("j'ai reussi a renvoyer une balle
	# dans mon camp, ca ne doit pas etre possible !") — still above the
	# original 1.5, just not the full double anymore.
	_check("the lift's spin effect on the ball was strengthened but walked back after a reversal bug", BallState.SPIN_STRENGTH > 1.5 and is_equal_approx(BallState.SPIN_STRENGTH, 2.0))

	# Regression: the old cap (1.5s) must NOT still read as full charge now
	# that the tier threshold tracks LIFT_CHARGE_CAP instead of a stale
	# hardcoded 1.5 literal.
	var ship := ShipNode.new()
	ship.character = load("res://data/characters/lourd.tres")
	ship._lift_charge_timer = 1.5
	_check("1.5s of charge is only the 66% tier now that the cap moved to 2s", is_equal_approx(ship.get_lift_charge(), 0.66))
	ship._lift_charge_timer = 2.0
	_check("2.0s of charge reaches the full 100% tier", is_equal_approx(ship.get_lift_charge(), 1.0))
	ship.queue_free()

func _test_vif_reverted_to_shared_lift() -> void:
	# 2026-08-13 (Camil: "il faudrait que la touche de lift redevienne une
	# touche de lift, comme les autres") — Vif's special_rule goes back to
	# "none", so he uses the shared hold-to-charge lift like everyone
	# without a special_rule (Lourd, Contrôleur, etc.), same as before the
	# 2026-08-09 dash_lift experiment.
	var vif: CharacterData = load("res://data/characters/vif.tres")
	_check("Vif's special_rule reverted to none (dash_lift dropped)", vif.special_rule == "none")
	_check("Vif's kit is still just his Tourbillon", vif.kit.size() == 1 and vif.kit[0].id == "vortex")

	var ship := ShipNode.new()
	ship.character = vif
	ship._lift_charge_timer = ShipNode.LIFT_CHARGE_CAP
	_check("Vif now uses the shared hold-to-charge lift tiers, not the dash rewrite", ship.get_lift_charge() == 1.0)
	ship.queue_free()

func _test_every_charge_capable_weapon_actually_slows() -> void:
	# 2026-08-09 — a general invariant, added after vortex.tres shipped with
	# charge_fire_duration set but no charge_fire_slow_multiplier (silently
	# defaulting to 1.0 = no slow at all), which read as an intermittent
	# "sometimes not slowed" bug through several rounds of ship_node.gd
	# fixes that were actually solving a different problem. Scans every
	# weapon under data/weapons/ so this can never silently regress again.
	var dir := DirAccess.open("res://data/weapons")
	var all_ok := true
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var weapon: WeaponData = load("res://data/weapons/%s" % f)
			if weapon.charge_fire_duration > 0.0 and weapon.charge_fire_slow_multiplier >= 1.0:
				all_ok = false
				print("FAIL: %s has charge_fire_duration but charge_fire_slow_multiplier is %s (no slow)" % [f, weapon.charge_fire_slow_multiplier])
		f = dir.get_next()
	dir.list_dir_end()
	_check("every charge-capable weapon actually slows movement while charging", all_ok)

func _test_weapon_exclusivity() -> void:
	# 2026-08-09 (Camil): "je pense que la mitraillette devrait etre
	# reservee a mitrailleur. Pour eviter de se prendre la tete avec des
	# changements d'arme, chaque joueur a sa propre arme." Every roster
	# character now carries exactly one weapon, and no two characters share
	# the same one.
	var character_ids := ["lourd", "controleur", "mitrailleur", "vif", "zoneur", "perturbateur", "missiles", "mini"]
	var seen_weapon_ids := {}
	var all_mono_weapon := true
	var all_unique := true
	for character_id in character_ids:
		var character: CharacterData = load("res://data/characters/%s.tres" % character_id)
		if character.kit.size() != 1:
			all_mono_weapon = false
		var weapon: WeaponData = character.kit[0]
		if seen_weapon_ids.has(weapon.id):
			all_unique = false
		seen_weapon_ids[weapon.id] = character_id
	_check("every roster character carries exactly one weapon", all_mono_weapon)
	_check("no two characters share the same weapon", all_unique)

	# 2026-08-09 (Camil): "seul mitrailleur tire plusieurs fois d'affilee
	# quand on laisse appuye... pour les autres, il faut appuyer plusieurs
	# fois pour tirer plusieurs fois."
	var mitrailleur: CharacterData = load("res://data/characters/mitrailleur.tres")
	_check("only Mitrailleur is full-auto", mitrailleur.full_auto)
	var vif: CharacterData = load("res://data/characters/vif.tres")
	_check("everyone else defaults to semi-auto (e.g. Vif)", not vif.full_auto)

func _test_vortex_weapon() -> void:
	# 2026-08-09 (Camil): Vif's new signature weapon — "un petit tourbillon
	# qui tourne sur lui meme en avancant et qui va tres vite. tir charge,
	# trois tourbillons qui vont tout droit (toujours en tournant sur eux
	# meme)." Redesigned after Camil's drawing: "je veux qu'il fasse des
	# cercles" — small forward-advancing loops. Then: "vu la vitesse, pour
	# le tourbillon, pas d'anim : garde uniquement wind1" — the wind1-3
	# cycle was dropped, too fast to read once the loop motion was tuned
	# up; the loop itself carried the "spinning" read.
	#
	# 2026-08-13 REWORK (Camil: "je n'aime pas [l'arme de vif]... que son
	# tir ne fasse plus des cercles, mais parte tout droit avec une
	# trajectoire sinusoidale") — is_looping (closed circular orbit)
	# replaced by is_sine (straight-line drift with a lateral wave), see
	# ProjectileNode.is_sine.
	var vortex: WeaponData = load("res://data/weapons/vortex.tres")
	_check("Tourbillon travels faster than the shared default projectile speed", vortex.projectile_speed > 620.0)
	_check("Tourbillon rides a sine wave instead of flying straight or looping", vortex.is_sine and vortex.sine_amplitude > 0.0 and vortex.sine_angular_speed > 0.0)
	_check("Tourbillon no longer loops (2026-08-13 rework)", not vortex.is_looping)
	_check("Tourbillon does not also spin the node (the wave motion already conveys spin)", vortex.projectile_spin_speed == 0.0)
	_check("Tourbillon has a charged fire configured", vortex.charge_fire_duration > 0.0)
	_check("Tourbillon's charge duration is 3s (2026-08-09 playtest: 'augmenter le temps de charge : 3 secondes')", is_equal_approx(vortex.charge_fire_duration, 3.0))
	# 2026-08-09 bug (the REAL root cause of the recurring "ralentissement"
	# reports for Vif): charge_fire_slow_multiplier was never set on
	# vortex.tres at all, silently defaulting to 1.0 (no slowdown) — every
	# ship_node.gd fix attempt was solving a different, hypothetical problem.
	_check("Tourbillon's charge actually slows movement (was silently defaulting to 1.0 = no slow)", vortex.charge_fire_slow_multiplier < 1.0 and vortex.charge_fire_slow_multiplier > 0.0)
	_check("Tourbillon's cooldown was increased 1.5x (2026-08-09 playtest: 'un peu court')", vortex.fire_rate < 4.0 / 1.4) # fire_rate=4.0/1.5 -> cooldown*1.5; loose upper bound so exact rounding doesn't matter
	# 2026-08-13: "j'augmenterais bien aussi le cooldown de l'arme de vif,
	# +40% par rapport a l'actuel" — actual before/after cooldowns compared
	# directly (1/fire_rate), not another fire_rate-space approximation.
	var vortex_cooldown_before := 1.0 / 2.667 # the value going into this change
	var vortex_cooldown_after := 1.0 / vortex.fire_rate
	_check("Tourbillon's cooldown was increased another 40% on top of that", is_equal_approx(vortex_cooldown_after, vortex_cooldown_before * 1.4))
	_check("Tourbillon's charged fire launches 3 vortices", vortex.charged_projectile_count == 3)
	_check("Tourbillon's charged vortices still go straight (no burst spread)", vortex.charged_burst_spread_deg == 0.0)
	_check("Tourbillon gives Vif a recoil speed boost on fire, trimmed twice after playtest (100% -> 70% -> 60%, 'toujours trop fort')", is_equal_approx(vortex.fire_recoil_speed_boost, 0.6) and is_equal_approx(vortex.fire_recoil_boost_decay_time, 0.5))

	var projectile := ProjectileNode.new()
	projectile.velocity = Vector2(vortex.projectile_speed, 0.0)
	projectile.is_sine = true
	projectile.sine_amplitude = vortex.sine_amplitude
	projectile.sine_angular_speed = vortex.sine_angular_speed
	projectile._ready() # captures _drift_velocity — never called automatically by .new() under this harness
	var start_position := projectile.position
	var off_the_straight_line := false
	var net_forward_progress := false
	var crossed_back_toward_center := false # true sine oscillates both sides, unlike a one-way curve
	var max_deviation := 0.0
	for i in 90: # ~1.5s at a 60fps-equivalent step — long enough to complete a full wave
		projectile._physics_process(1.0 / 60.0)
		var dy := projectile.position.y - start_position.y
		if absf(dy) > 2.0:
			off_the_straight_line = true
		max_deviation = maxf(max_deviation, absf(dy))
		if max_deviation > 5.0 and absf(dy) < max_deviation * 0.3:
			crossed_back_toward_center = true
		if projectile.position.x - start_position.x > 20.0:
			net_forward_progress = true
	_check("a sine-wave projectile deviates off the straight line", off_the_straight_line)
	_check("a sine-wave projectile swings back toward the center line (a real oscillation, not a one-way curve)", crossed_back_toward_center)
	_check("a sine-wave projectile still makes real net forward progress (drifts, doesn't just wave in place)", net_forward_progress)

	# 2026-08-09 (Camil: "attention quand il tourne, sa zone de contact
	# tourne avec lui !") — same principle carried into the sine rework:
	# the hit check uses the same `position` the wave actually moves
	# through, so a target placed only in the wave's swept path — off the
	# straight drift line — must still register a hit.
	var off_line_target := ShipNode.new()
	# Placed where the wave actually PEAKS (quarter-period forward, full
	# amplitude sideways) rather than an arbitrary small offset — a sine's
	# lateral displacement is ~0 near t=0 and only reaches full amplitude a
	# quarter-cycle in, by which point the projectile (at projectile_speed)
	# has already traveled real forward distance too.
	var quarter_period_time := 90.0 / vortex.sine_angular_speed # seconds to reach max lateral offset (90deg = quarter cycle)
	var forward_offset_at_peak := vortex.projectile_speed * quarter_period_time
	# Godot's Vector2.orthogonal() returns (y, -x) — for a rightward drift
	# (1,0) that's (0,-1), so the FIRST peak (t=quarter_period, sin=1) lands
	# at NEGATIVE y (up), not positive. Confirmed empirically (a +amplitude
	# placement missed entirely) rather than assumed.
	off_line_target.position = start_position + Vector2(forward_offset_at_peak, -vortex.sine_amplitude) # well off the straight (dy=0) line, but within the wave's sweep
	off_line_target.half_extents = Vector2(14, 28)
	off_line_target.state = ShipState.new(off_line_target.position, 0, off_line_target.half_extents) # apply_damage() needs this — normally built in _ready(), never called by this harness
	var probe := ProjectileNode.new()
	probe.velocity = Vector2(vortex.projectile_speed, 0.0)
	probe.is_sine = true
	probe.sine_amplitude = vortex.sine_amplitude
	probe.sine_angular_speed = vortex.sine_angular_speed
	probe.damage = 2
	probe.target = off_line_target
	probe.position = start_position
	probe._ready()
	var hit_off_line_target := false
	for i in 90: # long enough to sweep through a full wave
		probe._physics_process(1.0 / 60.0)
		if not is_instance_valid(probe) or probe.is_queued_for_deletion():
			hit_off_line_target = true
			break
	_check("the sine wave's hit detection actually follows the curved path (an off-line target still gets hit)", hit_off_line_target)
	off_line_target.queue_free()
	if is_instance_valid(probe) and not probe.is_queued_for_deletion():
		probe.queue_free()
	projectile.queue_free()

func _test_projectile_tunneling_fix() -> void:
	# 2026-08-09 bug report: "il y a plein de cas ou les tourbillons de Vif
	# ne touchent pas. J'ai l'impression que l'animation va tellement vite
	# qu'on saute des frames" — a point-only check on the post-move position
	# tunnels through a target rect narrower than one frame's travel. Proven
	# here with a plain fast straight-line shot (no looping needed to
	# reproduce it): a single large step that lands cleanly on the FAR side
	# of the target, having started cleanly on the near side, must still
	# register as a hit via the swept segment check.
	var target := ShipNode.new()
	target.position = Vector2(500, 300)
	target.half_extents = Vector2(14, 28) # ~28px-wide hitbox
	target.state = ShipState.new(target.position, 0, target.half_extents)

	# Target rect spans x in [486, 514] (position.x=500, half_extents.x=14).
	# Start clearly before it, end clearly past it, in a single physics step
	# — neither endpoint is inside the rect, only the sweep between them is.
	var projectile := ProjectileNode.new()
	projectile.position = Vector2(470, 300)
	projectile.velocity = Vector2(3600.0, 0.0) # a single 1/60s step covers 60px, clearing the whole 28px-wide hitbox
	projectile.target = target
	projectile.damage = 5
	projectile._physics_process(1.0 / 60.0)
	_check("a fast shot that would land past the target in one step still registers a hit (no tunneling)", target.state.hp < ShipState.START_HP)

	target.queue_free()
	if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
		projectile.queue_free()

	# The swept check itself, directly: a segment that starts before and
	# ends after a rect, passing straight through, must be detected even
	# though NEITHER endpoint is inside the rect.
	var probe2 := ProjectileNode.new()
	var rect := Rect2(100, 100, 20, 20) # spans x in [100, 120]
	_check("segment sweep catches a pass-through even when both endpoints are outside the rect", probe2._segment_crosses_rect(Vector2(90, 110), Vector2(130, 110), rect))
	_check("segment sweep correctly reports no crossing for a segment that misses the rect entirely", not probe2._segment_crosses_rect(Vector2(90, 200), Vector2(130, 200), rect))
	probe2.queue_free()

## 2026-08-11, Camil (after seeing the hitbox overlay on a charged giant
## boomerang): "avec la hit box on voit bien que celle des projectiles ne
## font pas la taille du sprite" — hit resolution used to test the
## projectile's exact center POINT, ignoring how big its sprite actually
## was. hit_half_size (computed in _ready() from texture size * visual_
## scale) now inflates the swept hit-test, confirmed here on the generic
## case ("il faut le faire sur tous les projectiles bien sur"), not just
## the boomerang.
func _test_hit_half_size_matches_sprite() -> void:
	var texture := PlaceholderTexture2D.new()
	texture.size = Vector2(20, 20) # matches boomerang.png's actual size
	var normal_shot := ProjectileNode.new()
	normal_shot.textures = [texture]
	normal_shot.visual_scale = 1.4 # the boomerang's base visual_scale set in _spawn_projectile()
	normal_shot._ready()
	_check("a normal-sized shot's hit_half_size matches its texture * visual_scale", normal_shot.hit_half_size.is_equal_approx(Vector2(14.0, 14.0)))

	var giant_shot := ProjectileNode.new()
	giant_shot.textures = [texture]
	giant_shot.visual_scale = 1.4 * 5.0 # Perturbateur's charged giant boomerang (charged_visual_scale_multiplier = 5.0)
	giant_shot._ready()
	_check("a 5x charged giant shot's hit_half_size is proportionally 5x bigger", giant_shot.hit_half_size.is_equal_approx(Vector2(70.0, 70.0)))

	var no_art_shot := ProjectileNode.new()
	no_art_shot.textures = []
	no_art_shot._ready()
	_check("a shot with no art yet keeps the small fallback hit_half_size", no_art_shot.hit_half_size.is_equal_approx(Vector2(4.0, 4.0)))

	# End to end: a target placed well outside the OLD (tiny, point-like) hit
	# test, but comfortably inside the giant shot's actual visual footprint,
	# must now register a hit — this is the whole point of the fix.
	var target := ShipNode.new()
	target.position = Vector2(500, 300)
	target.half_extents = Vector2(14, 28)
	target.state = ShipState.new(target.position, 0, target.half_extents)
	var far_shot := ProjectileNode.new()
	far_shot.textures = [texture]
	far_shot.visual_scale = 1.4 * 5.0
	far_shot._ready()
	far_shot.position = Vector2(430, 300) # 70px left of the target's near edge (486) — outside a bare point-test, well inside a 70px-radius hit_half_size
	far_shot.target = target
	far_shot.damage = 5
	far_shot._physics_process(1.0 / 60.0)
	_check("a giant shot registers a hit from a distance a point-sized shot never would have", target.state.hp < ShipState.START_HP)
	target.queue_free()
	if is_instance_valid(far_shot) and not far_shot.is_queued_for_deletion():
		far_shot.queue_free()
	normal_shot.queue_free()
	giant_shot.queue_free()
	no_art_shot.queue_free()

func _test_charged_fire_burst() -> void:
	# 2026-08-09 — WeaponData.charged_* fields feeding
	# MatchArenaNode._on_charged_weapon_fired()/_spawn_projectile(): the
	# framework is generic, proven here with Lourd's bazooka (2 faster
	# shells) rather than re-deriving ship_node.gd's Input-driven charge
	# state machine, which can't be simulated headless (same limitation as
	# every other keypress-driven behavior in this suite).
	var bazooka: WeaponData = load("res://data/weapons/bazooka.tres")
	_check("bazooka has a charged fire configured (Lourd's 3s charge)", is_equal_approx(bazooka.charge_fire_duration, 3.0))
	_check("bazooka's charge slows movement by 70%", is_equal_approx(bazooka.charge_fire_slow_multiplier, 0.3))
	_check("bazooka's charged release fires 2 shells", bazooka.charged_projectile_count == 2)
	_check("bazooka's charged shells are faster than normal", bazooka.charged_speed_multiplier > 1.0)

	# 2026-08-09 redesign after playtesting the first version (Camil: "je
	# laisse appuye, ca tire normalement. si au bout d'une seconde je suis
	# toujours en appui, la charge commence") — normal fire for the first
	# NORMAL_FIRE_GRACE seconds of a hold, THEN it starts charging.
	_check("NORMAL_FIRE_GRACE is about 1 second, per Camil's spec", is_equal_approx(ShipNode.NORMAL_FIRE_GRACE, 1.0))

	# 2026-08-09 (Camil): "quand la charge est fini, tu peux faire clignoter
	# rapidement le joueur pour qu'on sache que c'est bon", then after
	# seeing it: "pas mal le clignotement, tu peux le faire beaucoup plus
	# rapide" (0.5s -> 0.15s). The blink ITSELF (visual.modulate toggling in
	# _physics_process()) can't be simulated headless — it's gated behind
	# live fire_held/Input state, same limitation as every other keypress-
	# driven behavior in this suite — but the formula
	# (fmod(_fire_held_duration, PERIOD) < PERIOD/2.0) is pure math, checked
	# here directly with period-relative offsets (not a fixed elapsed time
	# like 3.0s, which risked landing on a float-precision edge case against
	# an arbitrary period value).
	_check("CHARGE_READY_BLINK_PERIOD was made much faster (0.5s -> 0.15s)", is_equal_approx(ShipNode.CHARGE_READY_BLINK_PERIOD, 0.15))
	# Sampled at the middle of each half (0.25/0.75 of a period), not on the
	# exact half/full-period boundary — a boundary sample is one float
	# rounding error away from landing on the wrong side of "< period/2.0".
	var period := ShipNode.CHARGE_READY_BLINK_PERIOD
	_check("the blink formula is ON in the first half of a period", fmod(period * 0.25, period) < period / 2.0)
	_check("the blink formula toggles OFF in the second half", not (fmod(period * 0.75, period) < period / 2.0))
	_check("the blink formula toggles back ON a full period later", fmod(period + period * 0.25, period) < period / 2.0)

func _test_heavy_push_rule() -> void:
	# 2026-08-09 (Camil): "Lourd bonne idee le lift a fond, il faudrait donc
	# que ca 'pousse' la balle et que cette derniere pousse le joueur
	# adverse." A fully-charged (100%) lift return arms the ball; the NEXT
	# ship it reaches gets shoved back.
	var lourd: CharacterData = load("res://data/characters/lourd.tres")
	_check("Lourd's special_rule is heavy_push", lourd.special_rule == "heavy_push")

	# Pure ShipState.knocked_back() — offset applied and clamped like normal movement.
	var bounds := Rect2(0, 0, 1280, 720)
	var state := ShipState.new(Vector2(200, 300), 0, Vector2(14, 28))
	var pushed_state := state.knocked_back(Vector2(40.0, 0.0), bounds, 640.0)
	_check("knocked_back() moves the ship by the offset", is_equal_approx(pushed_state.position.x, 240.0))
	var pushed_into_wall := state.knocked_back(Vector2(-1000.0, 0.0), bounds, 640.0)
	_check("knocked_back() is clamped, can't push a ship out of bounds", pushed_into_wall.position.x >= bounds.position.x)

	# End-to-end: arm on a 100%-charge return, consume on the next ship contact.
	var pusher := ShipNode.new()
	pusher.side = 0
	pusher.character = lourd
	pusher.position = Vector2(200, 300)
	pusher.state = ShipState.new(pusher.position, pusher.side, pusher.half_extents)
	pusher.weapon_state = WeaponSystemState.new(lourd.kit) # normally built in _ready(), which this harness never calls
	pusher._lift_charge_timer = ShipNode.LIFT_CHARGE_CAP # forces get_lift_charge() == 1.0
	root.add_child(pusher)

	var opponent := ShipNode.new()
	opponent.side = 1
	opponent.position = Vector2(1000, 300)
	opponent.arena_bounds = Rect2(0, 0, 1280, 720)
	opponent.frontier_x = 640.0
	opponent.state = ShipState.new(opponent.position, opponent.side, opponent.half_extents)
	opponent.weapon_state = WeaponSystemState.new([load("res://data/weapons/machine_gun.tres")])
	root.add_child(opponent)

	var ball := BallNode.new()
	ball.arena_bounds = Rect2(0, 0, 1280, 720)
	ball.frontier_x = 640.0
	ball.ships = [pusher, opponent]
	ball.state = BallState.new(pusher.position, Vector2(-1.0, 0.0)) # overlapping pusher, heading further left (a "return" reverses this)
	root.add_child(ball)

	ball._resolve_ships()
	_check("a 100%-charge heavy_push return arms the ball", ball._push_pending)

	# Move the (now rightward-traveling, post-return) ball onto the opponent and resolve again.
	ball._return_cooldown = 0.0
	ball.state = BallState.new(opponent.position, Vector2(500.0, 0.0))
	var opponent_x_before := opponent.position.x
	ball._resolve_ships()
	_check("the armed push knocks the opponent back on the next contact", opponent.position.x > opponent_x_before)
	_check("the push is consumed (single-use), not reusable", not ball._push_pending)

	pusher.queue_free()
	opponent.queue_free()
	ball.queue_free()

## 2026-08-11 QA pass (Camil: "j'aimerais que tu poses des tests un peu
## partout") — MatchState (best-of-3 round win condition) had ZERO test
## coverage anywhere in the suite despite being pure simulation logic
## (Regle absolue n1), the exact kind of class this project's headless
## testing convention exists for.
func _test_match_state() -> void:
	var fresh := MatchState.new()
	_check("a fresh MatchState starts 0-0, not over", fresh.rounds_won == [0, 0] and not fresh.match_over and fresh.winner_side == -1)

	var after_one := fresh.round_won_by(0)
	_check("winning one round increments that side's count", after_one.rounds_won == [1, 0])
	_check("one round win alone doesn't end the match (best of 3 needs 2)", not after_one.match_over and after_one.winner_side == -1)
	_check("round_won_by() returns a NEW state, doesn't mutate the original (pure/immutable, matches every other *State class)", fresh.rounds_won == [0, 0])

	var after_two := after_one.round_won_by(0)
	_check("winning a second round for the same side ends the match", after_two.match_over and after_two.winner_side == 0)
	_check("the losing side's count stays untouched", after_two.rounds_won == [2, 0])

	var side1_wins := MatchState.new().round_won_by(1).round_won_by(1)
	_check("side 1 can win the match too (not hardcoded to side 0)", side1_wins.match_over and side1_wins.winner_side == 1)

	var split := MatchState.new(1, 0).round_won_by(1)
	_check("a split 1-1 score is not over yet", not split.match_over and split.rounds_won == [1, 1])

## Purely cosmetic (a floating "+N" gauge-fill popup), but still simple pure
## motion/fade math worth locking in — same "poser des tests un peu partout"
## pass, even for the low-risk stuff.
func _test_floating_text_node() -> void:
	var popup := FloatingTextNode.new()
	popup.text = "+15"
	popup.velocity = Vector2(0.0, -42.0)
	popup.lifetime = 0.9
	var start_pos := popup.position
	popup._physics_process(0.5)
	_check("a floating text popup rises according to its velocity", popup.position.y < start_pos.y)
	_check("a floating text popup isn't queued for deletion before its lifetime elapses", not popup.is_queued_for_deletion())
	popup._physics_process(0.5) # total elapsed now 1.0s > lifetime 0.9s
	_check("a floating text popup queues for deletion once its lifetime elapses", popup.is_queued_for_deletion())

func _test_ultra_meter() -> void:
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	var state := WeaponSystemState.new([machine_gun])
	_check("a fresh WeaponSystemState starts with 0 ultra pips", state.ultra_pips == 0)
	_check("ultra isn't ready with an empty meter", not state.ultra_ready())

	for i in WeaponSystemState.ULTRA_METER_MAX - 1:
		state = state.with_ultra_pip_added()
	_check("one pip short of the max still isn't ready", not state.ultra_ready() and state.ultra_pips == WeaponSystemState.ULTRA_METER_MAX - 1)

	state = state.with_ultra_pip_added()
	_check("hitting ULTRA_METER_MAX makes the ultra ready", state.ultra_ready() and state.ultra_pips == WeaponSystemState.ULTRA_METER_MAX)

	var overfilled := state.with_ultra_pip_added()
	_check("adding a pip past the max is clamped, not uncapped", overfilled.ultra_pips == WeaponSystemState.ULTRA_METER_MAX)

	var consumed := state.with_ultra_consumed()
	_check("triggering the ultra spends the whole meter", consumed.ultra_pips == 0 and not consumed.ultra_ready())
	_check("with_ultra_pip_added() returns a NEW instance, doesn't mutate the original (matches every other *State class)", state.ultra_pips == WeaponSystemState.ULTRA_METER_MAX)

	var fresh := WeaponSystemState.new([machine_gun])
	var filled_then_fired := fresh.with_gauge_added(machine_gun.gauge_max)
	for i in WeaponSystemState.ULTRA_METER_MAX:
		filled_then_fired = filled_then_fired.with_ultra_pip_added()
	var fire_result := filled_then_fired.fired()
	_check("firing a normal shot doesn't touch the ultra meter (independent resources)", fire_result.state.ultra_pips == WeaponSystemState.ULTRA_METER_MAX)
