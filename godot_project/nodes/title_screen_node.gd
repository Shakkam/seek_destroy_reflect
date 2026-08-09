class_name TitleScreenNode
extends Node2D

## Front door of the game (2026-08-06 — prepping a build to show on a
## friend's portal, the game previously booted straight into character
## select with no title/branding at all). Purely presentational: no
## gameplay state beyond which menu entry is highlighted.
##
## 2026-08-09 rework (Camil): a proper 3-entry menu instead of two bare key
## prompts — "Nouvelle partie" / "Continuer la partie" / "Mode Versus".
## "Nouvelle partie" warns ("la progression en cours sera perdue") and wipes
## the save before starting fresh, but only if there's actually a save to
## lose. Same Up/Down + confirm scheme as every other menu in the project
## (CampaignMapNode, CampaignCharacterSelectNode, ...).

@onready var menu_label: Label = $MenuLabel
@onready var popup_label: Label = $PopupLabel
@onready var hint_label: Label = $HintLabel

const MENU_ENTRIES := ["Nouvelle partie", "Continuer la partie", "Mode Versus"]
const CONFIRM_ENTRIES := ["Oui, recommencer", "Non, annuler"]

enum State { MENU, CONFIRM_RESET }

var _state := State.MENU
var _menu_index := 0
var _confirm_index := 1 # defaults to "Non" — an accidental double-press must never wipe a save
var _move_prev := 0.0
var _confirm_prev := true # seeded true — same held-key carryover guard as every other menu (2026-08-08 bug pattern)

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
		if _state == State.MENU:
			_menu_index = wrapi(_menu_index + step, 0, MENU_ENTRIES.size())
		else:
			_confirm_index = wrapi(_confirm_index + step, 0, CONFIRM_ENTRIES.size())
		_refresh()
	_move_prev = move

	var confirm := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4 \
		or Input.get_joy_axis(1, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	if confirm and not _confirm_prev:
		if _state == State.MENU:
			_confirm_menu_selection()
		else:
			_confirm_reset_choice()
	_confirm_prev = confirm

func _refresh() -> void:
	if _state == State.CONFIRM_RESET:
		popup_label.text = "Attention : la progression en cours sera perdue."
		var lines := []
		for i in CONFIRM_ENTRIES.size():
			var marker := "> " if i == _confirm_index else "  "
			lines.append("%s%s" % [marker, CONFIRM_ENTRIES[i]])
		menu_label.text = "\n".join(lines)
		hint_label.text = "Haut/Bas : naviguer — Espace/Entrée : valider"
		return

	popup_label.text = ""
	var has_save := CampaignSave.has_any_progress()
	var lines := []
	for i in MENU_ENTRIES.size():
		var marker := "> " if i == _menu_index else "  "
		var suffix := ""
		if i == 1 and not has_save:
			suffix = " [aucune sauvegarde]"
		lines.append("%s%s%s" % [marker, MENU_ENTRIES[i], suffix])
	menu_label.text = "\n".join(lines)
	hint_label.text = "Haut/Bas : naviguer — Espace/Entrée : valider"

func _confirm_menu_selection() -> void:
	match _menu_index:
		0: # Nouvelle partie
			if CampaignSave.has_any_progress():
				_state = State.CONFIRM_RESET
				_confirm_index = 1 # default to "Non" — see var declaration
				_refresh()
			else:
				get_tree().change_scene_to_file("res://scenes/CampaignCharacterSelect.tscn")
		1: # Continuer la partie
			var character_id := CampaignSave.character_with_progress()
			if character_id == "":
				return # nothing to resume — no-op, matches CampaignMapNode's locked-entry convention
			if not CampaignCharacterSelectNode.CAMPAIGNS.has(character_id):
				return # save exists for a character whose campaign isn't authored (shouldn't happen)
			CampaignContext.campaign = CampaignCharacterSelectNode.CAMPAIGNS[character_id]
			get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")
		2: # Mode Versus
			get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")

func _confirm_reset_choice() -> void:
	if _confirm_index == 0: # Oui, recommencer
		CampaignSave.reset_all()
		get_tree().change_scene_to_file("res://scenes/CampaignCharacterSelect.tscn")
	else: # Non, annuler
		_state = State.MENU
		_refresh()
