class_name CampaignMapNode
extends Node2D

## Epic 4, Story 4.2/4.3 — the campaign map: every one of the character's
## fights (in CampaignContext.campaign) laid out as one single path, ending
## in the organizer.
##
## 2026-08-24 world-map rework (Camil, on seeing an actual Mario 3 map
## screenshot: "pour moi il faut une seule map, pas besoin de sous
## branche... vrai chemin, avec des cases pour les miniboss et des cases
## pour les boss, a la mario 3") — replaces BOTH the old branching/
## converging tree (Soul Calibur IV reference, prerequisite_ids-gated) AND
## the separate per-branch MiniBranchMap screen with ONE flat, strictly
## ordered sequence: every branch's mook_1 -> mook_2 -> rival back to back,
## then the organizer. No more choosing which branch to enter, no more a
## second screen — CampaignContext.campaign_step (see that file) is the
## single source of truth for where the player is on the path, and there is
## always exactly ONE actionable tile (the current step): everything before
## it is done, everything after is locked.
##
## 2026-08-24 same-day follow-up: "dans sources je t'ai mis un spritesheet
## pour te faire plaisir avec la map" — real art (mapPack_tilesheet.png,
## sliced into godot_project/assets/art/worldmap/) instead of the initial
## engine-drawn-shapes pass: a grass terrain background, numbered tiles for
## mooks, a small fortress for each rival ("miniboss"), a bigger castle for
## the organizer ("boss"), a straight road segment stretched/rotated
## between consecutive tiles, and a creature icon as the "you are here"
## marker over the current tile. Tiles snake across rows in a boustrophedon
## (Mario-map zigzag) with NO diagonal jogs — consecutive tiles are always
## either same-row (pure horizontal) or same-column (pure vertical), so the
## single road-segment texture only ever needs a 0/90-degree-ish rotation,
## never a corner piece.

@onready var title_label: Label = $TitleLabel
@onready var currency_label: Label = $CurrencyLabel
@onready var description_label: Label = $DescriptionLabel
@onready var hint_label: Label = $HintLabel
@onready var background: ColorRect = $Background # kept as a plain dark fallback; the grass texture (drawn in _draw()) fully covers it in practice

const GRASS_BG := preload("res://assets/art/worldmap/grass_bg.png")
const RIVAL_TOWER := preload("res://assets/art/worldmap/rival_tower.png")
const BOSS_CASTLE := preload("res://assets/art/worldmap/boss_castle.png")
const PLAYER_TOKEN_TEX := preload("res://assets/art/worldmap/player_token.png")
const ROAD_STRAIGHT := preload("res://assets/art/worldmap/road_straight.png") # a vertical capsule, native long axis = Y — see _draw_path_segment()

# Mook tiles get a sequential numbered sprite, Mario-level-number style.
# The sheet has 20; all 20 are loaded so characters with more than 8 mooks
# (e.g. Mitrailleur's 13-mook JSON map) have distinct art for every step.
const MOOK_TEXTURES: Array[Texture2D] = [
	preload("res://assets/art/worldmap/mook_01.png"), preload("res://assets/art/worldmap/mook_02.png"),
	preload("res://assets/art/worldmap/mook_03.png"), preload("res://assets/art/worldmap/mook_04.png"),
	preload("res://assets/art/worldmap/mook_05.png"), preload("res://assets/art/worldmap/mook_06.png"),
	preload("res://assets/art/worldmap/mook_07.png"), preload("res://assets/art/worldmap/mook_08.png"),
	preload("res://assets/art/worldmap/mook_09.png"), preload("res://assets/art/worldmap/mook_10.png"),
	preload("res://assets/art/worldmap/mook_11.png"), preload("res://assets/art/worldmap/mook_12.png"),
	preload("res://assets/art/worldmap/mook_13.png"), preload("res://assets/art/worldmap/mook_14.png"),
	preload("res://assets/art/worldmap/mook_15.png"), preload("res://assets/art/worldmap/mook_16.png"),
	preload("res://assets/art/worldmap/mook_17.png"), preload("res://assets/art/worldmap/mook_18.png"),
	preload("res://assets/art/worldmap/mook_19.png"), preload("res://assets/art/worldmap/mook_20.png"),
]

