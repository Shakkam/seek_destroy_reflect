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
	CampaignContext.start_branch(vif_campaign, branch, branch.mook_1)
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	var mook_ok := arena.ship_2.ai_controlled \
		and arena.ship_2.character == branch.mook_1.opponent \
		and arena.ship_2.max_hp_override == ShipState.START_HP * branch.mook_1.mook_hp_multiplier \
		and arena.active_twist == null \
		and arena.ship_1.character == vif_campaign.character
	print("PASS: mook fight configures ship_2 (reduced HP, no twist, correct opponent)" if mook_ok else "FAIL: mook fight setup incorrect")
	arena.queue_free()
	CampaignContext.clear()
	await get_tree().process_frame

	# --- Rival fight: full HP, twist applied ---
	CampaignContext.start_branch(vif_campaign, branch, branch.rival)
	var arena2 := arena_scene.instantiate() as MatchArenaNode
	add_child(arena2)
	await get_tree().process_frame

	var rival_ok := arena2.ship_2.character == branch.rival.opponent \
		and arena2.ship_2.max_hp_override == ShipState.START_HP \
		and arena2.active_twist == branch.rival.twist
	print("PASS: rival fight configures ship_2 (full HP, twist applied)" if rival_ok else "FAIL: rival fight setup incorrect")
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
	arena3.queue_free()
	CampaignContext.clear()

	get_tree().quit(0 if (mook_ok and rival_ok and organizer_ok) else 1)
