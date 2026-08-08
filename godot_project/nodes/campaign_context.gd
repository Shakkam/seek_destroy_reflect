extends Node

## Epic 4 — carries a campaign encounter's setup across the scene change
## from the campaign map (Story 4.2/4.3) into MatchArena (Story 4.4/4.6/4.8),
## and back. Mirrors MatchSetup's role for the 1v1 flow — Godot has no
## built-in way to pass data across change_scene_to_file(). Orchestration,
## not simulation (Regle absolue n1).

var campaign: CampaignData
var branch: MiniBranchData # null when fighting the organizer (is_organizer_fight == true)
var encounter: RivalEncounterData
var is_organizer_fight := false

## MatchArenaNode reads this on _ready() to know whether it's in campaign
## mode at all — cleared automatically once a campaign match starts so a
## later plain 1v1 (MatchSetup-only) launch never misreads stale state.
func has_pending_encounter() -> bool:
	return campaign != null and encounter != null

func clear() -> void:
	campaign = null
	branch = null
	encounter = null
	is_organizer_fight = false

## Story 4.3 — begin one of the fixed mook_1 -> mook_2 -> rival encounters
## within a mini-branch.
func start_branch(campaign_data: CampaignData, branch_data: MiniBranchData, encounter_data: RivalEncounterData) -> void:
	campaign = campaign_data
	branch = branch_data
	encounter = encounter_data
	is_organizer_fight = false

## Story 4.8 — begin the final encounter.
func start_organizer_fight(campaign_data: CampaignData) -> void:
	campaign = campaign_data
	branch = null
	encounter = campaign_data.organizer_encounter
	is_organizer_fight = true

## Story 4.4 — a mini-branch's 3 fights (mook_1 -> mook_2 -> rival) chain
## directly into each other (MatchArenaNode reloads the scene rather than
## bouncing back to the map between them) instead of persisting mid-branch
## progress to CampaignSave — only branch *completion* needs to survive a
## restart, not which fight within it the player is currently on.
## Returns true if there was a next fight to advance to, false if `encounter`
## was already the rival (or this isn't a mini-branch encounter at all).
func advance_within_branch() -> bool:
	if is_organizer_fight or branch == null:
		return false
	if encounter == branch.mook_1:
		encounter = branch.mook_2
		return true
	if encounter == branch.mook_2:
		encounter = branch.rival
		return true
	return false