# Same pale-blue "motif bleed" idea Story 4.7 had for the old tree map
# (echoes the organizer's current stand-in character, Perturbateur) — the
# grass tints toward this as the player nears the final tile.
const ORGANIZER_MOTIF_COLOR := Color(0.6, 0.8, 1.0, 1.0)

const COLOR_DONE := Color(0.35, 0.9, 0.55)
const COLOR_LOCKED_TINT := Color(0.35, 0.35, 0.42, 0.6) # multiplied onto a locked tile's texture
const COLOR_DONE_TINT := Color(0.8, 0.85, 0.8, 1.0) # slightly muted, reads as "already visited"

const MOOK_RADIUS := 24.0
const MINIBOSS_RADIUS := 34.0
const BOSS_RADIUS := 52.0

# Layout: tiles snake across rows of COLS, alternating direction each row
# (left-to-right, then right-to-left, ...) like a Mario world map — no
# special-casing for the organizer, it just continues the same snake (see
# the class doc comment on why that matters for the road art). Assumes the
# branch-tile count (mini_branches.size() * 3) is a multiple of COLS, true
# for every character's authored 4 branches (12 branch tiles + 1 organizer).
const COLS := 4
const MARGIN_X := 150.0
const ROW_Y_START := 150.0
const ROW_SPACING := 110.0 # 4 rows (3 branch rows + the boss's own) must clear DescriptionLabel at y=570

enum TileType { MOOK, MINIBOSS, BOSS }

var _tile_types: Array[int] = []
var _tile_encounters: Array = [] # of RivalEncounterData, parallel to _tile_types
var _tile_branches: Array = [] # of MiniBranchData, null for the boss tile
var _tile_mook_index: Array[int] = [] # 1 or 2 (within its branch) for a mook tile, 0 otherwise
var _tile_mook_number: Array[int] = [] # 1-8, sequential across the whole path, for MOOK_TEXTURES; 0 otherwise

# 2026-08-29 (Camil: "il ne faut plus avoir une route 'figee' mais bien se
# baser sur la carte + le json pour definir les points d'interet/combats")
# — when a character has a real exported map (PNG background + a JSON case
# list from the Atelier Cartographe map-editor tool), it fully replaces the
# procedural grass/road/icon drawing below: the PNG becomes the background
# as-is (art, terrain, road already baked in) and the JSON's per-case (x, y)
# positions become where the status markers/"you are here" token sit — no
# more boustrophedon math, no more per-tile icon textures.
# _map_background null == no custom map authored yet for this character;
# the old procedural renderer stays as the fallback so every OTHER character
# keeps working exactly as before until they get their own exported map.
var _map_background: Texture2D = null
var _tile_positions: Array[Vector2] = [] # parallel to _tile_types, filled by _build_layout()

var _confirm_prev := true # seeded true — same carryover guard every menu in this project uses (2026-08-08 bug pattern)
var _cheat_prev := false # cheat menu hotkey (2026-08-09) — no carryover risk, "T" isn't shared with any other screen's confirm key
var _pulse_time := 0.0

func _ready() -> void:
	if not CampaignContext.campaign:
		# Reached directly (e.g. editor testing) without picking a campaign
		# first — bounce back rather than crash on a null campaign. Deferred:
		# changing scene synchronously from inside _ready() (still mid
		# scene-tree setup) errors ("Parent node is busy adding/removing
		# children"), caught via headless boot-check.
		get_tree().change_scene_to_file.call_deferred("res://scenes/CampaignCharacterSelect.tscn")
		return

	_build_tiles()
	_build_layout()

	# Always re-sync from the save file on arrival (character-select/title's
	# "Continuer", or bouncing back here after a fight) — cheap, and the one
	# source of truth for "how far along is this character" regardless of
	# how this scene was reached.
	var character_id: String = CampaignContext.campaign.character.id
	var step := clampi(CampaignSave.get_campaign_progress(character_id), 0, _tile_types.size() - 1)
	CampaignContext.enter_campaign(CampaignContext.campaign, step)

	title_label.text = CampaignContext.campaign.character.display_name
	_refresh()

