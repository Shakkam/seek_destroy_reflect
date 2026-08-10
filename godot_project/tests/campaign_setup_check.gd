extends Node2D

## Scene-boot verification for Story 4.4/4.6/4.8's MatchArenaNode campaign
## setup — same rationale as round_end_check.gd/twist_apply_check.gd:
## match_arena_node.gd depends on autoloads (MatchSetup, CampaignContext,
## CampaignSave) that the -s harness (smoke_test.gd) doesn't initialize.
## Run with:
##   Godot --headless --path godot_project res://tests/campaign_setup_check.tscn --quit-after 60
## 2026-08-09: --quit-after counts FRAMES, and this file keeps growing —
## too low a value silently truncates the run before its own quit(0/1),
## and Godot's default clean-exit code (0) then masquerades as a pass. If
## new checks stop appearing in the output, raise this number first.

func _ready() -> void:
	var vif_campaign: CampaignData = load("res://data/campaigns/vif_campaign.tres")
	var branch: MiniBranchData = vif_campaign.mini_branches[0] # vs_lourd

	# --- Mook fight: reduced HP, no twist ---
	CampaignContext.start_branch(vif_campaign, branch)
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	var expected_mook_hp := ShipState.START_HP * branch.mook_1.mook_hp_multiplier
	var mook_ok := arena.ship_2.ai_controlled \
		and arena.ship_2.character == branch.mook_1.opponent \
		and arena.ship_2.max_hp_override == expected_mook_hp \
		and arena.ship_2.state.hp == expected_mook_hp \
		and arena.active_twist == null \
		and arena.ship_1.character == vif_campaign.character
	# 2026-08-08 bug report: the mook's `state` was built in ship_2._ready()
	# (children ready before their parent) using the *old* default
	# max_hp_override, so `state.hp` started at 100 even though
	# max_hp_override was set to the reduced value right after — the HP bar
	# (which divides by max_hp_override) then read as stuck near-full while
	# the debug text's raw state.hp visibly dropped.
	print("PASS: mook's actual starting HP matches the reduced max (not stuck at 100)" if arena.ship_2.state.hp == expected_mook_hp else "FAIL: mook state.hp=%.1f, expected %.1f" % [arena.ship_2.state.hp, expected_mook_hp])
	print("PASS: mook fight configures ship_2 (reduced HP, no twist, correct opponent)" if mook_ok else "FAIL: mook fight setup incorrect")

	# 2026-08-08 bug: "je ne vois toujours pas de twist" — some twists (like
	# gauge_floor) have zero other visible tell, so the HUD must spell out
	# the encounter + active twist by name.
	var mook1_label_ok: bool = arena.campaign_label.text.contains("Sous-adversaire 1/2") and not arena.campaign_label.text.contains("Twist")
	print("PASS: campaign_label reads 'Sous-adversaire 1/2', no twist mention" if mook1_label_ok else "FAIL: campaign_label was '%s'" % arena.campaign_label.text)
	arena.queue_free()
	CampaignContext.clear()
	await get_tree().process_frame

	# --- Second mook: must read as a DIFFERENT step, not the same one again
	# (2026-08-08 bug: mook_1 and mook_2 were literally the same resource,
	# so this label always said "1/2" even on the second fight — read by
	# Camil as "always the same match repeating"). ---
	CampaignContext.start_branch(vif_campaign, branch)
	CampaignContext.advance_branch_step() # 0 (mook_1) -> 1 (mook_2)
	var arena_mook2 := arena_scene.instantiate() as MatchArenaNode
	add_child(arena_mook2)
	await get_tree().process_frame
	var mook2_label_ok: bool = arena_mook2.campaign_label.text.contains("Sous-adversaire 2/2")
	print("PASS: campaign_label reads 'Sous-adversaire 2/2' for the second mook" if mook2_label_ok else "FAIL: campaign_label was '%s'" % arena_mook2.campaign_label.text)
	arena_mook2.queue_free()
	CampaignContext.clear()
	await get_tree().process_frame

	# --- Rival fight: full HP, twist applied ---
	CampaignContext.start_branch(vif_campaign, branch)
	CampaignContext.advance_branch_step() # 0 -> 1
	CampaignContext.advance_branch_step() # 1 -> 2 (rival)
	var arena2 := arena_scene.instantiate() as MatchArenaNode
	add_child(arena2)
	await get_tree().process_frame

	var rival_ok := arena2.ship_2.character == branch.rival.opponent \
		and arena2.ship_2.max_hp_override == ShipState.START_HP \
		and arena2.active_twist == branch.rival.twist
	print("PASS: rival fight configures ship_2 (full HP, twist applied)" if rival_ok else "FAIL: rival fight setup incorrect")
	var rival_label_ok: bool = arena2.campaign_label.text.contains("Twist") and arena2.campaign_label.text.contains(branch.rival.twist.display_name)
	print("PASS: campaign_label names the active twist for the rival fight" if rival_label_ok else "FAIL: campaign_label was '%s'" % arena2.campaign_label.text)

	# 2026-08-08 bug: "l'IA continue à bouger" after match end — verify a
	# forced match_over freezes both ships (F1 also must be a no-op in
	# campaign mode, next check below).
	arena2.match_state = arena2.match_state.round_won_by(0).round_won_by(0) # best-of-3: 2 rounds seals it
	arena2.ship_1.state = arena2.ship_1.state.damaged(1000.0) # force a round-ending HP=0 next _check_round_end()
	arena2._check_round_end()
	var freeze_ok: bool = not arena2.ship_1.active and not arena2.ship_2.active and not arena2.ball.active
	print("PASS: match_over freezes ships/ball (AI stops moving)" if freeze_ok else "FAIL: ships/ball still active after match_over")

	# F1 itself can't be simulated headless (no real physical key press in
	# this environment, same limitation noted throughout this test suite),
	# so this can only confirm the guard's precondition holds on a real
	# campaign match rather than exercise the key press end to end.
	var f1_guard_precondition_ok: bool = arena2._campaign_mode
	print("PASS: campaign match has _campaign_mode set (F1 guard's precondition holds)" if f1_guard_precondition_ok else "FAIL: _campaign_mode was false on a campaign match")

	arena2.queue_free()
	CampaignContext.clear()
	await get_tree().process_frame

	# --- Organizer fight ---
	CampaignContext.start_organizer_fight(vif_campaign)
	var arena3 := arena_scene.instantiate() as MatchArenaNode
	add_child(arena3)
	await get_tree().process_frame

	var organizer_ok := arena3.ship_2.character == vif_campaign.organizer_encounter.opponent \
		and arena3.active_twist.twist_type == "energy_orb_pickup"
	print("PASS: organizer fight configures ship_2 and the signature twist" if organizer_ok else "FAIL: organizer fight setup incorrect")
	var organizer_label_ok: bool = arena3.campaign_label.text.contains("Organisateur")
	print("PASS: campaign_label names the organizer fight" if organizer_label_ok else "FAIL: campaign_label was '%s'" % arena3.campaign_label.text)
	# 2026-08-09 bug report (Camil, cheat-menu test): "Billes d'energie...
	# ca apparait dans le no man's land" — the orb must spawn on a ship's
	# actual playable side, never inside the unreachable neutral strip
	# around the frontier (ShipState.NEUTRAL_ZONE_HALF_WIDTH).
	arena3._energy_orb_timer = 0.0
	var orb_spawn_reachable_ok := true
	for i in 10: # multiple draws — side is randomized, both sides must land outside the neutral zone
		arena3._process_energy_orb_spawns(0.0)
		var spawned_orb: EnergyOrbNode = null
		for child in arena3.get_children():
			if child is EnergyOrbNode:
				spawned_orb = child
		if not spawned_orb:
			orb_spawn_reachable_ok = false
			break
		var dist_from_frontier := absf(spawned_orb.position.x - arena3._current_frontier_x)
		if dist_from_frontier < ShipState.NEUTRAL_ZONE_HALF_WIDTH:
			orb_spawn_reachable_ok = false
		spawned_orb.queue_free()
		arena3._energy_orb_timer = 0.0
	print("PASS: energy orb always spawns outside the unreachable neutral zone" if orb_spawn_reachable_ok else "FAIL: an energy orb spawned inside the neutral zone")

	arena3.queue_free()
	CampaignContext.clear()

	# --- Cheat menu debug fight (2026-08-09): neither a branch nor the
	# organizer — a third case _update_campaign_label() initially missed,
	# crashing on CampaignContext.branch being null ("Invalid access to
	# property or key 'display_name' on a base object of type 'Nil'"). ---
	var debug_encounter := RivalEncounterData.new()
	debug_encounter.opponent = vif_campaign.organizer_encounter.opponent
	debug_encounter.is_mook = false
	debug_encounter.twist = load("res://data/twists/hazard_zones.tres")
	CampaignContext.start_debug_fight(vif_campaign, debug_encounter)
	var arena4 := arena_scene.instantiate() as MatchArenaNode
	add_child(arena4)
	await get_tree().process_frame

	var debug_fight_ok := arena4.ship_2.character == debug_encounter.opponent \
		and arena4.ship_2.max_hp_override == ShipState.START_HP \
		and arena4.active_twist == debug_encounter.twist
	print("PASS: debug fight configures ship_2 (full HP, chosen twist, no branch/organizer needed)" if debug_fight_ok else "FAIL: debug fight setup incorrect")
	var debug_label_ok: bool = not arena4.campaign_label.text.is_empty() and arena4.campaign_label.text.contains("Cheat menu")
	print("PASS: campaign_label doesn't crash on a debug fight, names it as such" if debug_label_ok else "FAIL: campaign_label was '%s'" % arena4.campaign_label.text)
	# NOTE: _resolve_campaign_result()'s debug_encounter branch (routes back
	# to CampaignCheatMenu.tscn instead of MiniBranchMap/CampaignMap) isn't
	# exercised end-to-end here — awaiting its real change_scene_to_file()
	# would replace this test's own scene tree mid-run and crash the checks
	# still to come below (same reason the mook/rival/organizer sections
	# above only ever check the freeze/precondition, never await the actual
	# scene change either).
	arena4.queue_free()
	CampaignContext.clear()

	# --- Cheat menu scene (2026-08-09): lists every TwistData under
	# data/twists/ plus "Aucun twist" at index 0. ---
	var cheat_scene := load("res://scenes/CampaignCheatMenu.tscn") as PackedScene
	var cheat_menu := cheat_scene.instantiate() as CampaignCheatMenuNode
	add_child(cheat_menu)
	await get_tree().process_frame
	var twist_dir := DirAccess.open("res://data/twists")
	var twist_file_count := 0
	if twist_dir:
		twist_dir.list_dir_begin()
		var f := twist_dir.get_next()
		while f != "":
			if f.ends_with(".tres"):
				twist_file_count += 1
			f = twist_dir.get_next()
		twist_dir.list_dir_end()
	var cheat_menu_lists_all_twists_ok: bool = cheat_menu._twists.size() == twist_file_count + 1 and cheat_menu._twists[0] == null
	print("PASS: cheat menu lists every twist under data/twists/ plus 'Aucun twist'" if cheat_menu_lists_all_twists_ok else "FAIL: cheat menu listed %d entries for %d twist files" % [cheat_menu._twists.size(), twist_file_count])
	cheat_menu.queue_free()
	await get_tree().process_frame

	# --- Title screen menu (2026-08-09 rework) ---
	var title_scene := load("res://scenes/TitleScreen.tscn") as PackedScene
	var title := title_scene.instantiate() as TitleScreenNode
	add_child(title)
	# Checked immediately after add_child(), with NO awaited frame in
	# between — same pitfall the confirm-key carryover checks below already
	# guard against: headless input always reads "not pressed", so a single
	# _process() tick would legitimately overwrite the seeded true back to
	# false and silently defeat this check.
	var title_confirm_guard_ok: bool = title._confirm_prev == true
	print("PASS: TitleScreen seeds _confirm_prev true (carryover guard)" if title_confirm_guard_ok else "FAIL: TitleScreen's _confirm_prev is not seeded true")
	await get_tree().process_frame
	var title_menu_has_three_entries_ok: bool = title.MENU_ENTRIES.size() == 3
	print("PASS: title menu has exactly 3 entries (Nouvelle partie / Continuer / Versus)" if title_menu_has_three_entries_ok else "FAIL: title menu had %d entries" % title.MENU_ENTRIES.size())
	title.queue_free()
	await get_tree().process_frame

	# --- Twist visuals actually move (2026-08-09 bug report): "Le twist
	# zone qui retrecit ne marche pas" — _current_arena_bounds/
	# _current_frontier_x were updating correctly for collision, but
	# nothing moved the Background/NeutralZone/CenterLine nodes, so the
	# shrink/drift was real but invisible. ---
	var visuals_arena := arena_scene.instantiate() as MatchArenaNode
	add_child(visuals_arena)
	await get_tree().process_frame
	var shrunk_bounds := Rect2(100, 60, 800, 600) # smaller than the default 1200x600
	visuals_arena._current_arena_bounds = shrunk_bounds
	visuals_arena._current_frontier_x = 500.0
	visuals_arena._sync_twist_visuals()
	var background_ok: bool = is_equal_approx(visuals_arena.background.offset_left, shrunk_bounds.position.x) \
		and is_equal_approx(visuals_arena.background.offset_right, shrunk_bounds.position.x + shrunk_bounds.size.x)
	print("PASS: shrinking the arena bounds actually moves the Background visual" if background_ok else "FAIL: background offsets were %s/%s" % [visuals_arena.background.offset_left, visuals_arena.background.offset_right])
	var center_line_ok: bool = is_equal_approx(visuals_arena.center_line.points[0].x, 500.0)
	print("PASS: drifting the frontier actually moves the CenterLine visual" if center_line_ok else "FAIL: center_line.points[0].x was %s" % visuals_arena.center_line.points[0].x)
	visuals_arena.queue_free()
	await get_tree().process_frame

	# --- Beam spawn doesn't crash on a null weapon (2026-08-09 bug report):
	# "Invalid access to property or key 'beam_range' on a base object of
	# type 'Nil'" — BeamNode.weapon used to be assigned AFTER add_child(),
	# but add_child() calls _ready() synchronously, which already reads
	# weapon.beam_range via _update_shape(). ---
	var beam_arena := arena_scene.instantiate() as MatchArenaNode
	add_child(beam_arena)
	await get_tree().process_frame
	var laser: WeaponData = load("res://data/weapons/laser.tres")
	beam_arena.ship_1.beam_active = true
	beam_arena.ship_1.beam_weapon = laser
	var beam_spawn_ok := true
	beam_arena._sync_beam(beam_arena.ship_1, beam_arena.ship_2) # must not crash, and weapon must already be set
	if not beam_arena._beams.has(beam_arena.ship_1) or beam_arena._beams[beam_arena.ship_1].weapon != laser:
		beam_spawn_ok = false
	print("PASS: spawning a beam never leaves BeamNode.weapon null when _ready() runs" if beam_spawn_ok else "FAIL: beam weapon was not set correctly on spawn")
	beam_arena.queue_free()
	await get_tree().process_frame

	# --- Charged fire spawns the right burst (2026-08-09) — proven with
	# Lourd's bazooka: 2 shells, faster than a normal shot. ---
	var charge_arena := arena_scene.instantiate() as MatchArenaNode
	add_child(charge_arena)
	await get_tree().process_frame
	var bazooka: WeaponData = load("res://data/weapons/bazooka.tres")
	charge_arena._on_charged_weapon_fired(bazooka, charge_arena.ship_1)
	await get_tree().process_frame
	var spawned_charged_projectile: ProjectileNode = null
	for child in charge_arena.get_children():
		if child is ProjectileNode:
			spawned_charged_projectile = child
	var charged_burst_ok: bool = spawned_charged_projectile != null \
		and is_equal_approx(spawned_charged_projectile.velocity.length(), bazooka.projectile_speed * bazooka.charged_speed_multiplier)
	print("PASS: charged fire spawns a faster shell (Lourd's bazooka)" if charged_burst_ok else "FAIL: no charged projectile found, or speed was wrong")

	# Mini's charged fire: 10 shots swept top-to-bottom, staggered 1/8s
	# apart — the first fires immediately (i=0, no stagger delay), the rest
	# are scheduled via get_tree().create_timer(), same pattern as the
	# missile swarm's burst_stagger.
	var mini_shot: WeaponData = load("res://data/weapons/mini_shot.tres")
	var children_before_mini_charge := charge_arena.get_child_count()
	charge_arena._on_charged_weapon_fired(mini_shot, charge_arena.ship_1)
	await get_tree().process_frame
	var immediate_mini_shots := charge_arena.get_child_count() - children_before_mini_charge
	var mini_charge_ok: bool = immediate_mini_shots == 1 # only the i=0 shot fires this frame; the other 9 are timer-scheduled
	print("PASS: Eventail's charged fire fires the first (unstaggered) shot immediately" if mini_charge_ok else "FAIL: expected exactly 1 immediate projectile, got %d" % immediate_mini_shots)

	# Mitrailleur's charged fire: a pure self-buff, must spawn NO projectile
	# at all (unlike every other charged weapon so far).
	var machine_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	var children_before_mg_charge := charge_arena.get_child_count()
	charge_arena.ship_1._heat_immunity_timer = 0.0
	charge_arena._on_charged_weapon_fired(machine_gun, charge_arena.ship_1)
	await get_tree().process_frame
	var new_children_from_mg_charge := charge_arena.get_child_count() - children_before_mg_charge
	var mg_charge_ok: bool = new_children_from_mg_charge == 0 and charge_arena.ship_1._heat_immunity_timer > 0.0
	print("PASS: Mitrailleur's charged fire grants heat immunity with no projectile spawned" if mg_charge_ok else "FAIL: expected 0 new projectiles + immunity armed, got %d new children, immunity timer %s" % [new_children_from_mg_charge, charge_arena.ship_1._heat_immunity_timer])

	charge_arena.queue_free()
	await get_tree().process_frame

	# --- Confirm-key carryover guard (2026-08-08 bug report) ---
	# A player who's still holding Fire (Space) when a match ends and the
	# scene changes would otherwise insta-confirm frame 1 of the next menu —
	# on CampaignMap this silently re-launched branch 0, which read as "no
	# map at all" + "always the same match". The fix is seeding each
	# screen's _confirm_prev to true; verify it stuck instead of relying on
	# re-reading the source by eye.
	# NOTE: checked immediately after add_child(), with NO awaited frame in
	# between — headless input always reads as "not pressed", so a single
	# _process() tick would legitimately overwrite the seeded value back to
	# false and silently defeat this check (that bit the first version of
	# this test).
	CampaignContext.campaign = vif_campaign
	var map_scene := load("res://scenes/CampaignMap.tscn") as PackedScene
	var map := map_scene.instantiate() as CampaignMapNode
	add_child(map)
	var map_guard_ok: bool = map._confirm_prev == true
	print("PASS: CampaignMap seeds _confirm_prev true (carryover guard)" if map_guard_ok else "FAIL: CampaignMap's _confirm_prev is not seeded true")
	map.queue_free()
	CampaignContext.clear()
	await get_tree().process_frame

	# --- MiniBranchMap (2026-08-08 UX rework): squares should reflect
	# branch_step, and the rival square should name its twist. ---
	CampaignContext.start_branch(vif_campaign, branch)
	var branch_map_scene := load("res://scenes/MiniBranchMap.tscn") as PackedScene
	var branch_map := branch_map_scene.instantiate() as MiniBranchMapNode
	add_child(branch_map)
	var branch_map_guard_ok: bool = branch_map._confirm_prev == true
	print("PASS: MiniBranchMap seeds _confirm_prev true (carryover guard)" if branch_map_guard_ok else "FAIL: MiniBranchMap's _confirm_prev is not seeded true")
	var branch_map_step0_ok: bool = branch_map.node1_label.text.contains(">>") and branch_map.node2_label.text.contains("[ ]") and branch_map.node3_label.text.contains(branch.rival.twist.display_name)
	print("PASS: MiniBranchMap at step 0 marks node 1 current, node 2 unreached, names the rival's twist" if branch_map_step0_ok else "FAIL: MiniBranchMap step-0 labels were '%s' / '%s' / '%s'" % [branch_map.node1_label.text, branch_map.node2_label.text, branch_map.node3_label.text])
	CampaignContext.advance_branch_step()
	branch_map._refresh()
	var branch_map_step1_ok: bool = branch_map.node1_label.text.contains("[X]") and branch_map.node2_label.text.contains(">>")
	print("PASS: MiniBranchMap at step 1 marks node 1 done, node 2 current" if branch_map_step1_ok else "FAIL: MiniBranchMap step-1 labels were '%s' / '%s'" % [branch_map.node1_label.text, branch_map.node2_label.text])
	branch_map.queue_free()
	CampaignContext.clear()
	await get_tree().process_frame

	var char_select_scene := load("res://scenes/CampaignCharacterSelect.tscn") as PackedScene
	var char_select := char_select_scene.instantiate() as CampaignCharacterSelectNode
	add_child(char_select)
	var char_select_guard_ok: bool = char_select._confirm_prev == true
	print("PASS: CampaignCharacterSelect seeds _confirm_prev true (carryover guard)" if char_select_guard_ok else "FAIL: CampaignCharacterSelect's _confirm_prev is not seeded true")
	char_select.queue_free()

	var vs_select_scene := load("res://scenes/CharacterSelect.tscn") as PackedScene
	var vs_select := vs_select_scene.instantiate() as CharacterSelectNode
	add_child(vs_select)
	var vs_select_guard_ok: bool = vs_select._p1_confirm_prev == true and vs_select._p2_confirm_prev == true
	print("PASS: CharacterSelect seeds both players' _confirm_prev true (carryover guard)" if vs_select_guard_ok else "FAIL: CharacterSelect's confirm_prev fields are not seeded true")
	vs_select.queue_free()

	var all_ok := mook_ok and rival_ok and organizer_ok and map_guard_ok and char_select_guard_ok and vs_select_guard_ok \
		and mook1_label_ok and mook2_label_ok and rival_label_ok and organizer_label_ok and freeze_ok and f1_guard_precondition_ok \
		and branch_map_guard_ok and branch_map_step0_ok and branch_map_step1_ok \
		and debug_fight_ok and debug_label_ok \
		and cheat_menu_lists_all_twists_ok and title_confirm_guard_ok and title_menu_has_three_entries_ok \
		and orb_spawn_reachable_ok and background_ok and center_line_ok and beam_spawn_ok and charged_burst_ok and mini_charge_ok and mg_charge_ok
	get_tree().quit(0 if all_ok else 1)
