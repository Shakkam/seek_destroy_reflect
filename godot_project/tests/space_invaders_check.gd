extends Node2D

## Scene-boot check for the Space Invaders mini-jeu (2026-08-22), built on
## the same real-game-systems approach validated by Breakout (see
## breakout_check.gd's own doc comment for the full history/reasoning).
## IMPORTANT: touches the REAL save file via CampaignSave — reset_all()
## before AND after. Run with:
##   Godot --headless --path . res://tests/space_invaders_check.tscn --quit-after 4000 --fixed-fps 60
## (verified complete at exactly this budget — bump generously if new checks are added, see project memory's --quit-after truncation trap)

func _ready() -> void:
	CampaignSave.reset_all()

	var vif_campaign: CampaignData = load("res://data/campaigns/vif_campaign.tres")
	var branch: MiniBranchData = vif_campaign.mini_branches[0]
	CampaignContext.enter_campaign(vif_campaign, 0) # campaign_step 0 -> branch[0].mook_1

	var scene := load("res://scenes/SpaceInvaders.tscn") as PackedScene
	var game := scene.instantiate() as SpaceInvadersNode
	add_child(game)
	await get_tree().process_frame
	# All 40 aliens autofire at ship_1 from the moment they spawn — left
	# alone for the whole test's real time (several seconds), enough of
	# them landing hits can drop ship_1 to 0 HP for real well before the
	# dedicated "alien fire" check below, triggering the REAL loss
	# resolution (scene change) and silently killing this test mid-run
	# (caught live: the test just stopped printing with no error, exit
	# code 0 — the exact trap --quit-after's own frame-count cutoff is
	# usually blamed for, but the real cause here was gameplay, not a
	# truncated frame budget). Silence every alien except the one the
	# dedicated check re-enables later.
	for alien in game._formation:
		alien.autofire = false

	# --- ship_1 is the player's own real character, formation sits on the right ---
	var weapon_ok := game.ship_1.character == vif_campaign.character
	print(("PASS: ship_1 is the player's own real character (%s)" % vif_campaign.character.display_name) if weapon_ok else "FAIL: ship_1 didn't get the player's own character")
	var formation_ok := game._formation.size() == SpaceInvadersNode.FORMATION_COLS * SpaceInvadersNode.FORMATION_ROWS and game._formation.all(func(a): return a.position.x > SpaceInvadersNode.FRONTIER_X)
	print("PASS: the formation is full-size and sits entirely past the center line" if formation_ok else "FAIL: formation size/position wrong")

	# --- no ball in this mode — the gauge fills over time instead (ship_1.passive_trickle_rate) ---
	var gauge_before := game.ship_1.weapon_state.gauges[game.ship_1.weapon_state.selected_index]
	for i in 60: # 1s @ 60fps
		await get_tree().physics_frame
	var gauge_after := game.ship_1.weapon_state.gauges[game.ship_1.weapon_state.selected_index]
	var trickle_ok := gauge_after > gauge_before
	print(("PASS: the gauge fills passively over time, no ball needed (%.1f -> %.1f)" % [gauge_before, gauge_after]) if trickle_ok else "FAIL: the gauge never filled without a ball")

	# --- the formation advances toward the player over time ---
	var probe_alien: TurretNode = game._formation[0]
	var x_before := probe_alien.position.x
	for i in 60:
		await get_tree().physics_frame
	var advance_ok := probe_alien.position.x < x_before
	print(("PASS: the formation advances toward the player (%.1f -> %.1f)" % [x_before, probe_alien.position.x]) if advance_ok else "FAIL: the formation never moved")

	# --- weapon fire hits an alien (reuses ProjectileNode's existing turret-hit sweep-check) ---
	var target_alien: TurretNode = game._formation[0]
	var hp_before := target_alien.hp
	game.ship_1.position = target_alien.position - Vector2(300.0, 0.0)
	game.ship_1.state.position = game.ship_1.position
	game._on_weapon_fired(game.ship_1.weapon_state.selected_weapon())
	for i in 90:
		await get_tree().physics_frame
	var weapon_hits_alien_ok := not is_instance_valid(target_alien) or target_alien.hp < hp_before
	print("PASS: firing the player's own weapon damages/destroys an alien" if weapon_hits_alien_ok else "FAIL: the weapon shot never reached/damaged the alien")

	# --- an alien shot damages ship_1 (autofire, reused TurretNode._fire_at_target()) ---
	# Fires from wherever the alien actually sits (its normal formation
	# spot, ~500px from ship_1) rather than being dragged close — dragging
	# it near ship_1 previously put its X past the frontier, tripping the
	# INVASION loss check for real and yanking the whole scene out from
	# under this test mid-run (same class of self-inflicted bug
	# breakout_check.gd hit with its own dummy-target/win-check checks).
	var hp_ship_before := game.ship_1.state.hp
	var firing_alien: TurretNode = null
	for a in game._formation:
		if is_instance_valid(a):
			firing_alien = a
			break
	if firing_alien:
		firing_alien.autofire = true # every other alien stays silenced — see the setup comment above
	# The formation keeps drifting toward FRONTIER_X the whole time this
	# check waits (~4s) on top of the drift already spent in the checks
	# above — enough real drift to cross the INVASION_MARGIN threshold and
	# trigger a REAL loss mid-wait, yanking the scene out from under this
	# test (caught live: the run silently stopped after the "weapon hits
	# an alien" check with no error). Restore some runway right before the
	# long wait rather than freezing the advance outright, since the
	# advance itself isn't what this check is testing.
	for a in game._formation:
		if is_instance_valid(a):
			a.position.x += 200.0
	for i in 250: # ~2.9s fire cooldown (ALIEN_FIRE_RATE=0.35) + ~1s travel time at 480px/s over ~500px, with margin
		await get_tree().physics_frame
	var alien_fire_ok := game.ship_1.state.hp < hp_ship_before
	print(("PASS: an alien's own fire damages ship_1 (%.0f -> %.0f)" % [hp_ship_before, game.ship_1.state.hp]) if alien_fire_ok else "FAIL: no alien fire ever landed")

	# --- invasion: an alien crossing the frontier ends the level (loss), everything freezes ---
	game._resolved = false # the alien-fire wait above may have already let HP drop toward 0 naturally; force a clean slate for this specific check
	game.ship_1.active = true
	var invading_alien: TurretNode = null
	for a in game._formation:
		if is_instance_valid(a):
			invading_alien = a
			break
	var invasion_ok := false
	if invading_alien:
		invading_alien.autofire = false # isolate the invasion check from also taking damage this same tick
		# 2026-08-22 (Camil: "il faudrait attendre que l'ennemi touche
		# vraiment la ligne centrale") — invasion is now the alien's own
		# leading edge crossing FRONTIER_X, no more early buffer margin.
		invading_alien.position.x = SpaceInvadersNode.FRONTIER_X + SpaceInvadersNode.FORMATION_HALF_EXTENTS.x - 1.0
		await get_tree().physics_frame
		invasion_ok = game._resolved and not game.ship_1.active
	print("PASS: an alien reaching the frontier ends the level and freezes everything" if invasion_ok else "FAIL: the invasion wasn't detected/didn't freeze play")

	# --- defeat names which condition actually fired (Camil: "lors de la defaite dire pourquoi") ---
	await get_tree().process_frame # let the deferred _resolve() call (scheduled by the invasion check above) actually run and set the label
	var invasion_message_ok := "ligne centrale" in game.message_label.text
	print(("PASS: an invasion defeat names the reason ('%s')" % game.message_label.text) if invasion_message_ok else ("FAIL: expected the invasion reason in the message, got '%s'" % game.message_label.text))
	game._resolve(false, "Vous avez ete detruit") # not awaited past its own first internal await — see the win-resolution check's own convention below
	await get_tree().process_frame
	var destroyed_message_ok := "detruit" in game.message_label.text
	print(("PASS: a destroyed-ship defeat names the reason ('%s')" % game.message_label.text) if destroyed_message_ok else ("FAIL: expected the destroyed-ship reason in the message, got '%s'" % game.message_label.text))

	# --- win resolution: same campaign-completion path a mook fight uses ---
	var currency_before := CampaignSave.get_currency("vif")
	var reward: int = branch.mook_1.reward_currency
	game._resolved = true
	game._resolve(true) # not awaited past its own first internal await — see reward_reveal_check.gd's own convention for why
	await get_tree().process_frame
	var win_resolution_ok := CampaignSave.get_currency("vif") == currency_before + reward
	print(("PASS: winning awards the mook's reward_currency (+%d), same as a real fight" % reward) if win_resolution_ok else "FAIL: currency wasn't awarded correctly on win")

	game.queue_free()
	CampaignContext.clear()
	CampaignSave.reset_all() # never leave fake progress in the real save file
	await get_tree().process_frame

	var all_ok := weapon_ok and formation_ok and trickle_ok and advance_ok and weapon_hits_alien_ok and alien_fire_ok and invasion_ok and invasion_message_ok and destroyed_message_ok and win_resolution_ok
	get_tree().quit(0 if all_ok else 1)