## 2026-08-29 JSON-first architecture — tries to load this character's
## exported map JSON and build the tile list from it (case type sequence +
## pool-based encounter assignment). Falls back to the old branch-order loop
## for every character that doesn't yet have an authored map.
func _build_tiles() -> void:
	_tile_types.clear()
	_tile_encounters.clear()
	_tile_branches.clear()
	_tile_mook_index.clear()
	_tile_mook_number.clear()
	var character_id: String = CampaignContext.campaign.character.id
	var json_cases := _load_json_cases(character_id)
	if json_cases.size() > 0:
		_build_tiles_from_json(json_cases)
		return
	# Branch-based fallback — unchanged for every character without a map
	CampaignContext.set_encounter_sequence([])
	var mook_number := 0
	for branch in CampaignContext.campaign.mini_branches:
		mook_number += 1
		_tile_types.append(TileType.MOOK)
		_tile_encounters.append(branch.mook_1)
		_tile_branches.append(branch)
		_tile_mook_index.append(1)
		_tile_mook_number.append(mook_number)

		mook_number += 1
		_tile_types.append(TileType.MOOK)
		_tile_encounters.append(branch.mook_2)
		_tile_branches.append(branch)
		_tile_mook_index.append(2)
		_tile_mook_number.append(mook_number)

		_tile_types.append(TileType.MINIBOSS)
		_tile_encounters.append(branch.rival)
		_tile_branches.append(branch)
		_tile_mook_index.append(0)
		_tile_mook_number.append(0)

	_tile_types.append(TileType.BOSS)
	_tile_encounters.append(CampaignContext.campaign.organizer_encounter)
	_tile_branches.append(null)
	_tile_mook_index.append(0)
	_tile_mook_number.append(0)

## Loads the combat-relevant cases from a character's exported map JSON,
## sorted by index and filtered to mook/miniboss/boss only. Returns an empty
## array when no JSON+PNG pair exists, the file is malformed, or there are no
## combat cases — the caller then falls back to the branch order.
func _load_json_cases(character_id: String) -> Array:
	var json_path := _map_json_path(character_id)
	var png_path := _map_png_path(character_id)
	if not FileAccess.file_exists(json_path) or not FileAccess.file_exists(png_path):
		return []
	var file := FileAccess.open(json_path, FileAccess.READ)
	if not file:
		return []
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("cases") or typeof(data["cases"]) != TYPE_ARRAY:
		return []
	var cases: Array = data["cases"].duplicate()
	cases.sort_custom(func(a, b): return a.get("index", 0) < b.get("index", 0))
	var combat_cases: Array = []
	for c in cases:
		if typeof(c) == TYPE_DICTIONARY and c.get("type", "") in ["mook", "miniboss", "boss"]:
			combat_cases.append(c)
	return combat_cases

