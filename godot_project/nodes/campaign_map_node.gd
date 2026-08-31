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

# 2026-08-31 — graph-mode campaign (Camil: "il n'y a plus de branches. La
# campagne DOIT se baser uniquement sur la carte"). When _graph_mode is true,
# the JSON has path_nodes + connections fields that define a real traversal
# graph, not just a sorted flat sequence. Navigation, resolution, and save
# are all per-node-id rather than a single monotonic integer step.
#
# _graph_nodes: id → {id, x, y, type} for every node (cases + path_nodes).
#   type "" = relay (path_node); type in [mook/miniboss/boss/custom_depart/...].
# _graph_adj: id → [neighbor_id, …] — undirected adjacency built from connections[].
# _graph_combat_encounters: id → RivalEncounterData, only for mook/miniboss/boss nodes.
# _tile_node_ids: the case id for each slot in _tile_types/_tile_positions (parallel).
# _current_node_id / _previous_node_id: token position + one-step back-trail for retreat.
# _resolved_ids: id → true for every combat node the player has already won.
# _depart_node_id: the id of the custom_depart anchor (or "" if none).
var _graph_mode: bool = false
var _graph_nodes: Dictionary = {}
var _graph_adj: Dictionary = {}
var _graph_combat_encounters: Dictionary = {}
var _tile_node_ids: Array[String] = []
var _current_node_id: String = ""
var _previous_node_id: String = ""
var _resolved_ids: Dictionary = {}
var _depart_node_id: String = ""

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

# 2026-08-30 arrow-key navigation + display_step
# _display_step: the tile the player's token is currently ON visually. Can be
#   -1 when a JSON "depart" anchor exists and the campaign hasn't started yet.
#   Ranges from -1 (depart) through 0..campaign_step; never exceeds campaign_step
#   so the player can't skip past the next unresolved fight.
#   Distinct from CampaignContext.campaign_step which is the authoritative saved
#   progress and only ever moves FORWARD after winning a fight.
# _has_depart/_depart_position: whether the exported JSON defines a "depart"
#   anchor and its (x, y) screen position on the PNG.
# _token_draw_position: the ANIMATED position of the player token sprite;
#   interpolated by a Tween during navigation, resting at _get_position_for_step
#   (_display_step) otherwise.
# _is_tweening: true while a navigation Tween is running — arrow inputs ignored.
# _confirm_dialog_active: true while the fight-confirmation panel is visible.
var _display_step: int = 0
var _has_depart: bool = false
var _depart_position: Vector2 = Vector2.ZERO
var _token_draw_position: Vector2 = Vector2.ZERO
var _is_tweening: bool = false
var _confirm_dialog_active: bool = false
var _confirm_panel: Panel = null
# Edge-detection state for each arrow key (detect press, not hold)
var _arrow_prev: Dictionary = {KEY_UP: false, KEY_DOWN: false, KEY_LEFT: false, KEY_RIGHT: false}

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

	var character_id: String = CampaignContext.campaign.character.id

	if _graph_mode:
		# Graph mode (2026-08-31): free-navigation graph, per-id resolution.
		# Load which nodes have been resolved from the save file, then place
		# the token at: the last-fought node (after a loss/win, current_graph_
		# node_id is preserved through return_to_map()), or the depart anchor
		# for a fresh start, or the first combat node as a last resort.
		_resolved_ids.clear()
		for cid in CampaignSave.get_resolved_case_ids(character_id):
			_resolved_ids[str(cid)] = true
		var restore_id := CampaignContext.current_graph_node_id
		if restore_id != "" and _graph_nodes.has(restore_id):
			_current_node_id = restore_id
		elif _depart_node_id != "":
			_current_node_id = _depart_node_id
		elif _tile_node_ids.size() > 0:
			_current_node_id = _tile_node_ids[0]
		_previous_node_id = ""  # no back-trail on map arrival
		_token_draw_position = _get_graph_node_position(_current_node_id)
		_create_confirm_dialog()
		# If restoring after a loss, the node is still unresolved — show
		# the fight dialog again immediately so the player can retry.
		if _is_graph_combat_node(_current_node_id) and not _is_node_resolved(_current_node_id):
			_show_confirm_dialog()
	else:
		# Linear mode — unchanged from 2026-08-30.
		# Always re-sync from the save file on arrival (character-select/title's
		# "Continuer", or bouncing back here after a fight) — cheap, and the one
		# source of truth for "how far along is this character" regardless of
		# how this scene was reached.
		var step := clampi(CampaignSave.get_campaign_progress(character_id), 0, _tile_types.size() - 1)
		CampaignContext.enter_campaign(CampaignContext.campaign, step)
		_load_depart_position(character_id)
		if _has_depart and CampaignContext.campaign_step == 0:
			_display_step = -1
		else:
			_display_step = CampaignContext.campaign_step
		_token_draw_position = _get_position_for_step(_display_step)
		_create_confirm_dialog()
		if _display_step >= 0 and _display_step == CampaignContext.campaign_step \
				and _display_step < _tile_types.size():
			_show_confirm_dialog()

	title_label.text = CampaignContext.campaign.character.display_name
	_refresh()

