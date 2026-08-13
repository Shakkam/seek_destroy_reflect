class_name CharacterSelectNode
extends Node2D

## Story 2.3 — local character-select screen shown before the pre-match
## "ready?" gate (Epic 1's MatchArenaNode). Both players pick independently
## and locally (no networking — that's Epic 3); picks are handed off to
## MatchArena via the MatchSetup autoload.
##
## 2026-08-12 redesign (Camil: "on avait dit 2 lignes de 4 persos
## (portraits) et quand on passe sur un perso, sa description arrive, avec
## image full ... Comme street fighter 2 en fait") — replaces the old
## scrolling text-list version. One shared 2x4 portrait grid (row-major,
## matches CHARACTERS' order); P1 and P2 move independent cursors over the
## SAME grid (own color each, can land on the same cell). Whichever
## character a player's cursor is on drives that player's side preview
## panel (name/archetype/weapon + a big full-body image). Real art drops
## in per-character as it's ready (see PORTRAIT_TEXTURES/FULL_TEXTURES
## below) — until then, a character falls back to a drawn placeholder
## (accent-tinted box + big initial), same "_draw() shapes" convention as
## CampaignMapNode.

const CHARACTERS := [ # of CharacterData — order matches the Epic 2 roster table AND the grid's row-major layout (row = i/GRID_COLS, col = i%GRID_COLS)
	preload("res://data/characters/lourd.tres"),
	preload("res://data/characters/controleur.tres"),
	preload("res://data/characters/mitrailleur.tres"),
	preload("res://data/characters/vif.tres"),
	preload("res://data/characters/zoneur.tres"),
	preload("res://data/characters/perturbateur.tres"),
	preload("res://data/characters/missiles.tres"),
	preload("res://data/characters/mini.tres"),
]

# Per-character accent color, from the GDD's character-portrait prompt
# table ("Accent" column) — used to tint the placeholder art until the
# real Gemini-generated portraits/big images are dropped in.
const ACCENT_COLORS := {
	"lourd": Color(0.85, 0.4, 0.15),
	"controleur": Color(0.6, 0.63, 0.68),
	"mitrailleur": Color(0.65, 0.78, 0.88),
	"vif": Color(0.15, 0.55, 1.0),
	"zoneur": Color(0.25, 0.9, 0.45),
	"perturbateur": Color(0.6, 0.5, 0.9),
	"missiles": Color(0.2, 0.85, 0.9), # Traqueur
	"mini": Color(1.0, 0.85, 0.2), # Spreader
}

const GRID_COLS := 4
const GRID_ROWS := 2
const CELL_SIZE := 110.0
const CELL_GAP := 22.0
const GRID_ORIGIN := Vector2(388.0, 200.0) # top-left of cell (0,0)

const P1_COLOR := Color(0.65, 0.9, 1, 1)
const P2_COLOR := Color(1, 0.55, 0.7, 1)

const BIG_IMAGE_P1_RECT := Rect2(60.0, 165.0, 250.0, 375.0) # left preview panel, ~2:3 per the GDD's "grande image" ratio
const BIG_IMAGE_P2_RECT := Rect2(970.0, 165.0, 250.0, 375.0) # right preview panel, mirrored

const GAMEPAD_STICK_DEADZONE := 0.25
const GAMEPAD_TRIGGER_THRESHOLD := 0.4

# Real portrait/full-body art, per character id — same "explicit preload +
# id lookup" pattern match_arena_node.gd uses for weapon sprites.
# 2026-08-13: full roster now has real art (all 8), so the placeholder
# path in _draw_grid_cell()/_draw_big_image() is dead code in practice —
# left in place as a safety net for any future 9th character/reroll.
const PORTRAIT_TEXTURES := {
	"lourd": preload("res://assets/art/characters/lourd/portrait.png"),
	"missiles": preload("res://assets/art/characters/missiles/portrait.png"), # Traqueur
	"controleur": preload("res://assets/art/characters/controleur/portrait.png"),
	"mitrailleur": preload("res://assets/art/characters/mitrailleur/portrait.png"),
	"zoneur": preload("res://assets/art/characters/zoneur/portrait.png"),
	"perturbateur": preload("res://assets/art/characters/perturbateur/portrait.png"),
	"mini": preload("res://assets/art/characters/mini/portrait.png"), # Spreader
	"vif": preload("res://assets/art/characters/vif/portrait.png"),
}
const FULL_TEXTURES := {
	"lourd": preload("res://assets/art/characters/lourd/full.png"),
	"missiles": preload("res://assets/art/characters/missiles/full.png"), # Traqueur
	"controleur": preload("res://assets/art/characters/controleur/full.png"),
	"mitrailleur": preload("res://assets/art/characters/mitrailleur/full.png"),
	"zoneur": preload("res://assets/art/characters/zoneur/full.png"),
	"perturbateur": preload("res://assets/art/characters/perturbateur/full.png"),
	"mini": preload("res://assets/art/characters/mini/full.png"), # Spreader
	"vif": preload("res://assets/art/characters/vif/full.png"),
}