## Builds _tile_* arrays and pushes a flat encounter sequence to
## CampaignContext when this character has an exported JSON map.
##
## Encounter assignment is pool-based: mook encounters are taken in order from
## all branches' mook_1/mook_2 concatenated; rival encounters from all
## branches' .rival concatenated; boss = campaign.organizer_encounter. The
## JSON case type at each sorted index determines which pool to consume next.
## If the pool runs out before the JSON cases do, that tile's encounter is null
## (push_warning logged). Extra pool entries beyond what JSON requests are
## silently unused (e.g. a branch added to reach pool size N when JSON only
## needs N-1 of that type).
func _build_tiles_from_json(json_cases: Array) -> void:
	# Build encounter pools from the branch data (order: branch 0, branch 1, …)
	var mook_pool: Array = []
	var rival_pool: Array = []
	for branch in CampaignContext.campaign.mini_branches:
		mook_pool.append(branch.mook_1)
		mook_pool.append(branch.mook_2)
		rival_pool.append(branch.rival)

	var character_id: String = CampaignContext.campaign.character.id
	var mook_idx := 0
	var rival_idx := 0
	var mook_number := 0
	var encounter_seq: Array = []

	for c in json_cases:
		var ctype: String = c.get("type", "")
		match ctype:
			"mook":
				mook_number += 1
				var enc: RivalEncounterData = null
				if mook_idx < mook_pool.size():
					enc = mook_pool[mook_idx]
				else:
					push_warning("CampaignMapNode: '%s' JSON needs more mook encounters than the branch pool provides (pool size %d, needed %d)" % [character_id, mook_pool.size(), mook_idx + 1])
				mook_idx += 1
				_tile_types.append(TileType.MOOK)
				_tile_encounters.append(enc)
				_tile_branches.append(null)  # no branch context in JSON mode
				_tile_mook_index.append(0)   # per-branch index unused in JSON mode
				_tile_mook_number.append(mook_number)
				encounter_seq.append(enc)
			"miniboss":
				var enc: RivalEncounterData = null
				if rival_idx < rival_pool.size():
					enc = rival_pool[rival_idx]
				else:
					push_warning("CampaignMapNode: '%s' JSON needs more rival encounters than the branch pool provides (pool size %d, needed %d)" % [character_id, rival_pool.size(), rival_idx + 1])
				rival_idx += 1
				_tile_types.append(TileType.MINIBOSS)
				_tile_encounters.append(enc)
				_tile_branches.append(null)
				_tile_mook_index.append(0)
				_tile_mook_number.append(0)
				encounter_seq.append(enc)
			"boss":
				_tile_types.append(TileType.BOSS)
				_tile_encounters.append(CampaignContext.campaign.organizer_encounter)
				_tile_branches.append(null)
				_tile_mook_index.append(0)
				_tile_mook_number.append(0)
				encounter_seq.append(CampaignContext.campaign.organizer_encounter)

	CampaignContext.set_encounter_sequence(encounter_seq)

## Tries to load this character's exported map (Atelier Cartographe: a PNG
## background + a JSON case list) and use its case positions verbatim;
## falls back to the procedural boustrophedon layout for every tile when no
## map has been authored yet, or when one exists but doesn't have exactly
## one case per real step (a mismatched/half-finished export) — never a
## partial mix of the two for a single character.
func _build_layout() -> void:
	_map_background = null
	_tile_positions.clear()
	var character_id: String = CampaignContext.campaign.character.id
	var custom_positions := _load_custom_map_positions(character_id)
	if custom_positions.size() == _tile_types.size():
		_map_background = _load_texture_from_disk(_map_png_path(character_id))
		_tile_positions = custom_positions
	else:
		for i in _tile_types.size():
			_tile_positions.append(_procedural_tile_position(i))

## Reads a PNG straight off disk via Image, bypassing Godot's resource
## import cache — a freshly-dropped map export won't have a .import file
## yet (and might never get one, if it's never opened in the editor), so
## load()/ResourceLoader can't see it even though the raw file is right
## there under res://.
func _load_texture_from_disk(path: String) -> Texture2D:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		push_warning("CampaignMapNode: failed to load map image '%s' (error %d)" % [path, err])
		return null
	return ImageTexture.create_from_image(img)

func _map_png_path(character_id: String) -> String:
	return "res://assets/art/worldmap/maps/%s_map.png" % character_id

func _map_json_path(character_id: String) -> String:
	return "res://assets/art/worldmap/maps/%s_map.json" % character_id

