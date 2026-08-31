class_name CampaignCharacterSelectNode
extends Node2D

## Epic 4 — lightweight single-player character pick for campaign mode,
## distinct from CharacterSelectNode (which picks 2 players for a 1v1).
## Only characters with an authored CampaignData resource are selectable.
## 2026-08-16: full roster authored — Vif's campaign (2026-08-13) proved
## the system end-to-end; the other 7 (data/campaigns/<id>_campaign.tres)
## follow the exact same template (4 branches, 2 mooks + 1 real rival with
## a twist each, required_branch_count=3, an organizer fight with the
## energy_orb_pickup signature twist), generated in bulk rather than
## hand-authored one file at a time — see [[campaign-content-2026-08-16]]
## project memory for the branch/organizer/twist assignment table.
const CAMPAIGNS := {
	"vif": preload("res://data/campaigns/vif_campaign.tres"),
	"lourd": preload("res://data/campaigns/lourd_campaign.tres"),
	"controleur": preload("res://data/campaigns/controleur_campaign.tres"),
	"mitrailleur": preload("res://data/campaigns/mitrailleur_campaign.tres"),
	"zoneur": preload("res://data/campaigns/zoneur_campaign.tres"),
	"perturbateur": preload("res://data/campaigns/perturbateur_campaign.tres"),
	"missiles": preload("res://data/campaigns/missiles_campaign.tres"),
	"mini": preload("res://data/campaigns/mini_campaign.tres"),
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
	# Bug report (Camil, 2026-08-31, re: Ben's playtest — "les fleches,
	# c'est uniquement J2", every menu/map is a solo screen and should
	# accept J1's own WASD too, not arrows only).
	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
		move += 1.0
	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
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

	# 2026-08-18 (Camil: "dans les menus, quand je fais Echap, que ca
	# revienne en arriere") — one-shot, no edge-guard needed (same as
	# CampaignCheatMenuNode's own Escape handling): the scene changes
	# immediately, so a held key can't double-fire.
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")

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
	# 2026-08-18 — the title theme (TitleMusic autoload) plays on through
	# this whole screen; stop it here, leaving for real campaign gameplay.
	TitleMusic.stop()
	get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
