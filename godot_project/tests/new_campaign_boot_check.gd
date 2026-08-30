extends Node2D

## One-off scene-boot verification for the 2026-08-16 bulk campaign
## authoring pass (Camil: "ok pour les campagnes") — all 8 characters now
## have a real campaign, generated from the same template Vif's proven
## one already used. This drives one of the NEW ones (Lourd's, arbitrarily
## picked) through the single world-map screen (2026-08-24 rework — used
## to also drive a separate MiniBranchMap) to catch anything the map-
## rendering code implicitly assumed about Vif's specific branch layout
## rather than reading generically off CampaignData. Run with:
##   Godot --headless --path godot_project res://tests/new_campaign_boot_check.tscn --quit-after 200

func _ready() -> void:
	CampaignSave.reset_all() # this test's own arrival at the map reads/writes campaign_progress — never touch real save state
	CampaignContext.campaign = load("res://data/campaigns/lourd_campaign.tres")

	var map_scene := load("res://scenes/CampaignMap.tscn") as PackedScene
	var map := map_scene.instantiate() as CampaignMapNode
	add_child(map)
	await get_tree().process_frame

	var map_ok: bool = is_instance_valid(map) and map.title_label.text == "Lourd"
	print(("PASS: CampaignMap boots fine with a non-Vif campaign, titled '%s'" % map.title_label.text) if map_ok else ("FAIL: CampaignMap didn't boot correctly for Lourd's campaign (title='%s')" % map.title_label.text))

	# Confirm the first branch it built tiles from is really one of Lourd's
	# own (not some stale Vif-shaped assumption).
	var first_branch: MiniBranchData = CampaignContext.campaign.mini_branches[0]
	var branch_id_ok: bool = first_branch.id == "vs_controleur"
	print(("PASS: the first branch is Lourd's own roster ('%s')" % first_branch.id) if branch_id_ok else ("FAIL: unexpected first branch id '%s'" % first_branch.id))

	# Same generic-rendering concern for the flat tile sequence itself —
	# tile 0 must be that branch's own mook_1, current (fresh campaign).
	var tiles_ok: bool = map._tile_encounters[0] == first_branch.mook_1 and map._tile_status(0) == "current"
	print("PASS: the world map's first tile is Lourd's own branch's mook_1, marked current" if tiles_ok else "FAIL: tile 0 wasn't Lourd's own mook_1/current")

	map.queue_free()
	await get_tree().process_frame

	var all_ok := map_ok and branch_id_ok and tiles_ok
	CampaignContext.clear()
	CampaignSave.reset_all() # never leave fake progress in the real save file
	get_tree().quit(0 if all_ok else 1)