## Returns the ordered (mook/miniboss/boss)-typed case positions from the
## character's exported map JSON, or an empty array if there's no map, the
## file is malformed, or it doesn't exist as a matching PNG+JSON pair.
## Decorative custom case types (a "bonus" or "depart" tile the map author
## added for their own tagging) are skipped — they aren't part of the real
## fight sequence CampaignContext drives, only the 3 core types are.
func _load_custom_map_positions(character_id: String) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var png_path := _map_png_path(character_id)
	var json_path := _map_json_path(character_id)
	if not FileAccess.file_exists(png_path) or not FileAccess.file_exists(json_path):
		return positions
	var file := FileAccess.open(json_path, FileAccess.READ)
	if not file:
		push_warning("CampaignMapNode: couldn't open map JSON for '%s'" % character_id)
		return positions
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("cases") or typeof(data["cases"]) != TYPE_ARRAY:
		push_warning("CampaignMapNode: malformed map JSON for '%s'" % character_id)
		return positions
	var cases: Array = data["cases"].duplicate()
	cases.sort_custom(func(a, b): return a.get("index", 0) < b.get("index", 0))
	for c in cases:
		if typeof(c) == TYPE_DICTIONARY and c.get("type") in ["mook", "miniboss", "boss"]:
			positions.append(Vector2(c.get("x", 0.0), c.get("y", 0.0)))
	if positions.size() != _tile_types.size():
		push_warning("CampaignMapNode: '%s' map has %d path case(s), expected %d for this campaign — using the generated layout instead" % [character_id, positions.size(), _tile_types.size()])
		return []
	return positions

func _process(delta: float) -> void:
	if not CampaignContext.campaign:
		return # queue_free()'d but still processing this frame (e.g. CampaignContext.clear() ran right after) — _draw() reads campaign state, nothing left to safely draw/navigate
	_pulse_time += delta
	queue_redraw() # cheap for a handful of texture blits + a pulsing ring/token

	var confirm := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	if confirm and not _confirm_prev:
		_confirm_selection()
	_confirm_prev = confirm

	# Cheat menu (2026-08-09) — dev/debug entry point, unchanged from the
	# tree-map version.
	if OS.is_debug_build() and Input.is_physical_key_pressed(KEY_T) and not _cheat_prev:
		get_tree().change_scene_to_file("res://scenes/CampaignCheatMenu.tscn")
	_cheat_prev = Input.is_physical_key_pressed(KEY_T)

	# 2026-08-18 (Camil: "dans les menus, quand je fais Echap, que ca
	# revienne en arriere") — the title screen is the one universal,
	# unambiguous "back" target, unchanged from the tree-map version.
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")

## 2026-08-18 ("un monde par rival... on peut inventer plein de mini jeux
## sympa") — a mook-slot encounter can route somewhere other than a plain
## 1v1 fight; the rival/organizer slot is never anything but "combat"
## (RivalEncounterData.challenge_type's own doc comment). Moved here from
## the now-removed MiniBranchMapNode._confirm() — same dispatch, single
## entry point now that there's only one map.
func _confirm_selection() -> void:
	var encounter := CampaignContext.current_encounter()
	if not encounter:
		return # campaign_step already past the last tile — nothing left to fight
	match encounter.challenge_type:
		"breakout":
			get_tree().change_scene_to_file("res://scenes/Breakout.tscn")
		"space_invaders":
			get_tree().change_scene_to_file("res://scenes/SpaceInvaders.tscn")
		_:
			get_tree().change_scene_to_file("res://scenes/MatchArena.tscn")

