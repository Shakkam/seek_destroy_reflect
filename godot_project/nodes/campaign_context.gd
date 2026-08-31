extends Node

## Epic 4 — carries a campaign encounter's setup across the scene change
## from the campaign map into MatchArena and back. Mirrors MatchSetup's role
## for the 1v1 flow — Godot has no built-in way to pass data across
## change_scene_to_file(). Orchestration, not simulation (Regle absolue n1).
##
## 2026-08-24 world-map rework (Camil: "pour moi il faut une seule map, pas
## besoin de sous branche... vrai chemin... a la mario 3") — replaces the old
## branch/branch_step/is_organizer_fight trio with a single campaign_step: a
## flat, fixed-order position across ALL of a character's content (every
## branch's mook_1/mook_2/rival back to back, then the organizer). No more
## picking which branch to enter, no more a separate MiniBranchMap screen —
## CampaignMapNode reads campaign_step directly and always shows the one map.
## Progress only ever moves forward: advance_step() is the only way
## campaign_step changes, and a loss re-fights the same step rather than
## resetting it — "on ne peut jamais reculer" (Camil, 2026-08-08), unchanged
## from the branch-based version.

var campaign: CampaignData
var campaign_step: int = 0

## 2026-08-31 graph-mode campaign (Camil: "il n'y a plus de branches. La
## campagne DOIT se baser uniquement sur la carte"). When true, navigation
## and combat resolution are driven by node ids rather than a linear integer
## step — combat nodes can be fought in any order, each tracked individually.
var is_graph_mode: bool = false

## Graph mode only — the id of the combat node the player is currently
## fighting. Set by CampaignMapNode._confirm_selection() before entering the
## fight scene; preserved by return_to_map() so CampaignMap can restore the
## token's position after a loss.
var current_graph_node_id: String = ""

## Graph mode only — the RivalEncounterData for the node being fought right
## now. Set by CampaignMapNode._confirm_selection() before the scene change.
## current_encounter() returns this in graph mode (highest priority, overrides
## the encounter_sequence lookup used in linear JSON mode).
var pending_graph_encounter: RivalEncounterData = null

## 2026-08-29 JSON-first architecture (Camil: "la carte JSON est la source de
## vérité absolue pour la structure de combats") — when a character has an
## exported map (PNG+JSON from Atelier Cartographe), CampaignMapNode builds a
## flat, ordered encounter list from the JSON case sequence + the branch
## encounter pools, then pushes it here via set_encounter_sequence().
## When non-empty, this list completely overrides the branch-formula logic in
## total_steps() / current_encounter(). Empty = branch-based fallback (all
## characters without a custom map continue to work exactly as before).
var encounter_sequence: Array = []  # of RivalEncounterData

## Cheat menu (2026-08-09, Camil: "tu aurais un sous menu 'cheat' de la
## campagne, pour que je puisse tester tous les twists ?") — bypasses
## campaign progression entirely: a throwaway RivalEncounterData built on
## the fly by CampaignCheatMenuNode, fought with no currency/unlock/progress
## side effects, bounced straight back to the cheat menu after.
var debug_encounter: RivalEncounterData = null

## Total tiles in the single world map. When encounter_sequence is populated
## (JSON-first characters), returns its length directly — that's exactly the
## number of combat cases from the JSON. Otherwise falls back to the branch
## formula (mini_branches.size() * 3 + 1) for characters without a map.
func total_steps() -> int:
	if not campaign:
		return 0
	if encounter_sequence.size() > 0:
		return encounter_sequence.size()
	return campaign.mini_branches.size() * 3 + 1

## Called by CampaignMapNode._build_tiles() when a character has a JSON map.
## seq is a flat, index-ordered list of RivalEncounterData built by consuming
## the branch encounter pools in JSON case order (see campaign_map_node.gd).
func set_encounter_sequence(seq: Array) -> void:
	encounter_sequence = seq

func is_organizer_fight() -> bool:
	if debug_encounter or not campaign:
		return false
	if is_graph_mode:
		# Graph mode: check whether the pending encounter IS the organizer's
		# (set by CampaignMapNode._confirm_selection() before the fight scene).
		return pending_graph_encounter != null \
			and pending_graph_encounter == campaign.organizer_encounter
	return campaign_step == total_steps() - 1

func has_pending_encounter() -> bool:
	return campaign != null and (debug_encounter != null or campaign_step < total_steps())

## The RivalEncounterData for whatever should be fought right now, given
## campaign_step (or the cheat-menu debug fight). Null once campaign_step
## has already reached total_steps() (nothing left to fight).
## When encounter_sequence is set (JSON-first characters), reads directly from
## that flat list; otherwise uses the branch formula as before.
func current_encounter() -> RivalEncounterData:
	if debug_encounter:
		return debug_encounter
	if not campaign:
		return null
	if is_graph_mode:
		# Graph mode: the encounter was set by CampaignMapNode._confirm_selection()
		# right before the scene change; it's valid until return_to_map() clears it.
		return pending_graph_encounter
	if campaign_step < 0 or campaign_step >= total_steps():
		return null
	if encounter_sequence.size() > 0:
		return encounter_sequence[campaign_step]
	# Branch-based fallback for characters without a JSON map
	if campaign_step == total_steps() - 1:
		return campaign.organizer_encounter
	var branch: MiniBranchData = campaign.mini_branches[campaign_step / 3]
	match campaign_step % 3:
		0:
			return branch.mook_1
		1:
			return branch.mook_2
		_:
			return branch.rival

## The branch the current step belongs to, or null for the organizer/a debug
## fight, or null in JSON-first mode (encounter_sequence set) where the branch
## structure no longer maps to campaign_step. Used by the map/HUD label only
## when valid — callers must null-check.
func current_branch() -> MiniBranchData:
	if debug_encounter or not campaign or is_organizer_fight() or campaign_step < 0 or campaign_step >= total_steps():
		return null
	if encounter_sequence.size() > 0:
		return null  # JSON mode: no per-step branch mapping
	return campaign.mini_branches[campaign_step / 3]

func clear() -> void:
	campaign = null
	campaign_step = 0
	debug_encounter = null
	encounter_sequence = []
	is_graph_mode = false
	current_graph_node_id = ""
	pending_graph_encounter = null

## Same partial reset return_to_map() always did — clears the transient
## debug-fight state without touching campaign/campaign_step, so whichever
## screen this returns to (always CampaignMap now) still knows which
## character's map and how far along it to show.
## Graph mode: current_graph_node_id is preserved so CampaignMap can restore
## the token at the same node after a loss. pending_graph_encounter is cleared
## (the fight is over — resolved or not — so the "pending" state is done).
func return_to_map() -> void:
	debug_encounter = null
	pending_graph_encounter = null
	# current_graph_node_id intentionally kept — CampaignMapNode reads it
	# to place the token at the last-fought node on reload.

## Cheat menu — fight a specific opponent with a specific twist (or no
## twist) active, full HP both sides, no campaign progression touched.
func start_debug_fight(campaign_data: CampaignData, encounter: RivalEncounterData) -> void:
	campaign = campaign_data
	debug_encounter = encounter

## Called once by CampaignMapNode._ready() after reading CampaignSave's
## persisted progress for this character — the single entry point into a
## real (non-debug) campaign run.
func enter_campaign(campaign_data: CampaignData, step: int) -> void:
	campaign = campaign_data
	campaign_step = step
	debug_encounter = null

## Called after winning the current step's fight.
func advance_step() -> void:
	campaign_step += 1
