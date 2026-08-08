class_name CharacterSelectNode
extends Node2D

## Story 2.3 — local character-select screen shown before the pre-match
## "ready?" gate (Epic 1's MatchArenaNode). Both players pick independently
## and locally (no networking — that's Epic 3); picks are handed off to
## MatchArena via the MatchSetup autoload.

const CHARACTERS := [ # of CharacterData — order matches the Epic 2 roster table
	preload("res://data/characters/lourd.tres"),
	preload("res://data/characters/controleur.tres"),
	preload("res://data/characters/mitrailleur.tres"),
	preload("res://data/characters/vif.tres"),
	preload("res://data/characters/zoneur.tres"),
	preload("res://data/characters/perturbateur.tres"),
	preload("res://data/characters/missiles.tres"),
	preload("res://data/characters/mini.tres"),
]

const GAMEPAD_STICK_DEADZONE := 0.25
const GAMEPAD_TRIGGER_THRESHOLD := 0.4

@onready var p1_list: Label = $P1List
@onready var p2_list: Label = $P2List
@onready var p1_status: Label = $P1Status
@onready var p2_status: Label = $P2Status

var _p1_index := 0
var _p2_index := 1
var _p1_confirmed := false
var _p2_confirmed := false

var _p1_move_prev := 0.0
var _p2_move_prev := 0.0
# Seeded true — same fix as CampaignMapNode (2026-08-08 bug report): P1's
# confirm key here (Space) is the same key used to arrive from TitleScreen,
# so a held-over press could instantly auto-confirm P1 on index 0 before
# the screen was ever seen. True means "already pressed", so frame 1 can
# never (mis)fire; it settles to the real state once actually released.
var _p1_confirm_prev := true
var _p2_confirm_prev := true

func _ready() -> void:
	_refresh_labels()

func _process(_delta: float) -> void:
	if not _p1_confirmed:
		_process_player(1)
	if not _p2_confirmed:
		_process_player(2)
	if _p1_confirmed and _p2_confirmed:
		_start_match()

func _process_player(player_index: int) -> void:
	var device := player_index - 1
	var move := 0.0
	if player_index == 1:
		if Input.is_physical_key_pressed(KEY_D):
			move += 1.0
		if Input.is_physical_key_pressed(KEY_A):
			move -= 1.0
	else:
		if Input.is_physical_key_pressed(KEY_RIGHT):
			move += 1.0
		if Input.is_physical_key_pressed(KEY_LEFT):
			move -= 1.0
	var stick_x := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	if absf(stick_x) > GAMEPAD_STICK_DEADZONE:
		move = stick_x

	var move_prev := _p1_move_prev if player_index == 1 else _p2_move_prev
	if absf(move) > 0.5 and absf(move_prev) <= 0.5:
		var step := 1 if move > 0.0 else -1
		if player_index == 1:
			_p1_index = wrapi(_p1_index + step, 0, CHARACTERS.size())
		else:
			_p2_index = wrapi(_p2_index + step, 0, CHARACTERS.size())
		_refresh_labels()
	if player_index == 1:
		_p1_move_prev = move
	else:
		_p2_move_prev = move

	var confirm := false
	if player_index == 1:
		confirm = Input.is_physical_key_pressed(KEY_SPACE)
	else:
		confirm = Input.is_physical_key_pressed(KEY_ENTER)
	if Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > GAMEPAD_TRIGGER_THRESHOLD:
		confirm = true

	var confirm_prev := _p1_confirm_prev if player_index == 1 else _p2_confirm_prev
	if confirm and not confirm_prev:
		if player_index == 1:
			_p1_confirmed = true
			p1_status.text = "PRET !"
		else:
			_p2_confirmed = true
			p2_status.text = "PRET !"
	if player_index == 1:
		_p1_confirm_prev = confirm
	else:
		_p2_confirm_prev = confirm

func _refresh_labels() -> void:
	p1_list.text = _roster_text(_p1_index)
	p2_list.text = _roster_text(_p2_index)

func _roster_text(selected_index: int) -> String:
	var lines := []
	for i in CHARACTERS.size():
		var character: CharacterData = CHARACTERS[i]
		var marker := "> " if i == selected_index else "  "
		lines.append("%s%s (%s)" % [marker, character.display_name, character.archetype])
	return "\n".join(lines)

func _start_match() -> void:
	MatchSetup.p1_character = CHARACTERS[_p1_index]
	MatchSetup.p2_character = CHARACTERS[_p2_index]
	get_tree().change_scene_to_file("res://scenes/MatchArena.tscn")