func _refresh() -> void:
	var character_id: String = CampaignContext.campaign.character.id
	currency_label.text = "Gold: %d" % CampaignSave.get_currency(character_id)

	var step := CampaignContext.campaign_step
	var total := _tile_types.size()

	if step >= total:
		description_label.text = "Campagne terminee !"
	else:
		var opponent: CharacterData = _tile_encounters[step].opponent if _tile_encounters[step] else null
		var opponent_name := opponent.display_name if opponent else "?"
		match _tile_types[step]:
			TileType.MOOK:
				var branch: MiniBranchData = _tile_branches[step]
				if branch:
					description_label.text = "%s — Sous-adversaire %d/2 (vs %s)" % [branch.display_name, _tile_mook_index[step], opponent_name]
				else:
					# JSON-based tile: no branch context, just show opponent
					description_label.text = "Combat %d (vs %s)" % [_tile_mook_number[step], opponent_name]
			TileType.MINIBOSS:
				var twist_suffix := ""
				if _tile_encounters[step].twist:
					twist_suffix = " (Twist : %s)" % _tile_encounters[step].twist.display_name
				description_label.text = "Rival : %s%s" % [opponent_name, twist_suffix]
			_: # TileType.BOSS
				description_label.text = "Combat final : l'Organisateur du tournoi."

	hint_label.text = "Espace/Entree : lancer le combat  |  Etape %d/%d" % [mini(step + 1, total), total]
	if OS.is_debug_build():
		hint_label.text += " | T : menu cheat"
	queue_redraw()

func _tile_status(i: int) -> String:
	if i < CampaignContext.campaign_step:
		return "done"
	elif i == CampaignContext.campaign_step:
		return "current"
	else:
		return "locked"

func _tile_radius(i: int) -> float:
	match _tile_types[i]:
		TileType.MOOK:
			return MOOK_RADIUS
		TileType.MINIBOSS:
			return MINIBOSS_RADIUS
		_:
			return BOSS_RADIUS

func _tile_texture(i: int) -> Texture2D:
	match _tile_types[i]:
		TileType.MOOK:
			# Bug (Camil: "Out of bounds get index '8' (on base:
			# 'Array[Texture2D]')") — mook_number counts up unbounded across
			# the whole path; with more than 4 branches (e.g. Mitrailleur's
			# 6, 12 mooks) it walked past MOOK_TEXTURES' 8 sprites. Wrap it
			# so every branch count stays in range, just cycling the art.
			return MOOK_TEXTURES[(_tile_mook_number[i] - 1) % MOOK_TEXTURES.size()]
		TileType.MINIBOSS:
			return RIVAL_TOWER
		_:
			return BOSS_CASTLE

## Fallback-only layout — see _build_layout(). Boustrophedon: tiles snake
## across rows of COLS, alternating direction each row like a Mario world
## map, deliberately NOT special-casing the organizer/last tile, so every
## consecutive pair of tiles differs in exactly one axis (pure horizontal
## within a row, pure vertical between rows) and the straight road texture
## never needs a corner piece.
func _procedural_tile_position(i: int) -> Vector2:
	var row := i / COLS
	var col := i % COLS
	var display_col := col if row % 2 == 0 else (COLS - 1 - col)
	var x := MARGIN_X + display_col * ((1280.0 - MARGIN_X * 2.0) / float(COLS - 1))
	var y := ROW_Y_START + row * ROW_SPACING
	return Vector2(x, y)

## Every draw/hit-test call site reads tile positions through here — filled
## once per _build_layout() call from either the character's real exported
## map or the procedural fallback, so nothing downstream needs to know which.
func _tile_position(i: int) -> Vector2:
	return _tile_positions[i]

func _draw() -> void:
	if not CampaignContext.campaign:
		return # a queue_redraw() from an earlier frame can still fire _draw() once after CampaignContext.campaign goes null (e.g. cleared right after queue_free()) — the _process() guard alone isn't enough, redraws aren't synchronous with it

	var total := _tile_types.size()

	if _map_background:
		# Real exported map: the terrain, road and tile art are already
		# baked into the PNG — just lay it down as-is and overlay small
		# status markers at each case's own (x, y) from the JSON.
		draw_texture_rect(_map_background, Rect2(0.0, 0.0, 1280.0, 720.0), false)
		for i in total:
			_draw_case_marker(i)
		return

	# Fallback: no custom map for this character yet — the original
	# procedural grass/road/icon rendering.
	draw_texture_rect(GRASS_BG, Rect2(0.0, 0.0, 1280.0, 720.0), false)
	var progress := float(CampaignContext.campaign_step) / float(maxi(total - 1, 1))
	var tint_alpha := clampf(progress, 0.0, 1.0) * 0.35
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), Color(ORGANIZER_MOTIF_COLOR.r, ORGANIZER_MOTIF_COLOR.g, ORGANIZER_MOTIF_COLOR.b, tint_alpha))

	for i in total - 1:
		var lit := i < CampaignContext.campaign_step
		_draw_path_segment(_tile_position(i), _tile_position(i + 1), COLOR_DONE if lit else Color(1.0, 1.0, 1.0, 0.55))

	for i in total:
		_draw_tile(i)

