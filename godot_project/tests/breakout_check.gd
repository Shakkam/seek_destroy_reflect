extends Node2D

## Scene-boot check for the REBUILT Breakout mini-jeu (2026-08-18, after
## Camil's feedback: "il faudrait vraiment garder le pattern actuel...
## la tu m'as juste fait un breakout qui est en dehors du systeme de jeu").
## This version reuses real ShipNode/BallNode/TurretNode wholesale, so
## unlike the first pass's pure-logic tests, this needs the real scene
## tree + autoloads (CampaignContext/CampaignSave) — same reasoning
## reward_reveal_check.gd documents for its own rival-win checks.
## IMPORTANT: touches the REAL save file via CampaignSave — reset_all()
## before AND after. Run with:
##   Godot --headless --path . res://tests/breakout_check.tscn --quit-after 4000 --fixed-fps 60

func _ready() -> void:
	CampaignSave.reset_all()

	var vif_campaign: CampaignData = load("res://data/campaigns/vif_campaign.tres")
	var branch: MiniBranchData = vif_campaign.mini_branches[0]
	CampaignContext.start_branch(vif_campaign, branch) # branch_step 0 -> mook_1

	var breakout_scene := load("res://scenes/Breakout.tscn") as PackedScene
	var breakout := breakout_scene.instantiate() as BreakoutNode
	add_child(breakout)
	await get_tree().process_frame
	# Freeze the ball immediately — with BRICK_HP=1 it can otherwise destroy
	# a brick out of pure launch-direction randomness during any of the
	# unrelated checks below (caught live: ".all()" crashed on an already-
	# freed brick mid-test). Explicitly re-enabled only for the two checks
	# that actually need it moving.
	breakout.ball.active = false

	# --- the ball launches at 70% of normal speed, Breakout-only ---
	var launch_speed_ok := is_equal_approx(breakout.ball.state.velocity.length(), BallState.BASE_SPEED * 0.7)
	print(("PASS: the ball launches at 70%% speed (%.0f, normal is %.0f)" % [breakout.ball.state.velocity.length(), BallState.BASE_SPEED]) if launch_speed_ok else ("FAIL: expected launch speed %.0f, got %.0f" % [BallState.BASE_SPEED * 0.7, breakout.ball.state.velocity.length()]))

	# --- the per-return speed-up is halved, Breakout-only (Camil: "le taux d'acceleration de la balle au rebond doit etre moins fort dans ce mode de jeu uniquement") ---
	var reduced_ok := is_equal_approx(breakout.ball.speed_increment_multiplier, 0.5)
	var probe := BallState.new(Vector2.ZERO, Vector2(100.0, 0.0))
	var normal_return := probe.returned(Vector2.ZERO, 0.0, 1)
	var reduced_return := probe.returned(Vector2.ZERO, 0.0, 1, BallState.SPEED_INCREMENT_PER_RETURN * breakout.ball.speed_increment_multiplier)
	var acceleration_ok := reduced_ok and reduced_return.velocity.length() < normal_return.velocity.length()
	print(("PASS: bounces speed the ball up more gently in this mode (normal +%.0f, here +%.0f)" % [normal_return.velocity.length() - BallState.BASE_SPEED, reduced_return.velocity.length() - BallState.BASE_SPEED]) if acceleration_ok else "FAIL: the reduced bounce-acceleration isn't actually weaker")

	# --- ship_1 is a REAL 2D-movement ShipNode, not a horizontal paddle ---
	var weapon_ok := breakout.ship_1.character == vif_campaign.character
	print(("PASS: ship_1 is the player's own real character (%s)" % vif_campaign.character.display_name) if weapon_ok else "FAIL: ship_1 didn't get the player's own character")

	var y_before := breakout.ship_1.position.y
	breakout.ship_1.ai_controlled = false
	# Drive real 2D movement the same way the main game's own tests do:
	# simulate the physical key directly, not InputMap actions.
	var down_event := InputEventKey.new()
	down_event.physical_keycode = KEY_S
	down_event.pressed = true
	Input.parse_input_event(down_event)
	for i in 20:
		await get_tree().physics_frame
	var y_after := breakout.ship_1.position.y
	var release_event := InputEventKey.new()
	release_event.physical_keycode = KEY_S
	release_event.pressed = false
	Input.parse_input_event(release_event)
	await get_tree().physics_frame
	var moves_in_2d_ok := y_after > y_before + 5.0
	print(("PASS: ship_1 actually moves vertically (2D movement, not a horizontal-only paddle) (%.1f -> %.1f)" % [y_before, y_after]) if moves_in_2d_ok else "FAIL: ship_1's Y never moved — still paddle-like")

	# --- bricks sit on the right, ball-deflectable via the REAL shared TurretNode mechanic ---
	var bricks_on_right_ok := breakout._bricks.size() > 0 and breakout._bricks.filter(func(b): return is_instance_valid(b)).all(func(b): return b.position.x > BreakoutNode.FRONTIER_X)
	print("PASS: the brick grid sits entirely on the right, past the center line" if bricks_on_right_ok else "FAIL: some bricks aren't past the frontier")

	# --- weapon fire hits a brick (reuses ProjectileNode's existing turret-hit sweep-check) ---
	var target_brick: TurretNode = breakout._bricks[0]
	var hp_before := target_brick.hp
	# ShipNode re-syncs .position FROM .state.position every physics tick —
	# must set both or the direct assignment gets silently overwritten
	# next frame (same gotcha as BallNode, see project memory).
	breakout.ship_1.position = target_brick.position - Vector2(200.0, 0.0)
	breakout.ship_1.state.position = breakout.ship_1.position
	breakout._on_weapon_fired(breakout.ship_1.weapon_state.selected_weapon())
	for i in 60: # give a straight-line shot time to cross 200px
		await get_tree().physics_frame
	var weapon_hits_brick_ok := not is_instance_valid(target_brick) or target_brick.hp < hp_before
	print("PASS: firing the player's own weapon damages/destroys a brick" if weapon_hits_brick_ok else "FAIL: the weapon shot never reached/damaged the brick")

	# --- ball bounce also damages a brick (classic Breakout mechanic, reused BallNode._resolve_turrets()) ---
	var second_brick: TurretNode = null
	for b in breakout._bricks:
		if is_instance_valid(b):
			second_brick = b
			break
	var ball_ok := false
	if second_brick:
		var ball_hp_before := second_brick.hp
		breakout.ball.active = true # re-enable — frozen at setup, see that comment
		breakout.ball.state.position = second_brick.position
		breakout.ball.position = second_brick.position
		breakout.ball.state.velocity = Vector2(50.0, 0.0)
		breakout.ball._return_cooldown = 0.0 # force a clean state — earlier checks in this test may have left a real cooldown mid-flight
		breakout.ball._blocked_side = -1
		for i in 3:
			await get_tree().physics_frame
		ball_ok = not is_instance_valid(second_brick) or second_brick.hp < ball_hp_before
		breakout.ball.active = false # re-freeze for the unrelated checks below
	print("PASS: the ball bouncing off a brick damages it" if ball_ok else "FAIL: the ball didn't damage the brick it touched")

	# --- the ball also damages popup enemies (Camil: "on casse les regles pour ce mode") ---
	breakout._spawn_enemy_group()
	var test_enemy: TurretNode = breakout._enemies[breakout._enemies.size() - 1]
	var enemy_ball_ok := false
	if is_instance_valid(test_enemy):
		# Enemies spawn scattered across the brick field's own area by
		# design ("emerging from among the bricks") — reposition this one
		# somewhere clearly clear of any brick first, or the ball can hit
		# an overlapping BRICK instead and this test would silently check
		# the wrong thing (caught live: enemy_pos ended up far from where
		# the ball landed, because a nearby brick's own hit-rect grabbed
		# the collision first).
		test_enemy.position = Vector2(1000.0, 600.0)
		var enemy_hp_before := test_enemy.hp
		breakout.ball.active = true
		breakout.ball.state.position = test_enemy.position
		breakout.ball.position = test_enemy.position
		breakout.ball.state.velocity = Vector2(50.0, 0.0)
		breakout.ball._return_cooldown = 0.0
		breakout.ball._blocked_side = -1
		for i in 3:
			await get_tree().physics_frame
		enemy_ball_ok = not is_instance_valid(test_enemy) or test_enemy.hp < enemy_hp_before
		breakout.ball.active = false
	print("PASS: the ball also damages a popup enemy" if enemy_ball_ok else "FAIL: the ball didn't damage the enemy it touched")

	# --- returning the ball fills the gauge bar and pops a "+X" (Camil: "afficher la jauge d'arme et les +x") ---
	var gauge_before := breakout.ship_1.weapon_state.gauges[breakout.ship_1.weapon_state.selected_index]
	var popups_before := breakout.get_children().filter(func(c): return c is FloatingTextNode).size()
	breakout.ball.active = true
	breakout.ball.state.position = breakout.ship_1.position
	breakout.ball.position = breakout.ship_1.position
	breakout.ball.state.velocity = Vector2(-50.0, 0.0)
	breakout.ball._return_cooldown = 0.0
	breakout.ball._blocked_side = -1
	await get_tree().physics_frame
	breakout.ball.active = false
	var gauge_after := breakout.ship_1.weapon_state.gauges[breakout.ship_1.weapon_state.selected_index]
	var popups_after := breakout.get_children().filter(func(c): return c is FloatingTextNode).size()
	var gauge_ui_ok := gauge_after > gauge_before and popups_after > popups_before
	print(("PASS: returning the ball fills the gauge (%.0f -> %.0f) and pops a '+X'" % [gauge_before, gauge_after]) if gauge_ui_ok else ("FAIL: gauge %.0f -> %.0f, popups %d -> %d" % [gauge_before, gauge_after, popups_before, popups_after]))

	# --- a shot reaching _dummy_target's own position doesn't crash ---
	# Live crash caught 2026-08-18: "Invalid call. Nonexistent function
	# 'damaged' in base 'Nil'" — _dummy_target is never added to the tree,
	# so its own _ready() (which builds .state) never runs; a projectile
	# whose straight path reaches it anyway (it deliberately sits inside
	# the brick field) hits the normal ship-hit check and crashes calling
	# apply_damage() on a null state. Clear only the ONE row _dummy_target
	# sits on (a clear lane is enough for a straight shot to reach it) —
	# NOT the whole grid: this test still needs bricks left afterward
	# (setting _resolved=true to dodge the real win-check here would also
	# block the countdown check below, itself gated on the same flag; a
	# real "no bricks left" would additionally fire the real win path for
	# real once _resolved is cleared again — caught both live).
	for b in breakout._bricks.duplicate():
		if is_instance_valid(b) and absf(b.position.y - breakout._dummy_target.position.y) < 1.0:
			b.queue_free()
	await get_tree().physics_frame
	breakout.ship_1.position = breakout._dummy_target.position - Vector2(300.0, 0.0)
	breakout.ship_1.state.position = breakout.ship_1.position
	breakout._on_weapon_fired(breakout.ship_1.weapon_state.selected_weapon())
	for i in 60:
		await get_tree().physics_frame
	var dummy_target_no_crash_ok := is_instance_valid(breakout) and is_instance_valid(breakout._dummy_target)
	print("PASS: a shot reaching the dummy target's own position doesn't crash" if dummy_target_no_crash_ok else "FAIL: hitting the dummy target crashed/broke the scene")

	# --- the far wall bounces the ball back instead of respawning it center-screen ---
	var max_x := BreakoutNode.ARENA_BOUNDS.position.x + BreakoutNode.ARENA_BOUNDS.size.x - BallState.RADIUS
	breakout.ball.active = true # re-enable — frozen at setup, see that comment
	breakout.ball.state.position = Vector2(max_x + 2.0, 300.0) # already past the wall, so the very next tick's check is unambiguous
	breakout.ball.state.velocity = Vector2(200.0, 0.0) # heading further into the far wall
	await get_tree().physics_frame
	var wall_bounce_ok := breakout.ball.state.velocity.x < 0.0 and breakout.ball.state.position.x <= max_x + 0.5
	print(("PASS: the far wall bounces the ball back (vel.x=%.0f), no reset-to-center" % breakout.ball.state.velocity.x) if wall_bounce_ok else "FAIL: the ball didn't bounce off the far wall")
	breakout.ball.active = false # re-freeze — the miss check right below emits ball_missed directly, doesn't need it moving

	# --- a miss also clears any enemy shot already in flight (Camil: "quand il y a le decompte 3 2 1 il faut supprimer les balles ennemies") ---
	var fake_enemy_shot := ProjectileNode.new()
	fake_enemy_shot.target = breakout.ship_1 # exactly what a real enemy shot's target looks like — see TurretNode._fire_at_target()
	breakout.add_child(fake_enemy_shot)
	await get_tree().process_frame

	# --- missing the ball costs real ship HP (reuses ShipNode.apply_damage, no separate lives counter) ---
	var hp_before_miss := breakout.ship_1.state.hp
	breakout.ball.ball_missed.emit(0)
	var miss_damages_hp_ok := breakout.ship_1.state.hp < hp_before_miss
	print(("PASS: missing the ball costs real ship HP (%.0f -> %.0f)" % [hp_before_miss, breakout.ship_1.state.hp]) if miss_damages_hp_ok else "FAIL: a miss didn't cost any HP")
	await get_tree().process_frame # queue_free() defers actual deallocation — is_instance_valid() right after the call would still read true

	var enemy_shots_cleared_ok := not is_instance_valid(fake_enemy_shot)
	print("PASS: an in-flight enemy shot is cleared when the countdown starts" if enemy_shots_cleared_ok else "FAIL: the enemy shot survived the countdown freeze")

	# --- a miss freezes play for a 3-2-1 countdown, then resumes ---
	var freeze_ok := not breakout.ship_1.active and not breakout.ball.active and breakout.message_label.text == "3"
	print("PASS: a miss freezes ship_1/ball and shows the countdown" if freeze_ok else ("FAIL: expected frozen+'3', got ship_1.active=%s ball.active=%s text='%s'" % [breakout.ship_1.active, breakout.ball.active, breakout.message_label.text]))
	for i in 200: # a bit over 3s @ 60fps — the full 3-2-1 count plus margin
		await get_tree().physics_frame
	var countdown_ends_ok := breakout.ship_1.active and breakout.ball.active and breakout.message_label.text == ""
	print("PASS: the countdown ends and resumes play" if countdown_ends_ok else ("FAIL: still frozen after 3s+ — ship_1.active=%s ball.active=%s text='%s'" % [breakout.ship_1.active, breakout.ball.active, breakout.message_label.text]))

	# --- everything freezes on defeat too (Camil: "quand il y a 'defaite' il faut tout freezer") ---
	# Exercises _freeze_gameplay() directly, same reasoning as calling
	# _resolve() directly elsewhere in this file — the freeze itself
	# happens in _physics_process()'s loss-detection branch, not inside
	# _resolve(), so this is the actual behavior under test either way.
	var loss_enemy := TurretNode.new()
	loss_enemy.weapon = WeaponData.new()
	loss_enemy.autofire = true
	loss_enemy.target = breakout.ship_1 # its own liveness check frees it immediately without a valid target
	loss_enemy.lifetime_override = 999.0 # and without a real lifetime — WeaponData's own default is 0
	breakout.add_child(loss_enemy)
	breakout._enemies.append(loss_enemy) # _freeze_gameplay() only toggles autofire on TRACKED enemies, not every TurretNode child
	var loss_enemy_shot := ProjectileNode.new()
	loss_enemy_shot.target = breakout.ship_1
	breakout.add_child(loss_enemy_shot)
	await get_tree().process_frame
	breakout._freeze_gameplay()
	await get_tree().process_frame # queue_free() defers actual deallocation — is_instance_valid() right after the call would still read true
	var loss_freeze_ok := not breakout.ship_1.active and not breakout.ball.active and not loss_enemy.autofire and not is_instance_valid(loss_enemy_shot)
	print("PASS: defeat freezes ship_1/ball/enemy fire and clears shots" if loss_freeze_ok else "FAIL: something kept moving/firing after a defeat freeze")

	# --- pressing K instantly clears the level (Camil: "on peut garder la touche K pour finir le niveau direct ?") ---
	var bricks_before_cheat := breakout._bricks.filter(func(b): return is_instance_valid(b)).size()
	var k_press := InputEventKey.new()
	k_press.physical_keycode = KEY_K
	k_press.pressed = true
	Input.parse_input_event(k_press)
	for i in 3: # hold it a few ticks, same margin the KEY_S movement check above uses — a single awaited frame proved unreliable for a same-tick edge trigger
		await get_tree().physics_frame
	var k_release := InputEventKey.new()
	k_release.physical_keycode = KEY_K
	k_release.pressed = false
	Input.parse_input_event(k_release)
	# queue_free() only defers actual deallocation to end-of-frame, so the
	# NATURAL win-check (later in this SAME _physics_process call) still
	# sees every brick as "alive" this tick — freeze right now, before a
	# SECOND tick would see them actually gone and cascade into the real
	# win flow for real (same class of self-inflicted scene-change bug
	# this file has hit before — see the dummy-target check's own notes).
	breakout._resolved = true
	await get_tree().process_frame
	var cheat_win_ok := bricks_before_cheat > 0 and breakout._bricks.filter(func(b): return is_instance_valid(b)).size() == 0
	print(("PASS: the K cheat instantly clears every brick (%d -> 0)" % bricks_before_cheat) if cheat_win_ok else "FAIL: the K cheat didn't clear the bricks")

	# --- win resolution: same campaign-completion path a mook fight uses ---
	var currency_before := CampaignSave.get_currency("vif")
	var reward: int = branch.mook_1.reward_currency
	breakout._resolved = true
	breakout._resolve(true) # not awaited past its own first internal await — see file doc comment convention elsewhere in this test suite
	await get_tree().process_frame
	var win_resolution_ok := CampaignSave.get_currency("vif") == currency_before + reward
	print(("PASS: winning awards the mook's reward_currency (+%d), same as a real fight" % reward) if win_resolution_ok else "FAIL: currency wasn't awarded correctly on win")

	breakout.queue_free()
	CampaignContext.clear()
	CampaignSave.reset_all() # never leave fake progress in the real save file
	await get_tree().process_frame

	var all_ok := weapon_ok and launch_speed_ok and acceleration_ok and moves_in_2d_ok and bricks_on_right_ok and weapon_hits_brick_ok and ball_ok and enemy_ball_ok and gauge_ui_ok and dummy_target_no_crash_ok and wall_bounce_ok and enemy_shots_cleared_ok and miss_damages_hp_ok and freeze_ok and countdown_ends_ok and loss_freeze_ok and cheat_win_ok and win_resolution_ok
	get_tree().quit(0 if all_ok else 1)