## 2026-08-29 JSON-first architecture — tries to load this character's
## exported map JSON and build the tile list from it (case type sequence +
## pool-based encounter assignment). Falls back to the old branch-order loop
## for every character that doesn't yet have an authored map.
##
## 2026-08-31 graph-mode extension: if the JSON also has path_nodes +
## connections fields, the character uses free-navigation graph mode instead
## of the previous linear sequence mode.
func _build_tiles() -> void:
	_tile_types.clear()
	_tile_encounters.clear()
	_tile_branches.clear()
	_tile_mook_index.clear()
	_tile_mook_number.clear()
	_tile_node_ids.clear()
	_graph_mode = false
	_graph_nodes.clear()
	_graph_adj.clear()
	_graph_combat_encounters.clear()
	_depart_node_id = ""
	var character_id: String = CampaignContext.campaign.character.id

	# Try graph mode first (JSON with path_nodes + connections fields).
	if _load_graph_data(character_id):
		_graph_mode = true
		CampaignContext.is_graph_mode = true
		_assign_graph_encounters()
		return

	# Linear JSON mode (sorted flat sequence, no graph connectivity).
	CampaignContext.is_graph_mode = false
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
##
## Graph mode: the PNG is always loaded (we just checked it exists in
## _load_graph_data()), and _tile_positions is filled from _graph_nodes using
## _tile_node_ids — same parallel-array contract as the linear mode.
func _build_layout() -> void:
	_map_background = null
	_tile_positions.clear()
	var character_id: String = CampaignContext.campaign.character.id

	if _graph_mode:
		_map_background = _load_texture_from_disk(_map_png_path(character_id))
		for nid in _tile_node_ids:
			var n: Dictionary = _graph_nodes.get(nid, {})
			_tile_positions.append(Vector2(n.get("x", 0.0), n.get("y", 0.0)))
		return

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

	# --- Confirmation dialog open: Espace/Entrée = Oui, Échap = Non --------
	# In graph mode, arrow keys pressed while the dialog is open also dismiss
	# it and start the retreat movement (the player chose "no, go back").
	if _confirm_dialog_active:
		var confirm := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) \
			or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4
		if confirm and not _confirm_prev:
			_confirm_selection()
		_confirm_prev = confirm
		if Input.is_physical_key_pressed(KEY_ESCAPE):
			_hide_confirm_dialog()
		# Graph mode: detect arrow edges here (before _sync_arrow_prev) so the
		# player can dismiss-and-retreat without leaving the dialog open.
		if _graph_mode and not _is_tweening:
			var arrow_keys_d := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
			for key in arrow_keys_d:
				var pressed_now_d: bool = _direction_key_physically_pressed(key)
				var was_pressed_d: bool = _arrow_prev.get(key, false)
				if pressed_now_d and not was_pressed_d:
					var target_id_d := _target_node_for_graph_key(key)
					if target_id_d != "":
						_hide_confirm_dialog()
						_move_to_graph_node(target_id_d)
						break
		# Keep _arrow_prev in sync so stale `false` values don't fire a
		# phantom edge on the first frame after the dialog closes (Bug 2026-08-30).
		_sync_arrow_prev()
		return  # while dialog is up, no further navigation / cheat-menu / escape-to-title

	# --- Cheat menu (dev/debug only) ----------------------------------------
	# 2026-08-09 — unchanged from the tree-map version.
	if OS.is_debug_build() and Input.is_physical_key_pressed(KEY_T) and not _cheat_prev:
		get_tree().change_scene_to_file("res://scenes/CampaignCheatMenu.tscn")
	_cheat_prev = Input.is_physical_key_pressed(KEY_T)

	# --- Escape → title screen ----------------------------------------------
	# 2026-08-18 (Camil: "dans les menus, quand je fais Echap, que ca revienne
	# en arriere") — unchanged from the tree-map version; only fires when no
	# confirm dialog is open (handled above).
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")

	# --- Arrow-key navigation (ignored while a tween is running) ------------
	if not _is_tweening:
		if _graph_mode:
			_handle_graph_arrow_navigation()
		else:
			_handle_arrow_navigation()
	else:
		# During a tween navigation is blocked, but we still need to track
		# actual key state so _arrow_prev never goes stale. A stale `false`
		# would produce a phantom edge-detect the frame the tween completes,
		# making the token move again without a real new key press (Bug 2026-08-30).
		_sync_arrow_prev()