## Real-map overlay: the art already shows the tile, so a marker only needs
## to communicate STATUS (done/current/locked), not identity.
func _draw_case_marker(i: int) -> void:
	var center := _tile_position(i)
	match _tile_status(i):
		"done":
			draw_circle(center, 11.0, COLOR_DONE)
			draw_arc(center, 11.0, 0.0, TAU, 24, Color(0, 0, 0, 0.35), 2.0)
		"current":
			_draw_current_pulse(center, 18.0)
			_draw_player_token(center, 18.0)
		_: # locked
			draw_circle(center, 9.0, Color(0.1, 0.1, 0.14, 0.6))
			draw_arc(center, 9.0, 0.0, TAU, 20, Color(1, 1, 1, 0.25), 1.5)

## The road art (ROAD_STRAIGHT) is a vertical capsule — its own native long
## axis is Y. Rotating by (direction.angle() - PI/2) aligns that axis with
## the segment regardless of orientation (the shape reads the same rotated
## 180 degrees, so sign doesn't matter), and scaling only the Y axis
## stretches its length without distorting its thickness.
func _draw_path_segment(a: Vector2, b: Vector2, tint: Color) -> void:
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var native := ROAD_STRAIGHT.get_size()
	var angle := (b - a).angle() - PI / 2.0
	draw_set_transform((a + b) / 2.0, angle, Vector2(1.0, length / native.y))
	draw_texture_rect(ROAD_STRAIGHT, Rect2(-native.x / 2.0, -native.y / 2.0, native.x, native.y), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE) # reset — this transform must not leak into the tile/label draws that follow

func _draw_tile(i: int) -> void:
	var center := _tile_position(i)
	var radius := _tile_radius(i)
	var status := _tile_status(i)
	var tex := _tile_texture(i)
	var native := tex.get_size()
	var display_scale := (radius * 2.0) / maxf(native.x, native.y) # fit within a radius*2 bounding box, preserving the source art's own aspect ratio
	var size := native * display_scale
	var rect := Rect2(center - size / 2.0, size)

	var tint := Color(1.0, 1.0, 1.0, 1.0)
	if status == "locked":
		tint = COLOR_LOCKED_TINT
	elif status == "done":
		tint = COLOR_DONE_TINT
	draw_texture_rect(tex, rect, false, tint)

	if status == "current":
		_draw_current_pulse(center, radius)
		_draw_player_token(center, radius)

func _draw_current_pulse(center: Vector2, base_radius: float) -> void:
	var pulse_radius := base_radius + 10.0 + sin(_pulse_time * 4.0) * 4.0
	draw_arc(center, pulse_radius, 0.0, TAU, 40, Color(1, 1, 1, 0.8), 3.0)

## The "you are here" marker — a small creature icon floating (and gently
## bobbing) above the current tile, Mario-overworld-sprite style.
func _draw_player_token(center: Vector2, base_radius: float) -> void:
	var bob := sin(_pulse_time * 3.0) * 4.0
	var native := PLAYER_TOKEN_TEX.get_size()
	var token_size := Vector2(34.0, 34.0 * native.y / native.x)
	var pos := center + Vector2(-token_size.x / 2.0, -base_radius - token_size.y - 6.0 + bob)
	draw_texture_rect(PLAYER_TOKEN_TEX, Rect2(pos, token_size), false)
