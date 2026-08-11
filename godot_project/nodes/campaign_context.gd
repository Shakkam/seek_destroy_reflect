extends Node

## Epic 4 — carries a campaign encounter's setup across the scene change
## from the campaign map (Story 4.2/4.3) into MatchArena and back, and now
## also into MiniBranchMap (2026-08-08 UX rework). Mirrors MatchSetup's
## role for the 1v1 flow — Godot has no built-in way to pass data across
## change_scene_to_file(). Orchestration, not simulation (Regle absolue n1).
##
## branch_step replaces the old "which RivalEncounterData resource is this"
## identity comparison (2026-08-08 bug: authoring mook_1 == mook_2 as the
## same resource made that comparison always report step 1, which read as
## a stuck loop even once mook_1/mook_2 were split into distinct resources
## — an explicit integer step is unambiguous regardless of authoring).
## Progress only ever moves forward: advance_branch_step() is the only way
## branch_step changes, and a loss re-fights the same step rather than
## resetting it — "on ne peut jamais reculer" (Camil, 2026-08-08).

var campaign: CampaignData
var branch: MiniBranchData # null when fighting the organizer
var branch_step: int = 0 # 0 = next up is mook_1, 1 = mook_2, 2 = rival, 3 = branch complete
var is_organizer_fight := false

## Cheat menu (2026-08-09, Camil: "tu aurais un sous menu 'cheat' de la
## campagne, pour que je puisse tester tous les twists ?") — bypasses
## branch/organizer progression entirely: a throwaway RivalEncounterData
## built on the fly by CampaignCheatMenuNode, fought with no currency/unlock/
## branch_step side effects, bounced straight back to the cheat menu after.
var debug_encounter: RivalEncounterData = null

func has_pending_encounter() -> bool:
	return campaign != null and (branch != null or is_organizer_fight or debug_encounter != null)

## The RivalEncounterData for whatever should be fought right now, given
## branch_step (or the organizer's encounter, or a cheat-menu debug fight).
## Null once branch_step has already reached 3 (nothing left to fight in
## this branch).
func current_encounter() -> RivalEncounterData:
	if debug_encounter:
		return debug_encounter
	if is_organizer_fight:
		return campaign.organizer_encounter
	if not branch:
		return null
	match branch_step:
		0:
			return branch.mook_1
		1:
			return branch.mook_2
		2:
			return branch.rival
		_:
			return null

func clear() -> void:
	campaign = null
	branch = null
	branch_step = 0
	is_organizer_fight = false
	debug_encounter = null

## 2026-08-11 bug report: "quand je bats un rival, au lieu de continuer vers
## la suite de la campagne, je reviens a la selection de mon perso" — every
## path back to CampaignMap.tscn after a finished fight (branch complete,
## organizer won or lost) called clear(), which also nulls `campaign` — but
## CampaignMapNode._ready() needs `campaign` to know which character's map
## to keep showing, and bounces straight to CampaignCharacterSelect when
## it's null. Same partial reset as clear(), minus that one field.
func return_to_map() -> void:
	branch = null
	branch_step = 0
	is_organizer_fight = false
	debug_encounter = null

## Cheat menu — fight a specific opponent with a specific twist (or no
## twist) active, full HP both sides, no campaign progression touched.
func start_debug_fight(campaign_data: CampaignData, encounter: RivalEncounterData) -> void:
	campaign = campaign_data
	branch = null
	is_organizer_fight = false
	debug_encounter = encounter

## Story 4.3 — begin (or resume) a mini-branch. Called once from the
## campaign map; MiniBranchMap re-reads branch_step on every visit rather
## than this being called again mid-branch.
func start_branch(campaign_data: CampaignData, branch_data: MiniBranchData) -> void:
	campaign = campaign_data
	branch = branch_data
	branch_step = 0
	is_organizer_fight = false

## Story 4.8 — begin the final encounter.
func start_organizer_fight(campaign_data: CampaignData) -> void:
	campaign = campaign_data
	branch = null
	is_organizer_fight = true

## Called after winning the current step's fight. Returns true if the
## branch still has fights remaining (MatchArenaNode should return to
## MiniBranchMap), false if the branch just completed (return to
## CampaignMap instead).
func advance_branch_step() -> bool:
	branch_step += 1
	return branch_step < 3