## 2026-08-18 ("un monde par rival... on peut inventer plein de mini jeux
## sympa") — a mook-slot encounter can route somewhere other than a plain
## 1v1 fight; the rival/organizer slot is never anything but "combat"
## (RivalEncounterData.challenge_type's own doc comment). Moved here from
## the now-removed MiniBranchMapNode._confirm() — same dispatch, single
## entry point now that there's only one map.
##
## 2026-08-31 graph mode: sets CampaignContext.current_graph_node_id and
## pending_graph_encounter before the scene change so MatchArena/Breakout/
## SpaceInvaders know which node is being fought and which encounter to run.
func _confirm_selection() -> void:
	if _graph_mode:
		var encounter: RivalEncounterData = _graph_combat_encounters.get(_current_node_id)
		if not encounter:
			return  # defensive: shouldn't happen for a valid combat node
		CampaignContext.current_graph_node_id = _current_node_id
		CampaignContext.pending_graph_encounter = encounter
		match encounter.challenge_type:
			"breakout":
				get_tree().change_scene_to_file("res://scenes/Breakout.tscn")
			"space_invaders":
				get_tree().change_scene_to_file("res://scenes/SpaceInvaders.tscn")
			_:
				get_tree().change_scene_to_file("res://scenes/MatchArena.tscn")
		return
	# Linear mode (JSON-first or branch-based fallback):
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

	if _graph_mode:
		_refresh_graph_mode()
		return

	var real_step := CampaignContext.campaign_step
	var total := _tile_types.size()

	# Description reflects the tile the player is currently LOOKING AT
	# (_display_step), not necessarily the next fight to trigger (real_step).
	if _display_step == -1:
		description_label.text = "Debut du chemin — utilisez les fleches pour avancer."
	elif _display_step >= total:
		description_label.text = "Campagne terminee !"
	else:
		var viewed := _display_step
		var opponent: CharacterData = _tile_encounters[viewed].opponent if _tile_encounters[viewed] else null
		var opponent_name := opponent.display_name if opponent else "?"
		var done_prefix := "" if viewed == real_step else "[Termine] "
		match _tile_types[viewed]:
			TileType.MOOK:
				var branch: MiniBranchData = _tile_branches[viewed]
				if branch:
					description_label.text = "%sCombat : %s — Sous-adversaire %d/2 (vs %s)" % [done_prefix, branch.display_name, _tile_mook_index[viewed], opponent_name]
				else:
					description_label.text = "%sCombat %d (vs %s)" % [done_prefix, _tile_mook_number[viewed], opponent_name]
			TileType.MINIBOSS:
				var twist_suffix := ""
				if _tile_encounters[viewed].twist:
					twist_suffix = " (Twist : %s)" % _tile_encounters[viewed].twist.display_name
				description_label.text = "%sRival : %s%s" % [done_prefix, opponent_name, twist_suffix]
			_: # TileType.BOSS
				description_label.text = "%sCombat final : l'Organisateur du tournoi." % done_prefix

	# Hint line adapts to current context
	if _confirm_dialog_active:
		hint_label.text = "Espace/Entree : lancer le combat  |  Echap : annuler"
	else:
		hint_label.text = "Fleches : naviguer  |  Etape %d/%d" % [mini(real_step + 1, total), total]
	if OS.is_debug_build() and not _confirm_dialog_active:
		hint_label.text += " | T : cheat"
	queue_redraw()

func _tile_status(i: int) -> String:
	if _graph_mode:
		if i < 0 or i >= _tile_node_ids.size():
			return "locked"
		var nid := _tile_node_ids[i]
		if _is_node_resolved(nid):
			return "done"
		if nid == _current_node_id:
			return "current"  # player is standing here (unresolved combat)
		return "locked"  # unresolved and not current
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
		# Token is drawn AFTER the markers so it sits on top; its position
		# is animated (_token_draw_position) and may differ from the "current"
		# fight tile when the player is exploring backwards.
		_draw_player_token(_token_draw_position, 18.0)
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
	# Token drawn on top at its animated position; pick a sensible base radius
	if total > 0:
		var tok_radius := MOOK_RADIUS  # default when at depart or out of range
		if _display_step >= 0 and _display_step < total:
			tok_radius = _tile_radius(_display_step)
		_draw_player_token(_token_draw_position, tok_radius)

