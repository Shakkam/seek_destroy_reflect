class_name CampaignCharacterSelectNode
extends Node2D

## Epic 4 — lightweight single-player character pick for campaign mode,
## distinct from CharacterSelectNode (which picks 2 players for a 1v1).
## Only characters with an authored CampaignData resource are selectable;
## authoring the other 7 rosters' campaigns is content work, tracked
## separately from this story's engineering scope (only Vif's campaign is
## authored so far, to prove the system end-to-end).

const CAMPAIGNS := {
	"vif": preload("res://data/campaigns/vif_campaign.tres"),
	# lourd / controleur / mitrailleur / zoneur / perturbateur / missiles / mini:
	# not authored yet — content work, not an engineering gap.
}

const CHARACTERS := [ # of CharacterData — same roster order as CharacterSelectNode
	preload("res://data/characters/lourd.tres"),
	preload("res://data/characters/controleur.tres"),
	preload("res://data/characters/mitrailleur.tres"),
	preload("res://data/characters/vif.tres"),
	preload("res://data/characters/zoneur.tres"),
	preload("res://data/characters/perturbateur.tres"),
	preload("res://data/characters/missiles.tres"),
	preload("res://data/characters/mini.tres"),
]

@onready var list_label: Label = $ListLabel

var _selected_index := 0
var _move_prev := 0.0
var _confirm_prev := true # seeded true — see CampaignMapNode's note (2026-08-08 bug: carried-over held key insta-confirms frame 1)

func _ready() -> void:
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
		_selected_index = wrapi(_selected_index + step, 0, CHARACTERS.size())
		_refresh()
	_move_prev = move

	var confirm := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	if confirm and not _confirm_prev:
		_confirm_selection()
	_confirm_prev = confirm

func _refresh() -> void:
	var lines := []
	for i in CHARACTERS.size():
		var character: CharacterData = CHARACTERS[i]
		var marker := "> " if i == _selected_index else "  "
		var suffix := "" if CAMPAIGNS.has(character.id) else " [bientot disponible]"
		lines.append("%s%s%s" % [marker, character.display_name, suffix])
	list_label.text = "\n".join(lines)

func _confirm_selection() -> void:
	var character: CharacterData = CHARACTERS[_selected_index]
	if not CAMPAIGNS.has(character.id):
		return
	CampaignContext.campaign = CAMPAIGNS[character.id]
	get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
