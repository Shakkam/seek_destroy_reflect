extends Node2D

## One-off scene-boot verification for the 2026-08-16 reward-reveal UI
## (Camil: "quand on bat un rival, il y a marque 'rival vaincu'. On
## pourrait ajouter 'vous avez gagne XXXXX' => icone + nom + description
## de l'arme"). Confirms a real rival win shows the reward icon (tinted to
## match that weapon's own established color, same convention the
## in-match HUD swatch already uses) and label (weapon display name + its
## passive_description) alongside "Rival vaincu !". Doesn't await
## _resolve_campaign_result() past its first internal await (the actual
## change_scene_to_file() would replace this test's own scene tree — same
## reasoning campaign_setup_check.gd documents for its own rival/organizer
## checks) — everything checked here happens synchronously before that
## point. IMPORTANT: CampaignSave.grant_unlock()/set_campaign_progress()
## inside _resolve_campaign_result() write to the REAL save file —
## reset_all() before AND after.
## Run with:
##   Godot --headless --path godot_project res://tests/reward_reveal_check.tscn --quit-after 60

func _ready() -> void:
	CampaignSave.reset_all()

	var vif_campaign: CampaignData = load("res://data/campaigns/vif_campaign.tres")
	var branch: MiniBranchData = vif_campaign.mini_branches[0] # vs_lourd -> unlock_reward is bazooka.tres
	CampaignContext.enter_campaign(vif_campaign, 2) # step 2 = branch[0].rival

	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	var reward_hidden_before_ok: bool = not arena.reward_icon.visible and not arena.reward_label.visible
	print("PASS: the reward icon/label start hidden" if reward_hidden_before_ok else "FAIL: the reward icon/label were already visible before any result resolved")

	arena._resolve_campaign_result(0) # side 0 (the player) wins — not awaited past its own first internal await, see file doc comment

	var bazooka: WeaponData = load("res://data/weapons/bazooka.tres")
	var icon_ok: bool = arena.reward_icon.visible and arena.reward_icon.color == arena._weapon_tint("bazooka")
	print(("PASS: the reward icon shows, tinted to match bazooka's own established color (%s)" % arena.reward_icon.color) if icon_ok else "FAIL: the reward icon wasn't shown/tinted correctly")

	var label_ok: bool = arena.reward_label.visible and arena.reward_label.text.contains(bazooka.display_name) and arena.reward_label.text.contains(bazooka.passive_description)
	print(("PASS: the reward label names the weapon and its passive_description ('%s')" % arena.reward_label.text.replace("\n", " / ")) if label_ok else ("FAIL: the reward label was wrong: '%s'" % arena.reward_label.text))

	var match_label_still_shows_ok: bool = arena.match_label.text == "Rival vaincu !"
	print("PASS: 'Rival vaincu !' still shows alongside the reward reveal" if match_label_still_shows_ok else ("FAIL: match_label read '%s'" % arena.match_label.text))

	arena.queue_free()
	CampaignContext.clear()
	CampaignSave.reset_all() # never leave fake progress in the real save file
	await get_tree().process_frame

	# --- organizer win (2026-08-22, Camil: "fin du tournoi => Tournoi
	# remporte, il faudrait revenir a l'accueil ensuite") — was
	# CampaignMap.tscn, now TitleScreen.tscn. Same "don't await past
	# _resolve_campaign_result()'s first internal await" convention as
	# above (the eventual change_scene_to_file() would tear down this
	# test's own scene tree) — only the synchronous state set before that
	# point is checkable here, so this confirms the organizer gets marked
	# defeated and the right label shows, trusting the change_scene_to_file
	# call itself (see the source for the actual target path).
	var organizer_arena := arena_scene.instantiate() as MatchArenaNode
	add_child(organizer_arena)
	await get_tree().process_frame
	CampaignContext.enter_campaign(vif_campaign, vif_campaign.mini_branches.size() * 3) # the organizer is always the last tile
	var organizer_defeated_before_ok: bool = not CampaignSave.is_organizer_defeated("vif")
	organizer_arena._resolve_campaign_result(0) # side 0 (the player) wins
	var organizer_win_ok: bool = CampaignSave.is_organizer_defeated("vif") and organizer_arena.match_label.text == "Tournoi remporte !"
	print(("PASS: winning the organizer fight marks it defeated and shows 'Tournoi remporte !'" if organizer_win_ok else ("FAIL: organizer_defeated=%s match_label='%s'" % [CampaignSave.is_organizer_defeated("vif"), organizer_arena.match_label.text])))
	organizer_arena.queue_free()
	CampaignContext.clear()
	CampaignSave.reset_all()
	await get_tree().process_frame

	var all_ok := reward_hidden_before_ok and icon_ok and label_ok and match_label_still_shows_ok and organizer_defeated_before_ok and organizer_win_ok
	get_tree().quit(0 if all_ok else 1)