## Real-map overlay: the art already shows the tile, so a marker only needs
## to communicate STATUS (done/current/locked), not identity.
## The player token is NOT drawn here — it is drawn separately in _draw() at
## _token_draw_position, which may be on a different tile (exploration mode).
func _draw_case_marker(i: int) -> void:
	var center := _tile_position(i)
	match _tile_status(i):
		"done":
			draw_circle(center, 11.0, COLOR_DONE)
			draw_arc(center, 11.0, 0.0, TAU, 24, Color(0, 0, 0, 0.35), 2.0)
		"current":
			# Pulse ring anchors the "next fight" tile visually even when the
			# token has wandered away from it during backwards exploration.
			_draw_current_pulse(center, 18.0)
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
		# Pulse ring marks the next fight; the player token is drawn on top
		# in _draw() at _token_draw_position (exploration may differ from here)
		_draw_current_pulse(center, radius)

func _draw_current_pulse(center: Vector2, base_radius: float) -> void:
	var pulse_radius := base_radius + 10.0 + sin(_pulse_time * 4.0) * 4.0
	draw_arc(center, pulse_radius, 0.0, TAU, 40, Color(1, 1, 1, 0.8), 3.0)

## The "you are here" marker — a small creature icon floating (and gently
## bobbing) above the current tile, Mario-overworld-sprite style.
## `center` is now _token_draw_position (animated), not necessarily the tile's
## own (x, y) — see _draw() where this is called.
func _draw_player_token(center: Vector2, base_radius: float) -> void:
	var bob := sin(_pulse_time * 3.0) * 4.0
	var native := PLAYER_TOKEN_TEX.get_size()
	var token_size := Vector2(34.0, 34.0 * native.y / native.x)
	var pos := center + Vector2(-token_size.x / 2.0, -base_radius - token_size.y - 6.0 + bob)
	draw_texture_rect(PLAYER_TOKEN_TEX, Rect2(pos, token_size), false)

# ---------------------------------------------------------------------------
# 2026-08-30 — Arrow-key navigation helpers
# ---------------------------------------------------------------------------

## Reads the "depart" case from the character's exported JSON and populates
## _has_depart / _depart_position. Only meaningful when in custom-map mode
## (_map_background != null); procedural-fallback characters have no JSON
## and therefore no depart anchor.
func _load_depart_position(character_id: String) -> void:
	_has_depart = false
	_depart_position = Vector2.ZERO
	if not _map_background:
		return  # procedural mode — no exported JSON, no depart case
	var json_path := _map_json_path(character_id)
	var file := FileAccess.open(json_path, FileAccess.READ)
	if not file:
		return
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("cases") or typeof(data["cases"]) != TYPE_ARRAY:
		return
	for c in data["cases"]:
		# Accept both "depart" (canonical type) and "custom_depart" (the name
		# the Atelier Cartographe tool currently exports for this anchor).
		if typeof(c) == TYPE_DICTIONARY and c.get("type", "") in ["depart", "custom_depart"]:
			_depart_position = Vector2(c.get("x", 0.0), c.get("y", 0.0))
			_has_depart = true
			return

## Maps a display_step value to its screen position:
##   -1  → _depart_position (if _has_depart, else falls back to tile 0)
##   0..N-1 → _tile_positions[step]
## Out-of-range values return Vector2.ZERO — callers guard against them.
func _get_position_for_step(step: int) -> Vector2:
	if step == -1:
		if _has_depart:
			return _depart_position
		return _tile_positions[0] if _tile_positions.size() > 0 else Vector2.ZERO
	if step >= 0 and step < _tile_positions.size():
		return _tile_positions[step]
	return Vector2.ZERO

## Bug report (Camil, 2026-08-31, re: Ben's playtest — "les fleches, c'est
## uniquement J2" for anything menu/map-side, and J1's own equivalent is
## WASD) — the map has exactly one navigator, never two players sharing it,
## so it should accept WASD (Z/Q/S/D on Camil's AZERTY keyboard, same
## physical keys as J1's ship controls) as well as the arrow keys, not
## arrows only. Every direction check below still keys off the canonical
## KEY_UP/DOWN/LEFT/RIGHT constants (used as direction IDs throughout this
## file, e.g. _dominant_direction()'s return value) — this only widens
## which PHYSICAL key counts as "that direction is currently held".
func _direction_key_physically_pressed(direction_key: int) -> bool:
	match direction_key:
		KEY_UP:
			return Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W)
		KEY_DOWN:
			return Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)
		KEY_LEFT:
			return Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)
		KEY_RIGHT:
			return Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)
		_:
			return false