@onready var p1_name_label: Label = $P1Name
@onready var p2_name_label: Label = $P2Name
@onready var p1_desc_label: Label = $P1Desc
@onready var p2_desc_label: Label = $P2Desc
@onready var p1_status: Label = $P1Status
@onready var p2_status: Label = $P2Status

var _p1_index := 0
var _p2_index := 1
var _p1_confirmed := false
var _p2_confirmed := false

var _p1_move_prev := Vector2.ZERO
var _p2_move_prev := Vector2.ZERO
# Seeded true — same fix as CampaignMapNode (2026-08-08 bug report): P1's
# confirm key here (Space) is the same key used to arrive from TitleScreen,
# so a held-over press could instantly auto-confirm P1 on index 0 before
# the screen was ever seen. True means "already pressed", so frame 1 can
# never (mis)fire; it settles to the real state once actually released.
var _p1_confirm_prev := true
var _p2_confirm_prev := true
var _pulse_time := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # keep pixel-art portraits crisp when scaled — same convention as ProjectileNode
	_refresh_labels()

func _process(delta: float) -> void:
	_pulse_time += delta
	queue_redraw() # cheap: a handful of rects/circles + a couple of labels' worth of text
	if not _p1_confirmed:
		_process_player(1)
	if not _p2_confirmed:
		_process_player(2)
	if _p1_confirmed and _p2_confirmed:
		_start_match()

func _process_player(player_index: int) -> void:
	var device := player_index - 1
	var move := Vector2.ZERO
	if player_index == 1:
		if Input.is_physical_key_pressed(KEY_D):
			move.x += 1.0
		if Input.is_physical_key_pressed(KEY_A):
			move.x -= 1.0
		if Input.is_physical_key_pressed(KEY_S):
			move.y += 1.0
		if Input.is_physical_key_pressed(KEY_W):
			move.y -= 1.0
	else:
		if Input.is_physical_key_pressed(KEY_RIGHT):
			move.x += 1.0
		if Input.is_physical_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_physical_key_pressed(KEY_DOWN):
			move.y += 1.0
		if Input.is_physical_key_pressed(KEY_UP):
			move.y -= 1.0
	var stick := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	if stick.length() > GAMEPAD_STICK_DEADZONE:
		move = stick

	var move_prev := _p1_move_prev if player_index == 1 else _p2_move_prev
	var index := _p1_index if player_index == 1 else _p2_index
	var moved := false
	if absf(move.x) > 0.5 and absf(move_prev.x) <= 0.5:
		index = _step_grid(index, 1 if move.x > 0.0 else -1, 0)
		moved = true
	if absf(move.y) > 0.5 and absf(move_prev.y) <= 0.5:
		index = _step_grid(index, 1 if move.y > 0.0 else -1, 1)
		moved = true
	if moved:
		if player_index == 1:
			_p1_index = index
		else:
			_p2_index = index
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

## Moves one cell along a single axis (row or col), wrapping — grid nav is
## 2D (SF2-style) instead of the old 1D left/right cycle.
func _step_grid(index: int, step: int, axis: int) -> int:
	var col := index % GRID_COLS
	var row := index / GRID_COLS
	if axis == 0:
		col = wrapi(col + step, 0, GRID_COLS)
	else:
		row = wrapi(row + step, 0, GRID_ROWS)
	return row * GRID_COLS + col

func _refresh_labels() -> void:
	var p1_character: CharacterData = CHARACTERS[_p1_index]
	var p2_character: CharacterData = CHARACTERS[_p2_index]
	p1_name_label.text = p1_character.display_name
	p2_name_label.text = p2_character.display_name
	p1_desc_label.text = _describe(p1_character)
	p2_desc_label.text = _describe(p2_character)

func _describe(character: CharacterData) -> String:
	var weapon_name := "?"
	if not character.kit.is_empty():
		weapon_name = character.kit[0].display_name
	return "%s\nArme : %s" % [character.archetype, weapon_name]

func _cell_position(index: int) -> Vector2:
	var col := index % GRID_COLS
	var row := index / GRID_COLS
	return GRID_ORIGIN + Vector2(col * (CELL_SIZE + CELL_GAP), row * (CELL_SIZE + CELL_GAP))

func _draw() -> void:
	for i in CHARACTERS.size():
		_draw_grid_cell(i)
	# Drawn AFTER every cell (not per-cell) so a frame is never partly
	# hidden behind a neighboring cell's own border, and P1/P2 nest at
	# different padding when both land on the same cell instead of
	# perfectly overlapping and reading as one.
	_draw_selection_frame(_cell_position(_p1_index), "J1", 6.0, P1_COLOR, _p1_confirmed)
	_draw_selection_frame(_cell_position(_p2_index), "J2", 12.0, P2_COLOR, _p2_confirmed)
	_draw_big_image(BIG_IMAGE_P1_RECT, CHARACTERS[_p1_index])
	_draw_big_image(BIG_IMAGE_P2_RECT, CHARACTERS[_p2_index])

