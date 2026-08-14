extends Node2D

## One-off scene-boot verification for Mitrailleur's Ultra, "Mitrailleuses
## Satellites" (2026-08-13 Epic 4 party-mode memlog: "double full-auto
## temporaire"). Split into its own file rather than growing
## ultra_abilities_check.gd further — that file's shared wait-loop
## already takes a while real-time with 3 characters in it; a dedicated
## file per additional Ultra keeps each test run focused. Confirms, via
## the real trigger path: the guaranteed floor lands the instant the
## intro finishes, and exactly 2 TurretNodes spawn flanking the shooter,
## carrying the right weapon/target/side. Run with:
##   Godot --headless --path godot_project res://tests/ultra_mitrailleuses_satellites_check.tscn --quit-after 2200

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	arena.ship_1.set_character(load("res://data/characters/mitrailleur.tres"))
	while not arena.ship_1.weapon_state.ultra_ready():
		arena.ship_1.add_ultra_pip()
	arena._unfreeze_round()

	var hp_before: float = arena.ship_2.state.hp
	var down := InputEventKey.new()
	down.physical_keycode = KEY_E
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Catch the exact tick the intro finishes and ships unfreeze — see
	# ultra_abilities_check.gd for why this beats a fixed "wait N then
	# check" (headless frames run far faster than realtime, and a
	# too-long wait risks other side effects piling up before the check).
	var was_active := arena.ship_1.active
	var hp_at_unfreeze := -1.0
	for i in 1600:
		await get_tree().physics_frame
		if not was_active and arena.ship_1.active:
			hp_at_unfreeze = arena.ship_2.state.hp
			break
		was_active = arena.ship_1.active

	var floor_ok: bool = hp_at_unfreeze >= 0.0 and is_equal_approx(hp_before - hp_at_unfreeze, MatchArenaNode.MITRAILLEUSES_SATELLITES_GUARANTEED_DAMAGE)
	print(("PASS: guaranteed floor lands the instant the intro finishes (%.0f -> %.0f)" % [hp_before, hp_at_unfreeze]) if floor_ok else ("FAIL: floor was wrong at unfreeze (%.0f -> %.0f, expected -%.0f)" % [hp_before, hp_at_unfreeze, MatchArenaNode.MITRAILLEUSES_SATELLITES_GUARANTEED_DAMAGE]))

	var turrets: Array = []
	for child in arena.get_children():
		if child is TurretNode:
			turrets.append(child)
	var count_ok: bool = turrets.size() == 2
	print(("PASS: exactly 2 satellite turrets spawned" % []) if count_ok else ("FAIL: %d turrets spawned, expected 2" % turrets.size()))

	var config_ok := true
	for turret in turrets:
		if turret.weapon != MatchArenaNode.ULTRA_MITRAILLEUSES_SATELLITES:
			config_ok = false
		if turret.target != arena.ship_2:
			config_ok = false
		if turret.owner_side != arena.ship_1.side:
			config_ok = false
		var offset_y: float = turret.position.y - arena.ship_1.position.y
		if not is_equal_approx(absf(offset_y), MatchArenaNode.MITRAILLEUSES_SATELLITES_OFFSET_Y):
			config_ok = false
	print("PASS: both turrets carry the right weapon/target/side, flanking the shooter" if config_ok else "FAIL: a turret's config was wrong")

	var all_ok := floor_ok and count_ok and config_ok
	get_tree().quit(0 if all_ok else 1)
