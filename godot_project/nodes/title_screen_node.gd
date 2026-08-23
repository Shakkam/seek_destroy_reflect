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
@onready var title_word_seek: Label = $TitleWordSeek
@onready var title_word_and_destroy: Label = $TitleWordAndDestroy
@onready var title_bottom: Label = $TitleBottom

# 2026-08-16 (Camil, with 1.wav — "on y entend distinctement les 2 mots
# 'Seek and Destroy and Return the ball'. Ce serait bien que les mots
# arrivent petit a petit en meme temps [que la voix], en arrivant du haut,
# facon Street Fighter 2") — each piece slams down from off-screen at the
# moment it's actually heard in the track, landing with an overshoot + a
# squash/recover, the classic SF2 character-select-card impact. Timestamps
# given by ear, listening to the real track (2026-08-16): "Seek" => 2.5s,
# "and destroy" => 3.5s, "and return the ball" => 4.5s — three separate
# drops, not two; "SEEK AND DESTROY" (one Label before this) had to split
# into TitleWordSeek/TitleWordAndDestroy so the first two can land apart.
const TITLE_SEEK_DROP_TIME := 2.5
const TITLE_AND_DESTROY_DROP_TIME := 3.5
const TITLE_BOTTOM_DROP_TIME := 4.5 # "and return the ball"
const TITLE_WORD_GAP := 16.0 # px between "SEEK" and "AND DESTROY" once positioned side by side — see _position_title_words()
# 2026-08-16 playtest: "on voit les textes tout en haut. Il faut les
# planquer et les faire atterrir de dessus (X2 => X1, comme on a fait pour
# la pluie de missiles de lourd)" — TITLE_DROP_HEIGHT was a delta below
# each line's OWN resting Y, which for the top row left it only ~40px
# above the screen's own top edge (y=0) — still poking into view. A
# shared ABSOLUTE start Y instead (comfortably above y=0 for every line,
# regardless of where it rests) plus the same "starts big, shrinks to
# normal size while it falls" trick MissileStrikeNode already uses for
# Lourd's Pluie de Scuds (start_scale -> 1.0) — reads as falling from high
# up, not just sliding down from just off-frame.
const TITLE_START_Y := -160.0
const TITLE_START_SCALE := 2.0
const TITLE_DROP_DURATION := 0.35 # seconds — fast, a slam not a float
const TITLE_SQUASH_DURATION := 0.4
var _title_seek_rest_y: float
var _title_and_destroy_rest_y: float
var _title_bottom_rest_y: float

const MENU_ENTRIES := ["Nouvelle partie", "Continuer la partie", "Mode Versus"]
const CONFIRM_ENTRIES := ["Oui, recommencer", "Non, annuler"]

enum State { MENU, CONFIRM_RESET }

var _state := State.MENU
var _menu_index := 0
var _confirm_index := 1 # defaults to "Non" — an accidental double-press must never wipe a save
var _move_prev := 0.0
var _confirm_prev := true # seeded true — same held-key carryover guard as every other menu (2026-08-08 bug pattern)
var _escape_prev := false

# 2026-08-16 UX audit (Sally): "'Continuer la partie' is selectable with
# nothing to continue" — confirming it with no save used to be a silent
# no-op (return, nothing else). Reuses popup_label (already there for the
# reset-confirm warning) for a brief denied message instead.
const DENIED_MESSAGE_DURATION := 1.2
var _denied_timer := 0.0

func _ready() -> void:
	_refresh()
	_position_title_words()
	_title_seek_rest_y = title_word_seek.position.y
	_title_and_destroy_rest_y = title_word_and_destroy.position.y
	_title_bottom_rest_y = title_bottom.position.y
	# Scale from here on out is always around each label's own center, not
	# its top-left corner — set once, doesn't change across loops.
	title_word_seek.pivot_offset = title_word_seek.size * 0.5
	title_word_and_destroy.pivot_offset = title_word_and_destroy.size * 0.5
	title_bottom.pivot_offset = title_bottom.size * 0.5
	# 2026-08-18 — theme music now lives in the TitleMusic autoload (see its
	# own doc comment) so it survives the change_scene_to_file() into
	# character select instead of being destroyed with this scene.
	TitleMusic.looped.connect(_on_music_looped)
	TitleMusic.start()