## Returns the KEY_* constant (UP / DOWN / LEFT / RIGHT) that most closely
## describes the screen direction from `from_pos` to `to_pos`, using Godot's
## y-down screen coordinate convention (positive y = downward = KEY_DOWN).
func _dominant_direction(from_pos: Vector2, to_pos: Vector2) -> int:
	var delta := to_pos - from_pos
	if absf(delta.x) >= absf(delta.y):
		return KEY_RIGHT if delta.x > 0.0 else KEY_LEFT
	else:
		return KEY_DOWN if delta.y > 0.0 else KEY_UP

## Reads the current physical state of every arrow key into _arrow_prev so
## that edge-detection in _handle_arrow_navigation() never fires a phantom
## "just pressed" event after a guard (tween / dialog) lifts. Called every
## frame when navigation is blocked instead of calling _handle_arrow_navigation().
func _sync_arrow_prev() -> void:
	_arrow_prev[KEY_UP]    = _direction_key_physically_pressed(KEY_UP)
	_arrow_prev[KEY_DOWN]  = _direction_key_physically_pressed(KEY_DOWN)
	_arrow_prev[KEY_LEFT]  = _direction_key_physically_pressed(KEY_LEFT)
	_arrow_prev[KEY_RIGHT] = _direction_key_physically_pressed(KEY_RIGHT)

## Edge-detects freshly-pressed arrow keys and starts a Tween toward the
## adjacent step in that direction when valid. One move per call at most
## (avoids two keys pressed simultaneously producing two moves).
func _handle_arrow_navigation() -> void:
	var arrow_keys := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
	var moved := false
	for key in arrow_keys:
		var pressed_now: bool = _direction_key_physically_pressed(key)
		var was_pressed: bool = _arrow_prev.get(key, false)
		if pressed_now and not was_pressed and not moved:
			var target := _target_step_for_key(key)
			if target != _display_step:
				_move_to_display_step(target)
				moved = true
		_arrow_prev[key] = pressed_now

## Returns the display_step we would move to if `key` is pressed now, or
## _display_step unchanged if that direction doesn't map to a valid neighbour.
##
## Navigation rules:
##  - Can go BACK  to display_step-1 (or to depart at -1 from step 0).
##  - Can go FORWARD only when display_step < campaign_step, i.e. the target
##    step has already been cleared. The player can NEVER skip past campaign_step
##    — that requires winning the fight first.
func _target_step_for_key(key: int) -> int:
	var cur_pos := _get_position_for_step(_display_step)

	# Backward: step -1 (depart, if it exists) or step-1 (any step > 0)
	var can_go_back := _display_step > 0 or (_has_depart and _display_step == 0)
	if can_go_back:
		var prev_step := _display_step - 1
		var prev_pos := _get_position_for_step(prev_step)
		if _dominant_direction(cur_pos, prev_pos) == key:
			return prev_step

	# Forward: next step must already be completed (display_step < campaign_step)
	# Note: -1 < N is always true for any N >= 0, so depart → step 0 is
	# naturally handled here even on a brand-new campaign (campaign_step == 0
	# means step 0 is the NEXT fight, not yet cleared — but we DO allow moving
	# from depart to step 0 so the player can reach the fight and see the dialog).
	# The "step 0 is a depart-arrival, not a free advance" logic is enforced by
	# _on_arrive_at_display_step: showing the dialog when display_step == campaign_step.
	var can_go_forward := _display_step < CampaignContext.campaign_step \
		or _display_step == -1  # depart → step 0 always allowed
	can_go_forward = can_go_forward and (_display_step + 1) < _tile_positions.size()
	if can_go_forward:
		var next_step := _display_step + 1
		var next_pos := _get_position_for_step(next_step)
		if _dominant_direction(cur_pos, next_pos) == key:
			return next_step

	return _display_step  # key doesn't map to any navigable neighbour

## Starts an animated move of the player token to `target_step`.
## Inputs are blocked while the Tween runs. The confirm dialog (if open) is
## dismissed first — the player is navigating away.
func _move_to_display_step(target_step: int) -> void:
	_hide_confirm_dialog()
	_display_step = target_step
	_is_tweening = true
	var end_pos := _get_position_for_step(target_step)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "_token_draw_position", end_pos, 0.35)
	tween.tween_callback(func():
		_is_tweening = false
		_on_arrive_at_display_step(target_step)
	)

## Called when the token's tween has finished and the token has landed on
## `arrived_step`. If that step is the current unresolved fight tile, shows
## the combat-confirmation dialog.
func _on_arrive_at_display_step(arrived_step: int) -> void:
	_refresh()
	if arrived_step < 0 or arrived_step >= _tile_types.size():
		return  # depart anchor or out-of-range — no combat to trigger
	if arrived_step != CampaignContext.campaign_step:
		return  # already-done tile — just update the description, no combat prompt
	# Landed on the next unresolved fight tile → ask the player
	# (_tile_types only contains MOOK / MINIBOSS / BOSS — custom_bonus and
	# depart are filtered out of the combat sequence and never land here)
	_show_confirm_dialog()

