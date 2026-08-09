class_name CampaignCheatMenuNode
extends Node2D

## Cheat menu (2026-08-09, Camil: "tu aurais un sous menu 'cheat' de la
## campagne, pour que je puisse tester tous les twists ?") — a dev/debug
## tool, not part of the normal campaign flow. Jumps directly into a match
## with any TwistData active (or none, "Aucun twist") against any opponent
## character, full HP both sides. No currency/unlock/branch_step side
## effects — see CampaignContext.start_debug_fight() and
## MatchArenaNode._resolve_campaign_result()'s debug_encounter branch, which
## bounces straight back here after the match so twists can be swapped and
## re-tested immediately.
##
## Only Vif's campaign is authored so far (see CampaignCharacterSelectNode),
## so the player's own character always follows whatever CampaignContext.
## campaign is already set to (or defaults to Vif) — picking the PLAYER's
## character isn't in scope here, only the twist and the opponent.

const CHARACTERS := CampaignCharacterSelectNode.CHARACTERS # reuse the same 8-character roster

@onready var title_label: Label = $TitleLabel
@onready var twist_list_label: Label = $TwistListLabel
@onready var opponent_label: Label = $OpponentLabel
@onready var hint_label: Label = $HintLabel

var _twists: Array = [] # of TwistData; index 0 is always null ("Aucun twist")
var _twist_index := 0
var _opponent_index := 0
var _move_prev := 0.0
var _side_move_prev := 0.0
var _confirm_prev := true # seeded true — same held-key carryover guard as every other menu (2026-08-08 bug pattern)

func _ready() -> void:
	title_label.text = "Cheat menu — tester un twist"
	_twists = [null]
	var dir := DirAccess.open("res://data/twists")
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				var twist: TwistData = load("res://data/twists/%s" % file_name)
				if twist:
					_twists.append(twist)
			file_name = dir.get_next()
		dir.list_dir_end()
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
		_twist_index = wrapi(_twist_index + step, 0, _twists.size())
		_refresh()
	_move_prev = move

	var side_move := 0.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		side_move += 1.0
	if Input.is_physical_key_pressed(KEY_LEFT):
		side_move -= 1.0
	var stick_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if absf(stick_x) > 0.3:
		side_move = stick_x
	if absf(side_move) > 0.5 and absf(_side_move_prev) <= 0.5:
		var step := 1 if side_move > 0.0 else -1
		_opponent_index = wrapi(_opponent_index + step, 0, CHARACTERS.size())
		_refresh()
	_side_move_prev = side_move

	var confirm := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	if confirm and not _confirm_prev:
		_launch()
	_confirm_prev = confirm

	if Input.is_physical_key_pressed(KEY_ESCAPE):
		get_tree().change_scene_to_file("res://scenes/CampaignMap.tscn")

func _refresh() -> void:
	var lines := []
	for i in _twists.size():
		var marker := "> " if i == _twist_index else "  "
		var twist: TwistData = _twists[i]
		var twist_name := twist.display_name if twist else "Aucun twist"
		lines.append("%s%s" % [marker, twist_name])
	twist_list_label.text = "\n".join(lines)
	var opponent: CharacterData = CHARACTERS[_opponent_index]
	opponent_label.text = "<  Adversaire : %s  >" % opponent.display_name
	hint_label.text = "Haut/Bas : twist — Gauche/Droite : adversaire — Espace : lancer — Echap : retour"

func _launch() -> void:
	var campaign_data: CampaignData = CampaignContext.campaign if CampaignContext.campaign else CampaignCharacterSelectNode.CAMPAIGNS["vif"]
	var encounter := RivalEncounterData.new()
	encounter.opponent = CHARACTERS[_opponent_index]
	encounter.is_mook = false
	encounter.twist = _twists[_twist_index]
	CampaignContext.start_debug_fight(campaign_data, encounter)
	get_tree().change_scene_to_file("res://scenes/MatchArena.tscn")
