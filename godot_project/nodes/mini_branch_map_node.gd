class_name MiniBranchMapNode
extends Node2D

## Epic 4 — visible per-branch progress map (2026-08-08 UX request, Camil:
## "il est temps de faire une mini map ... petit carré match, flèche, petit
## carré match, flèche, petit carré match contre le vrai 'joueur' avec le
## twist"). Shown before the branch's first fight and again between each
## fight, instead of silently reloading straight into the next one — the
## previous approach was mechanically correct (verified headlessly) but
## illegible: nothing on screen told the player they'd actually advanced.
##
## No backtracking: CampaignContext.branch_step only ever increases
## (advance_branch_step()), so there's nothing to navigate here — the
## player just confirms to fight whichever step is next.

@onready var title_label: Label = $TitleLabel
@onready var node1_label: Label = $Node1
@onready var arrow1_label: Label = $Arrow1
@onready var node2_label: Label = $Node2
@onready var arrow2_label: Label = $Arrow2
@onready var node3_label: Label = $Node3
@onready var hint_label: Label = $HintLabel

var _confirm_prev := true # seeded true — same carryover guard as CampaignMapNode (2026-08-08 bug)

func _ready() -> void:
	if not CampaignContext.branch:
		# Reached without a branch chosen first (e.g. editor testing) —
		# bounce back rather than crash. Deferred: see CampaignMapNode's
		# note on why a synchronous change_scene_to_file() from _ready()
		# errors ("Parent node is busy adding/removing children").
		get_tree().change_scene_to_file.call_deferred("res://scenes/CampaignMap.tscn")
		return
	title_label.text = CampaignContext.branch.display_name
	_refresh()

func _process(_delta: float) -> void:
	var confirm := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	if confirm and not _confirm_prev:
		get_tree().change_scene_to_file("res://scenes/MatchArena.tscn")
	_confirm_prev = confirm

func _refresh() -> void:
	node1_label.text = _node_text(0, "Sous-adversaire 1")
	node2_label.text = _node_text(1, "Sous-adversaire 2")
	var rival_text := "Rival"
	if CampaignContext.branch.rival.twist:
		rival_text += "\n(%s)" % CampaignContext.branch.rival.twist.display_name
	node3_label.text = _node_text(2, rival_text)
	hint_label.text = "Espace/Entree : combattre" if CampaignContext.branch_step < 3 else ""

func _node_text(index: int, label: String) -> String:
	var step := CampaignContext.branch_step
	if index < step:
		return "[X]\n%s" % label # done
	elif index == step:
		return ">>\n%s\n<<" % label # current — about to fight this one
	else:
		return "[ ]\n%s" % label # not reached yet