## Builds the fight-confirmation dialog as a child Panel in code — no scene
## modification needed. Hidden by default; shown by _show_confirm_dialog().
func _create_confirm_dialog() -> void:
	_confirm_panel = Panel.new()
	_confirm_panel.size = Vector2(520.0, 160.0)
	_confirm_panel.position = Vector2(1280.0 / 2.0 - 260.0, 720.0 / 2.0 - 80.0)
	_confirm_panel.visible = false
	add_child(_confirm_panel)

	var lbl := Label.new()
	lbl.text = "Voulez-vous declencher le combat ?"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0, 1.0))
	lbl.size = Vector2(480.0, 40.0)
	lbl.position = Vector2(20.0, 24.0)
	_confirm_panel.add_child(lbl)

	var oui := Button.new()
	oui.text = "Oui  (Espace / Entree)"
	oui.size = Vector2(220.0, 48.0)
	oui.position = Vector2(30.0, 88.0)
	oui.pressed.connect(_confirm_selection)
	_confirm_panel.add_child(oui)

	var non := Button.new()
	non.text = "Non  (Echap)"
	non.size = Vector2(220.0, 48.0)
	non.position = Vector2(270.0, 88.0)
	non.pressed.connect(_hide_confirm_dialog)
	_confirm_panel.add_child(non)

func _show_confirm_dialog() -> void:
	if not _confirm_panel:
		return
	_confirm_dialog_active = true
	_confirm_panel.visible = true
	_confirm_prev = true  # seed the carryover guard so a held key doesn't insta-trigger
	_refresh()

func _hide_confirm_dialog() -> void:
	if not _confirm_panel:
		return
	_confirm_dialog_active = false
	_confirm_panel.visible = false
	_refresh()

# ---------------------------------------------------------------------------
# 2026-08-31 — Graph-mode helpers
# ---------------------------------------------------------------------------

## Loads the graph structure from the character's exported JSON when it has
## the new path_nodes + connections fields. Populates _graph_nodes, _graph_adj,
## _depart_node_id. Returns true if graph mode was successfully detected.
## Returns false for characters using the old format (linear JSON or branch
## fallback) — the caller then tries the next mode down.
func _load_graph_data(character_id: String) -> bool:
	var json_path := _map_json_path(character_id)
	var png_path := _map_png_path(character_id)
	if not FileAccess.file_exists(json_path) or not FileAccess.file_exists(png_path):
		return false
	var file := FileAccess.open(json_path, FileAccess.READ)
	if not file:
		return false
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	# Graph mode requires both path_nodes and connections arrays in the JSON.
	if not data.has("path_nodes") or not data.has("connections") \
			or not data.has("cases"):
		return false
	if typeof(data["path_nodes"]) != TYPE_ARRAY \
			or typeof(data["connections"]) != TYPE_ARRAY \
			or typeof(data["cases"]) != TYPE_ARRAY:
		return false

	# Load all case nodes (combat + custom types like depart/bonus)
	for c in data["cases"]:
		if typeof(c) != TYPE_DICTIONARY or not c.has("id"):
			continue
		var nid: String = str(c["id"])
		_graph_nodes[nid] = {
			"id": nid,
			"x": float(c.get("x", 0)),
			"y": float(c.get("y", 0)),
			"type": str(c.get("type", "")),
			"index": int(c.get("index", 9999))
		}
		_graph_adj[nid] = []
		var t := str(c.get("type", ""))
		if t in ["custom_depart", "depart"]:
			_depart_node_id = nid

	# Load relay nodes (path_nodes — no type, pure traversal waypoints)
	for p in data["path_nodes"]:
		if typeof(p) != TYPE_DICTIONARY or not p.has("id"):
			continue
		var nid: String = str(p["id"])
		_graph_nodes[nid] = {
			"id": nid,
			"x": float(p.get("x", 0)),
			"y": float(p.get("y", 0)),
			"type": "",
			"index": 9999
		}
		_graph_adj[nid] = []

	# Build undirected adjacency list from connections
	for conn in data["connections"]:
		if typeof(conn) != TYPE_ARRAY or conn.size() < 2:
			continue
		var a: String = str(conn[0])
		var b: String = str(conn[1])
		if _graph_adj.has(a) and not (b in _graph_adj[a]):
			_graph_adj[a].append(b)
		if _graph_adj.has(b) and not (a in _graph_adj[b]):
			_graph_adj[b].append(a)

	return true