func _draw_grid_cell(i: int) -> void:
	var character: CharacterData = CHARACTERS[i]
	var accent: Color = ACCENT_COLORS.get(character.id, Color(0.6, 0.6, 0.6))
	var pos := _cell_position(i)
	var rect := Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.22), true)
	draw_rect(rect, accent, false, 3.0)
	var portrait: Texture2D = PORTRAIT_TEXTURES.get(character.id)
	if portrait:
		_draw_texture_fit(portrait, rect, 6.0)
	else:
		_draw_placeholder_initial(character.display_name, pos + Vector2(CELL_SIZE, CELL_SIZE) / 2.0, 40, accent)
	_draw_centered_text(character.display_name, pos + Vector2(CELL_SIZE / 2.0, CELL_SIZE + 16.0), 15, Color(0.9, 0.91, 0.97))

## The bold player cursor — a thick rectangular frame with outward corner
## ticks (HUD "target lock" look), NOT a thin arc. 2026-08-12: the
## original arc read as near-invisible next to each cell's own permanent
## accent-colored border (a headless input-simulation test proved the
## cursor's underlying index genuinely moves every press — see
## tests/character_select_nav_check.gd — the bug was purely that the old
## cursor didn't read as a cursor). Padding differs per player so two
## cursors on the same cell nest instead of perfectly overlapping.
##
## 2026-08-12 v2 (Sally's review, playtest screenshot): with the tag
## floating ABOVE the frame and P2's old 18px pad, two players on
## vertically-adjacent cells (P1 on the cell directly below P2's) had
## the "J1"/"J2" tags collide right in the gap between the two cells —
## read as "J1" labeling the wrong (upper) character. Fixed two ways:
## padding shrunk so it can never eat the whole CELL_GAP, and the tag now
## sits INSIDE the frame's top-left corner instead of floating above it,
## so it can never land in the seam between two rows regardless of pad.
func _draw_selection_frame(pos: Vector2, tag: String, base_pad: float, color: Color, confirmed: bool) -> void:
	var pad := base_pad if confirmed else base_pad + sin(_pulse_time * 4.0) * 3.0
	var rect := Rect2(pos - Vector2(pad, pad), Vector2(CELL_SIZE, CELL_SIZE) + Vector2(pad, pad) * 2.0)
	draw_rect(rect, color, false, 5.0)
	_draw_corner_ticks(rect, color)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(6.0, 16.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)

## Small outward L-shaped ticks at each corner of the frame — reinforces
## "this is a cursor locked onto a target", not just a colored outline.
func _draw_corner_ticks(rect: Rect2, color: Color) -> void:
	const TICK := 12.0
	# [corner, outward-x sign, outward-y sign] for top-left/top-right/bottom-left/bottom-right
	var corners := [
		[rect.position, -1.0, -1.0],
		[rect.position + Vector2(rect.size.x, 0.0), 1.0, -1.0],
		[rect.position + Vector2(0.0, rect.size.y), -1.0, 1.0],
		[rect.end, 1.0, 1.0],
	]
	for entry in corners:
		var corner: Vector2 = entry[0]
		draw_line(corner, corner + Vector2(TICK * entry[1], 0.0), color, 5.0)
		draw_line(corner, corner + Vector2(0.0, TICK * entry[2]), color, 5.0)

func _draw_big_image(rect: Rect2, character: CharacterData) -> void:
	var accent: Color = ACCENT_COLORS.get(character.id, Color(0.6, 0.6, 0.6))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.18), true)
	draw_rect(rect, accent, false, 3.0)
	var full_image: Texture2D = FULL_TEXTURES.get(character.id)
	if full_image:
		_draw_texture_fit(full_image, rect, 4.0)
	else:
		_draw_placeholder_initial(character.display_name, rect.position + rect.size / 2.0, 90, accent)
		_draw_centered_text("(placeholder — image a venir)", rect.position + Vector2(rect.size.x / 2.0, rect.size.y - 16.0), 12, Color(0.85, 0.86, 0.9, 0.7))

## Scales `texture` to fit inside `rect` (uniform scale, aspect preserved,
## centered), with `inset` px of margin on each side — the grid cell's
## accent tint/border stays visible as a frame around it.
func _draw_texture_fit(texture: Texture2D, rect: Rect2, inset: float) -> void:
	var avail := Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset, inset) * 2.0)
	var tex_size := texture.get_size()
	var fit_scale := minf(avail.size.x / tex_size.x, avail.size.y / tex_size.y)
	var draw_size := tex_size * fit_scale
	var draw_pos := avail.position + (avail.size - draw_size) / 2.0
	draw_texture_rect(texture, Rect2(draw_pos, draw_size), false)

func _draw_placeholder_initial(display_name: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var initial := display_name.substr(0, 1).to_upper()
	var text_size := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, center - text_size / 2.0 + Vector2(0.0, text_size.y * 0.35), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_centered_text(text: String, top_center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, top_center - Vector2(text_size.x / 2.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _start_match() -> void:
	MatchSetup.p1_character = CHARACTERS[_p1_index]
	MatchSetup.p2_character = CHARACTERS[_p2_index]
	get_tree().change_scene_to_file("res://scenes/MatchArena.tscn")
