extends Node2D

## Scene-boot verification for Story 4.4/4.6/4.8's MatchArenaNode campaign
## setup — same rationale as round_end_check.gd/twist_apply_check.gd:
## match_arena_node.gd depends on autoloads (MatchSetup, CampaignContext,
## CampaignSave) that the -s harness (smoke_test.gd) doesn't initialize.
## Run with:
##   Godot --headless --path godot_project res://tests/campaign_setup_check.tscn --quit-after 10

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
	arena3.queue_free()
	CampaignContext.clear()

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
		and branch_map_guard_ok and branch_map_step0_ok and branch_map_step1_ok
	get_tree().quit(0 if all_ok else 1)