## Assigns encounters to the graph's combat nodes using the same pool logic
## as the linear JSON mode (mook_pool / rival_pool consumed in JSON index
## order). Also fills _tile_types, _tile_node_ids, _tile_encounters (all
## parallel arrays used by _draw() and _tile_status()), and pushes the flat
## encounter_sequence to CampaignContext for backward compatibility.
func _assign_graph_encounters() -> void:
	var mook_pool: Array = []
	var rival_pool: Array = []
	for branch in CampaignContext.campaign.mini_branches:
		mook_pool.append(branch.mook_1)
		mook_pool.append(branch.mook_2)
		rival_pool.append(branch.rival)

	var character_id: String = CampaignContext.campaign.character.id

	# Sort all combat nodes by JSON index to determine pool assignment order
	var combat_nodes: Array = []
	for nid in _graph_nodes:
		var t: String = _graph_nodes[nid].get("type", "")
		if t in ["mook", "miniboss", "boss"]:
			combat_nodes.append(_graph_nodes[nid])
	combat_nodes.sort_custom(func(a, b): return int(a.get("index", 9999)) < int(b.get("index", 9999)))

	var mook_idx := 0
	var rival_idx := 0
	var mook_number := 0
	var encounter_seq: Array = []
	_graph_combat_encounters.clear()

	for node in combat_nodes:
		var nid: String = node["id"]
		var ctype: String = node.get("type", "")
		match ctype:
			"mook":
				mook_number += 1
				var enc: RivalEncounterData = null
				if mook_idx < mook_pool.size():
					enc = mook_pool[mook_idx]
				else:
					push_warning("CampaignMapNode: '%s' graph needs more mook encounters than pool (pool=%d, needed=%d)" % [character_id, mook_pool.size(), mook_idx + 1])
				mook_idx += 1
				_graph_combat_encounters[nid] = enc
				_tile_types.append(TileType.MOOK)
				_tile_mook_number.append(mook_number)
				_tile_node_ids.append(nid)
				_tile_encounters.append(enc)
				_tile_branches.append(null)
				_tile_mook_index.append(0)
				encounter_seq.append(enc)
			"miniboss":
				var enc: RivalEncounterData = null
				if rival_idx < rival_pool.size():
					enc = rival_pool[rival_idx]
				else:
					push_warning("CampaignMapNode: '%s' graph needs more rival encounters than pool (pool=%d)" % [character_id, rival_pool.size()])
				rival_idx += 1
				_graph_combat_encounters[nid] = enc
				_tile_types.append(TileType.MINIBOSS)
				_tile_mook_number.append(0)
				_tile_node_ids.append(nid)
				_tile_encounters.append(enc)
				_tile_branches.append(null)
				_tile_mook_index.append(0)
				encounter_seq.append(enc)
			"boss":
				var enc := CampaignContext.campaign.organizer_encounter
				_graph_combat_encounters[nid] = enc
				_tile_types.append(TileType.BOSS)
				_tile_mook_number.append(0)
				_tile_node_ids.append(nid)
				_tile_encounters.append(enc)
				_tile_branches.append(null)
				_tile_mook_index.append(0)
				encounter_seq.append(enc)

	CampaignContext.set_encounter_sequence(encounter_seq)

## Maps a graph node id to its screen position (x, y) from _graph_nodes.
func _get_graph_node_position(nid: String) -> Vector2:
	var n: Dictionary = _graph_nodes.get(nid, {})
	return Vector2(float(n.get("x", 0.0)), float(n.get("y", 0.0)))

## Returns true if this node is a combat case (mook / miniboss / boss).
## Relay nodes and custom non-combat cases (depart, bonus) return false.
func _is_graph_combat_node(nid: String) -> bool:
	var nd: Dictionary = _graph_nodes.get(nid, {})
	var t: String = str(nd.get("type", ""))
	return t in ["mook", "miniboss", "boss"]

## Returns true if this combat node has been won by the player.
func _is_node_resolved(nid: String) -> bool:
	return _resolved_ids.get(nid, false)

## Returns true if the token can move from _current_node_id to the given
## neighbor. The only movement restriction: when standing on an UNRESOLVED
## combat node (Camil: "ne peut PAS continuer au-delà de ce noeud"), the
## player may only retreat to _previous_node_id (where they came from). When
## there is no previous node (e.g. map reload after a loss), retreat is allowed
## to any relay/resolved neighbor so the player is never hard-locked.
func _can_move_to_graph_neighbor(neighbor_id: String) -> bool:
	if _is_graph_combat_node(_current_node_id) and not _is_node_resolved(_current_node_id):
		if _previous_node_id != "":
			return neighbor_id == _previous_node_id
		# No previous node: allow retreat to resolved or non-combat neighbors
		if _is_node_resolved(neighbor_id):
			return true
		var nd: Dictionary = _graph_nodes.get(neighbor_id, {})
		var t: String = str(nd.get("type", ""))
		return t not in ["mook", "miniboss", "boss"]
	return true  # from resolved/relay/depart: all neighbors accessible

