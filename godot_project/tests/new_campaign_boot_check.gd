extends Node2D

## One-off scene-boot verification for the 2026-08-16 bulk campaign
## authoring pass (Camil: "ok pour les campagnes") — all 8 characters now
## have a real campaign, generated from the same template Vif's proven
## one already used. This drives one of the NEW ones (Lourd's, arbitrarily
## picked) through CampaignMap and MiniBranchMap end to end to catch
## anything the map-rendering code implicitly assumed about Vif's specific
## branch layout rather than reading generically off CampaignData. Run
## with:
##   Godot --headless --path godot_project res://tests/new_campaign_boot_check.tscn --quit-after 200

func _ready() -> void:
	CampaignContext.campaign = load("res://data/campaigns/lourd_campaign.tres")

	var map_scene := load("res://scenes/CampaignMap.tscn") as PackedScene
	var map := map_scene.instantiate() as CampaignMapNode
	add_child(map)
	await get_tree().process_frame

	var map_ok: bool = is_instance_valid(map) and map.title_label.text == "Lourd"
	print(("PASS: CampaignMap boots fine with a non-Vif campaign, titled '%s'" % map.title_label.text) if map_ok else ("FAIL: CampaignMap didn't boot correctly for Lourd's campaign (title='%s')" % map.title_label.text))

	# Confirm the branch it draws first is really one of Lourd's own (not
	# some stale Vif-shaped assumption).
	var first_branch: MiniBranchData = CampaignContext.campaign.mini_branches[0]
	var branch_id_ok: bool = first_branch.id == "vs_controleur"
	print(("PASS: the first branch is Lourd's own roster ('%s')" % first_branch.id) if branch_id_ok else ("FAIL: unexpected first branch id '%s'" % first_branch.id))
	map.queue_free()
	await get_tree().process_frame

	# Drive one branch's mini-branch map too (2 mooks -> rival flow),
	# same generic-rendering concern.
	CampaignContext.branch = first_branch
	CampaignContext.branch_step = 0
	var mbm_scene := load("res://scenes/MiniBranchMap.tscn") as PackedScene
	var mbm := mbm_scene.instantiate()
	add_child(mbm)
	await get_tree().process_frame
	var mbm_ok: bool = is_instance_valid(mbm)
	print("PASS: MiniBranchMap boots fine for one of Lourd's branches" if mbm_ok else "FAIL: MiniBranchMap didn't boot")

	var all_ok := map_ok and branch_id_ok and mbm_ok
	CampaignContext.clear()
	get_tree().quit(0 if all_ok else 1)
