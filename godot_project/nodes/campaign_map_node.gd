class_name CampaignMapNode
extends Node2D

## Epic 4, Story 4.2/4.3 — the campaign map: a node list for the character
## in CampaignContext.campaign (Soul Calibur IV branching-map reference,
## UX-DR1). Simplified to a keyboard-navigable list rather than the full
## visual branching-path rendering, consistent with the project's existing
## placeholder-UI convention (CharacterSelectNode) — same data/flow
## underneath, so richer map art can replace just the rendering later.
##
## Story 4.3's resolution applies: no mini-branch's completion is a
## prerequisite for another (fully free order), but once inside one, its
## mook_1 -> mook_2 -> rival sequence is fixed (see CampaignContext).

@onready var title_label: Label = $TitleLabel
@onready var currency_label: Label = $CurrencyLabel
@onready var list_label: Label = $ListLabel
@onready var description_label: Label = $DescriptionLabel
@onready var background: ColorRect = $Background

# Story 4.7 — the organizer's motif "bleeding" into the map as the player
# approaches the final node, environmental storytelling instead of a text
# announcement (2026-08-07 brainstorm, Constraint Injection). Matches the
# organizer's current stand-in character tint (Perturbateur, see
# data/campaigns/vif/organizer_encounter.tres — no dedicated organizer art yet).
const BASE_BG_COLOR := Color(0.07, 0.09, 0.15, 1.0)
const ORGANIZER_MOTIF_COLOR := Color(0.6, 0.8, 1.0, 1.0) # same pale-blue as the stun tint, echoes Perturbateur

var _selected_index := 0
var _nodes: Array = [] # of MiniBranchData
var _move_prev := 0.0
# Seeded true, not false (2026-08-08 bug report: arriving here still holding
# the Fire button from the match that just ended instantly re-triggered
# _confirm_selection() on frame 1 — re-launching branch 0 before the map was
# ever visible, which read as "no map at all" + "always the same match").
# True means "was already pressed" so the first frame can never (mis)fire;
# it naturally settles once the button is actually released.
var _confirm_prev := true
var _cheat_prev := false # cheat menu hotkey (2026-08-09) — no carryover risk, "T" isn't shared with any other screen's confirm key

func _ready() -> void:
	if not CampaignContext.campaign:
		# Reached directly (e.g. editor testing) without picking a campaign
		# first — bounce back rather than crash on a null campaign. Deferred:
		# changing scene synchronously from inside _ready() (still mid
		# scene-tree setup) errors ("Parent node is busy adding/removing
		# children"), caught via headless boot-check.
		get_tree().change_scene_to_file.call_deferred("res://scenes/CampaignCharacterSelect.tscn")
		return
	_nodes = CampaignContext.campaign.mini_branches.duplicate()
	title_label.text = CampaignContext.campaign.character.display_name
	_refresh()

func _process(_delta: float) -> void:
	var move := 0.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		move += 1.0
	if Input.is_physical_key_pressed(KEY_UP):
		move -= 1.0
	var stick_y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if absf(stick_y) > 0.3:
		move = stick_y
	if absf(move) > 0.5 and absf(_move_prev) <= 0.5:
		var step := 1 if move > 0.0 else -1
		_selected_index = wrapi(_selected_index + step, 0, _nodes.size() + 1) # +1 for the organizer node
		_refresh()
	_move_prev = move

	var confirm := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	if confirm and not _confirm_prev:
		_confirm_selection()
	_confirm_prev = confirm

	# Cheat menu (2026-08-09, Camil: "tu aurais un sous menu 'cheat' de la
	# campagne, pour que je puisse tester tous les twists ?") — dev/debug
	# entry point, physical "T" (Test), same "physical key" convention as
	# the rest of the project so it's unaffected by AZERTY/QWERTY labeling.
	if Input.is_physical_key_pressed(KEY_T) and not _cheat_prev:
		get_tree().change_scene_to_file("res://scenes/CampaignCheatMenu.tscn")
	_cheat_prev = Input.is_physical_key_pressed(KEY_T)

func _organizer_unlocked() -> bool:
	var character_id: String = CampaignContext.campaign.character.id
	return CampaignSave.completed_branch_count(character_id) >= CampaignContext.campaign.required_branch_count

func _refresh() -> void:
	var character_id: String = CampaignContext.campaign.character.id
	currency_label.text = "Gold: %d" % CampaignSave.get_currency(character_id)

	# Story 4.7 — the closer to unlocking the organizer, the more its motif
	# bleeds into the map's own background.
	var progress := float(CampaignSave.completed_branch_count(character_id)) / float(CampaignContext.campaign.required_branch_count)
	background.color = BASE_BG_COLOR.lerp(ORGANIZER_MOTIF_COLOR, clampf(progress, 0.0, 1.0) * 0.35)

	var lines := []
	for i in _nodes.size():
		var branch: MiniBranchData = _nodes[i]
		var marker := "> " if i == _selected_index else "  "
		var status := "[fait]" if CampaignSave.is_branch_completed(character_id, branch.id) else ""
		lines.append("%s%s %s" % [marker, branch.display_name, status])

	var organizer_marker := "> " if _selected_index == _nodes.size() else "  "
	var organizer_line := "%sOrganisateur du tournoi" % organizer_marker
	if not _organizer_unlocked():
		organizer_line += " [verrouille]" # silhouette-in-fog substitute — no art yet
	lines.append(organizer_line)
	list_label.text = "\n".join(lines)

	if _selected_index < _nodes.size():
		var branch: MiniBranchData = _nodes[_selected_index]
		description_label.text = "Mini-branche : %s\n2 combats d'echauffement, puis le rival." % branch.display_name
	elif _organizer_unlocked():
		description_label.text = "Combat final contre l'organisateur du tournoi."
	else:
		description_label.text = "Complete %d mini-branches pour debloquer ce combat (%d/%d actuellement)." % [
			CampaignContext.campaign.required_branch_count,
			CampaignSave.completed_branch_count(character_id),
			CampaignContext.campaign.required_branch_count,
		]
	description_label.text += "\n\n(T : menu cheat — tester un twist)"

func _confirm_selection() -> void:
	var character_id: String = CampaignContext.campaign.character.id
	if _selected_index < _nodes.size():
		var branch: MiniBranchData = _nodes[_selected_index]
		if CampaignSave.is_branch_completed(character_id, branch.id):
			return # re-fighting a completed branch isn't part of this pass's scope
		CampaignContext.start_branch(CampaignContext.campaign, branch)
		get_tree().change_scene_to_file("res://scenes/MiniBranchMap.tscn") # visible per-branch progress (2026-08-08 UX request) instead of jumping straight into a fight
	elif _organizer_unlocked():
		CampaignContext.start_organizer_fight(CampaignContext.campaign)
		get_tree().change_scene_to_file("res://scenes/MatchArena.tscn")