## For the given arrow key, finds the NEAREST neighbor of _current_node_id
## whose dominant screen direction (haut/bas/gauche/droite) matches the key
## and that _can_move_to_graph_neighbor() allows. Returns "" if none found.
func _target_node_for_graph_key(key: int) -> String:
	var cur_pos := _get_graph_node_position(_current_node_id)
	var neighbors: Array = _graph_adj.get(_current_node_id, [])
	var best_id := ""
	var best_dist := INF
	for neighbor_id in neighbors:
		if not _can_move_to_graph_neighbor(neighbor_id):
			continue
		var neighbor_pos := _get_graph_node_position(neighbor_id)
		if _dominant_direction(cur_pos, neighbor_pos) == key:
			var dist := cur_pos.distance_to(neighbor_pos)
			if dist < best_dist:
				best_dist = dist
				best_id = neighbor_id
	return best_id

## Graph-mode arrow navigation — edge-detects arrow keys and starts a Tween
## toward the matching neighbor (nearest, in that dominant direction).
func _handle_graph_arrow_navigation() -> void:
	var arrow_keys := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
	var moved := false
	for key in arrow_keys:
		var pressed_now: bool = _direction_key_physically_pressed(key)
		var was_pressed: bool = _arrow_prev.get(key, false)
		if pressed_now and not was_pressed and not moved:
			var target_id := _target_node_for_graph_key(key)
			if target_id != "":
				_move_to_graph_node(target_id)
				moved = true
		_arrow_prev[key] = pressed_now

## Starts an animated Tween moving the token to the given graph node.
## Updates _previous_node_id and _current_node_id before the animation so
## _tile_status() and navigation rules reflect the new position immediately.
func _move_to_graph_node(target_id: String) -> void:
	_hide_confirm_dialog()
	_previous_node_id = _current_node_id
	_current_node_id = target_id
	_is_tweening = true
	var end_pos := _get_graph_node_position(target_id)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "_token_draw_position", end_pos, 0.35)
	tween.tween_callback(func():
		_is_tweening = false
		_on_arrive_at_graph_node(target_id)
	)

## Called when the token's tween has finished and the token has arrived at
## a graph node. Shows the fight-confirmation dialog if the node is an
## unresolved combat case; does nothing for relay/resolved/non-combat nodes.
func _on_arrive_at_graph_node(node_id: String) -> void:
	_refresh()
	if not _is_graph_combat_node(node_id):
		return  # relay, depart, bonus — no dialog
	if _is_node_resolved(node_id):
		return  # already won — just visiting, no dialog
	_show_confirm_dialog()

## Graph-mode _refresh() — description + hint line based on the current node.
func _refresh_graph_mode() -> void:
	var node: Dictionary = _graph_nodes.get(_current_node_id, {})
	var type: String = str(node.get("type", ""))
	var total := _tile_node_ids.size()
	var resolved_count := 0
	for nid in _tile_node_ids:
		if _is_node_resolved(nid):
			resolved_count += 1

	if type in ["custom_depart", "depart"]:
		description_label.text = "Debut du chemin — utilisez les fleches pour explorer."
	elif type == "":
		description_label.text = "En transit..."
	elif _is_node_resolved(_current_node_id):
		var enc: RivalEncounterData = _graph_combat_encounters.get(_current_node_id)
		var opp_name := enc.opponent.display_name if (enc and enc.opponent) else "?"
		description_label.text = "[Termine] vs %s" % opp_name
	else:
		var enc: RivalEncounterData = _graph_combat_encounters.get(_current_node_id)
		if enc:
			var opp_name := enc.opponent.display_name if enc.opponent else "?"
			match type:
				"boss":
					description_label.text = "Combat final : %s (Organisateur)" % opp_name
				"miniboss":
					description_label.text = "Rival : vs %s" % opp_name
				_:
					description_label.text = "Combat : vs %s" % opp_name
		else:
			description_label.text = "Case inconnue"

	if _confirm_dialog_active:
		hint_label.text = "Espace/Entree : lancer le combat  |  Echap : annuler"
	else:
		hint_label.text = "Fleches : naviguer  |  Victoires : %d/%d" % [resolved_count, total]
	if OS.is_debug_build() and not _confirm_dialog_active:
		hint_label.text += " | T : cheat"
	queue_redraw()