## "SEEK" and "AND DESTROY" are two independent Labels now (so they can
## land at different moments — see the timestamp comment above) but still
## need to read as one centered line together. Measures each word's real
## rendered width off its own font/size rather than guessing fixed
## offsets, so this stays correct if the font, size, or wording ever
## changes. Runs once — the two words' X position/width never change,
## only their Y animates.
func _position_title_words() -> void:
	var font := title_word_seek.get_theme_font("font")
	var font_size := title_word_seek.get_theme_font_size("font_size")
	var seek_width := font.get_string_size(title_word_seek.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var and_destroy_width := font.get_string_size(title_word_and_destroy.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var total_width := seek_width + TITLE_WORD_GAP + and_destroy_width
	var start_x := (1280.0 - total_width) / 2.0
	title_word_seek.position.x = start_x
	title_word_seek.size.x = seek_width
	title_word_and_destroy.position.x = start_x + seek_width + TITLE_WORD_GAP
	title_word_and_destroy.size.x = and_destroy_width

## Re-arms the three title-word slam-ins against the music's own playback
## clock (TitleMusic.looped fires on both the initial start AND every
## subsequent loop) — so if the player is still sitting on the title screen
## when the track loops, the entrance replays too instead of only ever
## happening once.
func _on_music_looped() -> void:
	_reset_title_word_to_start(title_word_seek)
	_reset_title_word_to_start(title_word_and_destroy)
	_reset_title_word_to_start(title_bottom)
	get_tree().create_timer(TITLE_SEEK_DROP_TIME).timeout.connect(_drop_title_line.bind(title_word_seek, _title_seek_rest_y))
	get_tree().create_timer(TITLE_AND_DESTROY_DROP_TIME).timeout.connect(_drop_title_line.bind(title_word_and_destroy, _title_and_destroy_rest_y))
	get_tree().create_timer(TITLE_BOTTOM_DROP_TIME).timeout.connect(_drop_title_line.bind(title_bottom, _title_bottom_rest_y))

func _reset_title_word_to_start(label: Label) -> void:
	label.position.y = TITLE_START_Y
	label.scale = Vector2(TITLE_START_SCALE, TITLE_START_SCALE)

## The slam: position and scale fall together (position overshoots past
## rest_y and springs back via TRANS_BACK/EASE_OUT — the punchy part;
## scale eases plainly down to 1.0 via TRANS_QUAD so "getting closer"
## reads clean, without also fighting the position bounce for attention),
## landing into a squash that snaps back to normal scale (TRANS_ELASTIC)
## — same one-two as an SF2 character card impact.
func _drop_title_line(label: Label, rest_y: float) -> void:
	if not is_instance_valid(label):
		return # scene changed while this SceneTreeTimer was still pending
	var drop_tween := label.create_tween()
	drop_tween.set_parallel(true)
	drop_tween.tween_property(label, "position:y", rest_y, TITLE_DROP_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	drop_tween.tween_property(label, "scale", Vector2.ONE, TITLE_DROP_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	drop_tween.finished.connect(_impact_squash.bind(label))

func _impact_squash(label: Label) -> void:
	if not is_instance_valid(label):
		return
	label.scale = Vector2(1.18, 0.7) # flattened wide on impact — pivot_offset is already centered, set once in _ready()
	var squash_tween := label.create_tween()
	squash_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	squash_tween.tween_property(label, "scale", Vector2.ONE, TITLE_SQUASH_DURATION)

func _process(delta: float) -> void:
	if _denied_timer > 0.0:
		_denied_timer -= delta
		if _denied_timer <= 0.0:
			popup_label.text = ""

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

	# 2026-08-18 (Camil: "dans les menus, quand je fais Echap, que ca
	# revienne en arriere") — this screen has no PREVIOUS screen to leave
	# (it's the root), but its reset-confirm popup is itself a small
	# "menu" state; Escape here reads naturally as "cancel", same as
	# picking "Non, annuler". Edge-guarded (unlike the other screens'
	# Escape handlers) since this changes internal state, not the scene —
	# a held key must not re-fire it every frame.
	var escape := Input.is_physical_key_pressed(KEY_ESCAPE)
	if escape and not _escape_prev and _state == State.CONFIRM_RESET:
		_state = State.MENU
		_refresh()
	_escape_prev = escape

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
	_denied_timer = 0.0
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
				# 2026-08-16 UX audit (Sally): used to be a silent no-op here —
				# a mistimed confirm on a dead entry got zero feedback.
				popup_label.text = "Aucune sauvegarde a continuer."
				_denied_timer = DENIED_MESSAGE_DURATION
				return
			if not CampaignCharacterSelectNode.CAMPAIGNS.has(character_id):
				return # save exists for a character whose campaign isn't authored (shouldn't happen)
			CampaignContext.campaign = CampaignCharacterSelectNode.CAMPAIGNS[character_id]
			# "Continuer" skips character select entirely — the music should
			# keep playing through THAT screen (see CampaignCharacterSelectNode/
			# CharacterSelectNode's own stop() calls), but this path never
			# touches it at all, so stop here instead.
			TitleMusic.stop()
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
