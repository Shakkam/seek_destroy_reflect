local screen_manager = require("screen_manager")
local input = require("input")
local campaign_context = require("campaign.campaign_context")
local campaign_save = require("campaign.campaign_save")
local match_arena = require("screens.match_arena")
local breakout = require("screens.breakout")
local space_invaders = require("screens.space_invaders")
local gradius = require("screens.gradius")
local campaign_cheat_menu = require("screens.campaign_cheat_menu")
local assets = require("assets")
local draw_utils = require("draw_utils")
local mathx = require("simulation.mathx")
local json = require("json")

-- Ported from godot_project/nodes/campaign_map_node.gd — 2026-08-24 world-
-- map rework (Camil, on seeing a Mario 3 screenshot: "il faut une seule
-- map... vrai chemin, avec des cases pour les miniboss et des cases pour
-- les boss, a la mario 3"), PLUS the same-day follow-up real-art pass
-- ("dans sources je t'ai mis un spritesheet pour te faire plaisir avec la
-- map"): a boustrophedon snake of real tile sprites (grass terrain, a
-- straight road segment rotated/stretched between consecutive tiles,
-- numbered mook icons, a rival tower, a boss castle) with an animated
-- "you are here" token the player walks with the arrow keys/WASD — not a
-- flat row of engine-drawn shapes (2026-09-14 correction, Camil: "c'est
-- pas ca du tout... tout est dans la version godot").
--
-- 2026-09-14, same-day follow-up: GRAPH MODE (godot_project's own 2026-08-31
-- rework, Camil: "il n'y a plus de branches. La campagne DOIT se baser
-- uniquement sur la carte") — a character with a real Atelier Cartographe
-- export whose JSON also carries path_nodes+connections (currently just
-- Mitrailleur) fully replaces the procedural rendering above: the PNG
-- background is drawn as-is (terrain/road/tile art already baked in) and
-- the token free-navigates the real graph (relay waypoints included, not
-- just combat tiles) instead of walking a fixed linear sequence. Every
-- other character (no JSON, or a JSON without those two fields) keeps
-- using the procedural boustrophedon above — see load_graph_data()'s own
-- fallback-to-false path.
--
-- "breakout"/"space_invaders" tiles launch their own dedicated mini-game
-- screens (see screens/breakout.lua, screens/space_invaders.lua); the
-- "not yet available" fallback below only ever fires for a genuinely
-- unhandled challenge_type, which none of the 8 characters' campaigns
-- actually use (rival_encounter_data.lua's own enum is just these three).

local campaign_map = {}

local COLS = 4
local MARGIN_X = 150.0
local ROW_Y_START = 150.0
local ROW_SPACING = 110.0 -- 4 rows (3 branch rows + the boss's own) must clear the description text around y=570

local MOOK_RADIUS = 24.0
local MINIBOSS_RADIUS = 34.0
local BOSS_RADIUS = 52.0

local ORGANIZER_MOTIF_COLOR = { 0.6, 0.8, 1.0 }
local COLOR_DONE = { 0.35, 0.9, 0.55 }
local COLOR_LOCKED_TINT = { 0.35, 0.35, 0.42, 0.6 }
local COLOR_DONE_TINT = { 0.8, 0.85, 0.8, 1.0 }

local NOT_AVAILABLE_DURATION = 1.8
local TOKEN_MOVE_DURATION = 0.35 -- Godot's own Tween duration (EASE_IN_OUT/TRANS_SINE — see ease_in_out_sine())

local TILE_TYPE = { MOOK = "mook", MINIBOSS = "miniboss", BOSS = "boss" }

-- Parallel arrays, one entry per tile — built once in campaign_map.enter()
-- from the character's branch data (mini_branches.size()*3 + 1 tiles: every
-- branch's mook_1/mook_2/rival back to back, then the organizer).
local tile_types, tile_encounters, tile_branches, tile_mook_index, tile_mook_number, tile_positions

-- Arrow-key "walk the map" state (2026-08-30 on the Godot side) — distinct
-- from campaign_context.campaign_step (the AUTHORITATIVE next-fight
-- position, only ever advanced by actually winning): display_step is just
-- where the token is currently STANDING, which the player can freely walk
-- backward over already-done tiles to review, but never past campaign_step.
local display_step
local token_draw_position -- animated {x, y}
local is_tweening = false
local tween_elapsed, tween_duration, tween_start_pos, tween_end_pos, tween_target_step, tween_target_node_id

local confirm_dialog_active = false
local confirm_prev = true -- seeded true, same carryover-guard convention every menu in this project uses
local arrow_prev = { up = false, down = false, left = false, right = false }
local pulse_time = 0.0

local not_available_message, not_available_timer

-- Graph mode (see the header comment) — nil/empty/false whenever the
-- current character has no exported map with path_nodes+connections;
-- load_graph_data() populates all of these, assign_graph_encounters()
-- fills tile_types/tile_encounters/etc. (the SAME arrays the procedural
-- mode uses, for the status-marker overlay) plus tile_node_ids (parallel,
-- which combat CASE id each tile_positions[i] belongs to).
--
-- graph_nodes: id -> {id, x, y, type, index}. type "" = relay waypoint;
--   otherwise "mook"/"miniboss"/"boss"/"custom_depart"/"custom_bonus"/etc.
-- graph_adj: id -> {neighbor_id, ...}, undirected.
-- graph_combat_encounters: id -> RivalEncounterData, combat nodes only.
-- current_node_id/previous_node_id: token position + one-step retreat trail.
-- resolved_ids: id -> true for every combat node already won.
local graph_mode = false
local graph_nodes, graph_adj, graph_combat_encounters = {}, {}, {}
local tile_node_ids
local map_background
local current_node_id, previous_node_id = "", ""

-- 2026-09-27 (Camil: "il me faudrait un mode 'triche' qui me permet de
-- passer au travers des cases que je n'ai pas encore conquises... en
-- appuyant sur 'k', qui switch ON/OFF le mode 'fantome'") — debug-only
-- navigation bypass; deliberately NOT reset in campaign_map.enter() (a map
-- re-entry happens after every single fight) so it stays on across a whole
-- exploration session until toggled off again, same as how a "walk through
-- walls" cheat behaves elsewhere. See target_step_for_direction()/
-- can_move_to_graph_neighbor(), the two choke points every arrow-move
-- request already funnels through for both map modes.
local ghost_mode = false
local resolved_ids = {}
local depart_node_id = ""

local function opponent_name(encounter)
	return (encounter and encounter.opponent) and encounter.opponent.display_name or "?"
end

-- Every tile_* array is explicitly 0-INDEXED (tile_types[0] is the first
-- tile), matching campaign_context.campaign_step's own 0-based convention
-- and tile_positions' own indexing below — table.insert()'s natural
-- 1-based append would silently shift every lookup off by one against
-- those (a real bug caught in review, not a style choice).
local function build_tiles()
	tile_types, tile_encounters, tile_branches, tile_mook_index, tile_mook_number = {}, {}, {}, {}, {}
	local campaign = campaign_context.campaign
	local i = 0
	local mook_number = 0
	local function push(tile_type, encounter, branch, mook_index, mook_num)
		tile_types[i] = tile_type
		tile_encounters[i] = encounter
		tile_branches[i] = branch
		tile_mook_index[i] = mook_index
		tile_mook_number[i] = mook_num
		i = i + 1
	end
	for _, branch in ipairs(campaign.mini_branches) do
		mook_number = mook_number + 1
		push(TILE_TYPE.MOOK, branch.mook_1, branch, 1, mook_number)
		mook_number = mook_number + 1
		push(TILE_TYPE.MOOK, branch.mook_2, branch, 2, mook_number)
		push(TILE_TYPE.MINIBOSS, branch.rival, branch, 0, 0)
	end
	push(TILE_TYPE.BOSS, campaign.organizer_encounter, nil, 0, 0)
end

-- #tile_types (Lua's length operator) only works reliably on a 1-indexed,
-- gap-free array — every tile_* array here is 0-indexed instead, so every
-- "how many tiles" call site goes through this.
local function tile_count()
	local n = 0
	while tile_types[n] ~= nil do
		n = n + 1
	end
	return n
end

-- Boustrophedon: tiles snake across rows of COLS, alternating direction
-- each row like a Mario world map, deliberately NOT special-casing the
-- organizer/last tile, so every consecutive pair of tiles differs in
-- exactly one axis (pure horizontal within a row, pure vertical between
-- rows) and the straight road texture never needs a corner piece.
local function procedural_tile_position(i)
	local row = math.floor(i / COLS)
	local col = i % COLS
	local display_col = (row % 2 == 0) and col or (COLS - 1 - col)
	local x = MARGIN_X + display_col * ((1280.0 - MARGIN_X * 2.0) / (COLS - 1))
	local y = ROW_Y_START + row * ROW_SPACING
	return { x = x, y = y }
end

local function build_layout()
	tile_positions = {}
	for i = 0, tile_count() - 1 do
		tile_positions[i] = procedural_tile_position(i)
	end
end

local function get_position_for_step(step)
	if tile_positions[step] then
		return tile_positions[step]
	end
	return tile_positions[0] or { x = 0.0, y = 0.0 }
end

local function tile_status(i)
	local current = campaign_context.campaign_step
	if i < current then
		return "done"
	elseif i == current then
		return "current"
	end
	return "locked"
end

local function tile_radius(i)
	if tile_types[i] == TILE_TYPE.MOOK then
		return MOOK_RADIUS
	elseif tile_types[i] == TILE_TYPE.MINIBOSS then
		return MINIBOSS_RADIUS
	end
	return BOSS_RADIUS
end

local function tile_texture(i)
	if tile_types[i] == TILE_TYPE.MOOK then
		-- mook_number counts up unbounded across the whole path; wrap it so
		-- any branch count (Mitrailleur's 7 branches = 14 mooks) stays in
		-- range, just cycling the art (match_arena_node.gd's own fix).
		return assets.worldmap.mook[((tile_mook_number[i] - 1) % 20) + 1]
	elseif tile_types[i] == TILE_TYPE.MINIBOSS then
		return assets.worldmap.rival_tower
	end
	return assets.worldmap.boss_castle
end

local function map_png_path(character_id)
	return "assets/worldmap/maps/" .. character_id .. "_map.png"
end

local function map_json_path(character_id)
	return "assets/worldmap/maps/" .. character_id .. "_map.json"
end

-- Reads+decodes a character's map JSON, or nil if it doesn't exist / fails
-- to parse — every caller treats that as "no map, fall back" rather than
-- erroring (matches Godot's own JSON.parse_string() returning null).
local function read_map_json(character_id)
	local path = map_json_path(character_id)
	if not love.filesystem.getInfo(path) then
		return nil
	end
	local content = love.filesystem.read(path)
	if not content then
		return nil
	end
	local data = json.decode(content)
	if type(data) ~= "table" then
		return nil
	end
	return data
end

local function add_undirected_edge(a, b)
	if graph_adj[a] then
		local already = false
		for _, n in ipairs(graph_adj[a]) do
			if n == b then
				already = true
				break
			end
		end
		if not already then
			table.insert(graph_adj[a], b)
		end
	end
end

-- Loads the graph structure from the character's exported JSON when it has
-- path_nodes + connections fields. Populates graph_nodes/graph_adj/
-- depart_node_id. Returns true if graph mode was successfully detected —
-- false for the old branch fallback (no map, or a map missing those
-- fields), same "try the next mode down" contract as Godot's own
-- _load_graph_data().
local function load_graph_data(character_id)
	graph_nodes, graph_adj, depart_node_id = {}, {}, ""
	if not love.filesystem.getInfo(map_png_path(character_id)) then
		return false
	end
	local data = read_map_json(character_id)
	if not data then
		return false
	end
	if type(data.path_nodes) ~= "table" or type(data.connections) ~= "table" or type(data.cases) ~= "table" then
		return false
	end

	for _, c in ipairs(data.cases) do
		if type(c) == "table" and c.id then
			local nid = tostring(c.id)
			local ctype = c.type or ""
			graph_nodes[nid] = { id = nid, x = c.x or 0.0, y = c.y or 0.0, type = ctype, index = c.index or 9999 }
			graph_adj[nid] = {}
			if ctype == "custom_depart" or ctype == "depart" then
				depart_node_id = nid
			end
		end
	end
	for _, p in ipairs(data.path_nodes) do
		if type(p) == "table" and p.id then
			local nid = tostring(p.id)
			graph_nodes[nid] = { id = nid, x = p.x or 0.0, y = p.y or 0.0, type = "", index = 9999 }
			graph_adj[nid] = {}
		end
	end
	for _, conn in ipairs(data.connections) do
		if type(conn) == "table" and conn[1] and conn[2] then
			local a, b = tostring(conn[1]), tostring(conn[2])
			add_undirected_edge(a, b)
			add_undirected_edge(b, a)
		end
	end
	return true
end

-- Assigns encounters to the graph's combat nodes using the same pool logic
-- as the branch fallback (mook_pool/rival_pool consumed in JSON index
-- order), and fills the SAME tile_types/tile_encounters/etc. arrays that
-- mode uses for the status-marker overlay, plus tile_node_ids (parallel —
-- which case id each tile_positions[i] belongs to).
local function assign_graph_encounters()
	local mook_pool, rival_pool = {}, {}
	for _, branch in ipairs(campaign_context.campaign.mini_branches) do
		table.insert(mook_pool, branch.mook_1)
		table.insert(mook_pool, branch.mook_2)
		table.insert(rival_pool, branch.rival)
	end

	local combat_nodes = {}
	for _, node in pairs(graph_nodes) do
		if node.type == "mook" or node.type == "miniboss" or node.type == "boss" then
			table.insert(combat_nodes, node)
		end
	end
	table.sort(combat_nodes, function(a, b) return a.index < b.index end)

	tile_types, tile_encounters, tile_branches, tile_mook_index, tile_mook_number, tile_node_ids = {}, {}, {}, {}, {}, {}
	graph_combat_encounters = {}
	local mook_idx, rival_idx, mook_number = 0, 0, 0
	local encounter_seq = {}
	local i = 0

	for _, node in ipairs(combat_nodes) do
		local nid = node.id
		local enc, tile_type, mook_num = nil, nil, 0
		if node.type == "mook" then
			mook_number = mook_number + 1
			enc = mook_pool[mook_idx + 1] -- 1-indexed Lua array, mook_idx is 0-based
			mook_idx = mook_idx + 1
			tile_type, mook_num = TILE_TYPE.MOOK, mook_number
		elseif node.type == "miniboss" then
			enc = rival_pool[rival_idx + 1]
			rival_idx = rival_idx + 1
			tile_type = TILE_TYPE.MINIBOSS
		else -- "boss"
			enc = campaign_context.campaign.organizer_encounter
			tile_type = TILE_TYPE.BOSS
		end
		graph_combat_encounters[nid] = enc
		tile_types[i] = tile_type
		tile_mook_number[i] = mook_num
		tile_node_ids[i] = nid
		tile_encounters[i] = enc
		tile_branches[i] = nil
		tile_mook_index[i] = 0
		table.insert(encounter_seq, enc)
		i = i + 1
	end

	campaign_context.set_encounter_sequence(encounter_seq)
end

local function get_graph_node_position(nid)
	local n = graph_nodes[nid]
	if not n then
		return { x = 0.0, y = 0.0 }
	end
	return { x = n.x, y = n.y }
end

local function is_graph_combat_node(nid)
	local n = graph_nodes[nid]
	local t = n and n.type or ""
	return t == "mook" or t == "miniboss" or t == "boss"
end

local function is_node_resolved(nid)
	return resolved_ids[nid] == true
end

-- The only movement restriction: standing on an UNRESOLVED combat node
-- means the player may only retreat to previous_node_id (where they came
-- from). With no previous node (e.g. map reload after a loss), retreat is
-- allowed to any relay/resolved neighbor so the player is never hard-locked.
local function can_move_to_graph_neighbor(neighbor_id)
	if ghost_mode then
		return true
	end
	if is_graph_combat_node(current_node_id) and not is_node_resolved(current_node_id) then
		if previous_node_id ~= "" then
			return neighbor_id == previous_node_id
		end
		if is_node_resolved(neighbor_id) then
			return true
		end
		return not is_graph_combat_node(neighbor_id)
	end
	return true -- from resolved/relay/depart: all neighbors accessible
end

-- Tries a PNG straight off disk first (love.filesystem.getInfo already
-- confirmed it exists in load_graph_data()) — wrapped in pcall since a
-- corrupt/unreadable file would otherwise crash the whole map screen.
local function try_load_map_background(character_id)
	local ok, image = pcall(love.graphics.newImage, map_png_path(character_id))
	if ok then
		return image
	end
	return nil
end

function campaign_map.enter()
	confirm_prev = true
	not_available_message = nil
	not_available_timer = 0.0
	arrow_prev = { up = false, down = false, left = false, right = false }
	pulse_time = 0.0
	map_background = nil

	local character_id = campaign_context.campaign.character.id

	-- Try graph mode first (a real Atelier Cartographe export with
	-- path_nodes+connections) — falls back to the procedural branch layout
	-- for every other character, unchanged from before.
	graph_mode = load_graph_data(character_id)
	campaign_context.is_graph_mode = graph_mode

	if graph_mode then
		assign_graph_encounters()
		map_background = try_load_map_background(character_id)
		tile_positions = {}
		for i = 0, tile_count() - 1 do
			tile_positions[i] = get_graph_node_position(tile_node_ids[i])
		end

		resolved_ids = {}
		for _, cid in ipairs(campaign_save.get_resolved_case_ids(character_id)) do
			resolved_ids[tostring(cid)] = true
		end
		local restore_id = campaign_context.current_graph_node_id
		if restore_id ~= "" and graph_nodes[restore_id] then
			current_node_id = restore_id
		elseif depart_node_id ~= "" then
			current_node_id = depart_node_id
		elseif tile_node_ids[0] then
			current_node_id = tile_node_ids[0]
		end
		previous_node_id = ""
		token_draw_position = get_graph_node_position(current_node_id)
		is_tweening = false
		confirm_dialog_active = false
		-- Restoring after a loss: the node is still unresolved — show the
		-- fight dialog again immediately so the player can retry.
		if is_graph_combat_node(current_node_id) and not is_node_resolved(current_node_id) then
			confirm_dialog_active = true
			confirm_prev = true
		end
		return
	end

	build_tiles()
	build_layout()

	-- Always re-sync from the save file on arrival (character-select/
	-- title's "Continuer", or bouncing back here after a fight) — cheap,
	-- and the one source of truth for "how far along is this character"
	-- regardless of how this scene was reached.
	local step = mathx.clampf(campaign_save.get_campaign_progress(character_id), 0, tile_count() - 1)
	campaign_context.enter_campaign(campaign_context.campaign, math.floor(step))

	display_step = campaign_context.campaign_step
	token_draw_position = get_position_for_step(display_step)
	is_tweening = false
	confirm_dialog_active = false
	if display_step >= 0 and display_step == campaign_context.campaign_step and display_step < tile_count() then
		confirm_dialog_active = true
		confirm_prev = true
	end
end

local function refresh()
	-- Nothing to precompute — description/hint text is derived live in
	-- draw() from display_step/campaign_step, same as the rest of this
	-- screen; kept as a named no-op call site so future state-driven
	-- refresh logic (matching Godot's own _refresh()) has an obvious home.
end

local function direction_key_down(direction)
	-- Godot's own WASD-widening bug fix (2026-08-31, Ben's playtest: "les
	-- fleches, c'est uniquement J2... J1 c'est WASD") — the map has exactly
	-- one navigator, so it accepts both.
	if direction == "up" then
		return input.solo_up()
	elseif direction == "down" then
		return input.solo_down()
	elseif direction == "left" then
		return input.solo_left()
	end
	return input.solo_right()
end

local function dominant_direction(from_pos, to_pos)
	local dx, dy = to_pos.x - from_pos.x, to_pos.y - from_pos.y
	if math.abs(dx) >= math.abs(dy) then
		return dx > 0.0 and "right" or "left"
	end
	return dy > 0.0 and "down" or "up"
end

local function sync_arrow_prev()
	arrow_prev.up = direction_key_down("up")
	arrow_prev.down = direction_key_down("down")
	arrow_prev.left = direction_key_down("left")
	arrow_prev.right = direction_key_down("right")
end

-- Navigation rules (unchanged from Godot): can always go BACK a step; can
-- only go FORWARD onto a step already cleared (display_step < campaign_
-- step) — never skip past the next unresolved fight without winning it.
local function target_step_for_direction(direction)
	local cur_pos = get_position_for_step(display_step)

	if display_step > 0 then
		local prev_pos = get_position_for_step(display_step - 1)
		if dominant_direction(cur_pos, prev_pos) == direction then
			return display_step - 1
		end
	end

	local can_go_forward = (ghost_mode or display_step < campaign_context.campaign_step) and (display_step + 1) < tile_count()
	if can_go_forward then
		local next_pos = get_position_for_step(display_step + 1)
		if dominant_direction(cur_pos, next_pos) == direction then
			return display_step + 1
		end
	end

	return display_step
end

local function hide_confirm_dialog()
	confirm_dialog_active = false
end

local function show_confirm_dialog()
	confirm_dialog_active = true
	confirm_prev = true -- seed the carryover guard so a held key doesn't insta-trigger
end

local function on_arrive_at_display_step(arrived_step)
	if arrived_step < 0 or arrived_step >= tile_count() then
		return
	end
	if arrived_step ~= campaign_context.campaign_step then
		return -- already-done tile — just visiting, no combat prompt
	end
	show_confirm_dialog()
end

local function move_to_display_step(target_step)
	hide_confirm_dialog()
	display_step = target_step
	is_tweening = true
	tween_elapsed = 0.0
	tween_duration = TOKEN_MOVE_DURATION
	tween_start_pos = { x = token_draw_position.x, y = token_draw_position.y }
	tween_end_pos = get_position_for_step(target_step)
	tween_target_step = target_step
end

local function handle_arrow_navigation()
	local directions = { "up", "down", "left", "right" }
	local moved = false
	for _, direction in ipairs(directions) do
		local pressed_now = direction_key_down(direction)
		local was_pressed = arrow_prev[direction]
		if pressed_now and not was_pressed and not moved then
			local target = target_step_for_direction(direction)
			if target ~= display_step then
				move_to_display_step(target)
				moved = true
			end
		end
		arrow_prev[direction] = pressed_now
	end
end

-- For the given direction, finds the NEAREST neighbor of current_node_id
-- whose dominant screen direction matches and that can_move_to_graph_
-- neighbor() allows. Returns "" if none found.
local function target_node_for_graph_direction(direction)
	local cur_pos = get_graph_node_position(current_node_id)
	local best_id, best_dist = "", math.huge
	for _, neighbor_id in ipairs(graph_adj[current_node_id] or {}) do
		if can_move_to_graph_neighbor(neighbor_id) then
			local neighbor_pos = get_graph_node_position(neighbor_id)
			if dominant_direction(cur_pos, neighbor_pos) == direction then
				local dx, dy = neighbor_pos.x - cur_pos.x, neighbor_pos.y - cur_pos.y
				local dist = math.sqrt(dx * dx + dy * dy)
				if dist < best_dist then
					best_dist = dist
					best_id = neighbor_id
				end
			end
		end
	end
	return best_id
end

local function on_arrive_at_graph_node(node_id)
	if not is_graph_combat_node(node_id) then
		return -- relay, depart, bonus — no dialog
	end
	if is_node_resolved(node_id) then
		return -- already won — just visiting
	end
	show_confirm_dialog()
end

local function move_to_graph_node(target_id)
	hide_confirm_dialog()
	previous_node_id = current_node_id
	current_node_id = target_id
	is_tweening = true
	tween_elapsed = 0.0
	tween_duration = TOKEN_MOVE_DURATION
	tween_start_pos = { x = token_draw_position.x, y = token_draw_position.y }
	tween_end_pos = get_graph_node_position(target_id)
	tween_target_node_id = target_id
end

local function handle_graph_arrow_navigation()
	local directions = { "up", "down", "left", "right" }
	local moved = false
	for _, direction in ipairs(directions) do
		local pressed_now = direction_key_down(direction)
		local was_pressed = arrow_prev[direction]
		if pressed_now and not was_pressed and not moved then
			local target_id = target_node_for_graph_direction(direction)
			if target_id ~= "" then
				move_to_graph_node(target_id)
				moved = true
			end
		end
		arrow_prev[direction] = pressed_now
	end
end

local function confirm_current_tile()
	local encounter
	if graph_mode then
		encounter = graph_combat_encounters[current_node_id]
		if not encounter then
			return -- defensive: shouldn't happen for a valid combat node
		end
		campaign_context.current_graph_node_id = current_node_id
		campaign_context.pending_graph_encounter = encounter
	else
		encounter = tile_encounters[campaign_context.campaign_step]
		if not encounter then
			return
		end
	end
	if encounter.challenge_type == "breakout" then
		screen_manager.switch_to(breakout)
	elseif encounter.challenge_type == "space_invaders" then
		screen_manager.switch_to(space_invaders)
	elseif encounter.challenge_type == "gradius" then
		screen_manager.switch_to(gradius)
	elseif encounter.challenge_type == "combat" then
		screen_manager.switch_to(match_arena)
	else
		not_available_message = string.format(
			"Le mini-jeu '%s' n'est pas encore disponible dans ce portage.",
			encounter.challenge_type
		)
		not_available_timer = NOT_AVAILABLE_DURATION
	end
end

-- Godot's Tween.EASE_IN_OUT + TRANS_SINE.
local function ease_in_out_sine(t)
	return -(math.cos(math.pi * t) - 1.0) / 2.0
end

function campaign_map.update(dt)
	pulse_time = pulse_time + dt

	if not_available_timer and not_available_timer > 0.0 then
		not_available_timer = not_available_timer - dt
		if not_available_timer <= 0.0 then
			not_available_message = nil
		end
	end

	if is_tweening then
		tween_elapsed = tween_elapsed + dt
		local t = mathx.clampf(tween_elapsed / tween_duration, 0.0, 1.0)
		local eased = ease_in_out_sine(t)
		token_draw_position = {
			x = mathx.lerp(tween_start_pos.x, tween_end_pos.x, eased),
			y = mathx.lerp(tween_start_pos.y, tween_end_pos.y, eased),
		}
		sync_arrow_prev() -- keep edge-detection state fresh so it can't fire a phantom move the instant the tween ends
		if t >= 1.0 then
			is_tweening = false
			if graph_mode then
				on_arrive_at_graph_node(tween_target_node_id)
			else
				on_arrive_at_display_step(tween_target_step)
			end
		end
		return
	end

	if confirm_dialog_active then
		local confirm = input.solo_confirm()
		if confirm and not confirm_prev then
			confirm_current_tile()
		end
		confirm_prev = confirm
		-- Graph mode: an arrow key press while the dialog is open dismisses
		-- it and immediately starts retreating (Godot's own 2026-08-31
		-- shortcut — "the player chose no, go back"). Linear mode has no
		-- such shortcut; arrows just stay tracked so no phantom edge fires
		-- once the dialog closes.
		if graph_mode then
			for _, direction in ipairs({ "up", "down", "left", "right" }) do
				local pressed_now = direction_key_down(direction)
				if pressed_now and not arrow_prev[direction] then
					local target_id = target_node_for_graph_direction(direction)
					if target_id ~= "" then
						hide_confirm_dialog()
						move_to_graph_node(target_id)
						break
					end
				end
			end
		end
		sync_arrow_prev()
		return
	end

	if graph_mode then
		handle_graph_arrow_navigation()
	else
		handle_arrow_navigation()
	end
end

local function draw_path_segment(a, b, tint)
	local length = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
	if length < 1.0 then
		return
	end
	local native_w, native_h = assets.worldmap.road_straight:getDimensions()
	local angle = math.atan(b.y - a.y, b.x - a.x) - math.pi / 2.0
	love.graphics.setColor(tint[1], tint[2], tint[3], tint[4] or 1.0)
	draw_utils.draw_stretched(assets.worldmap.road_straight, (a.x + b.x) / 2.0, (a.y + b.y) / 2.0, native_w, length, false, angle)
end

local function draw_current_pulse(center, base_radius)
	local pulse_radius = base_radius + 10.0 + math.sin(pulse_time * 4.0) * 4.0
	love.graphics.setColor(1, 1, 1, 0.8)
	love.graphics.setLineWidth(3.0)
	love.graphics.circle("line", center.x, center.y, pulse_radius, 40)
	love.graphics.setLineWidth(1.0)
end

local function draw_tile(i)
	local center = tile_positions[i]
	local radius = tile_radius(i)
	local status = tile_status(i)
	local tex = tile_texture(i)

	local tint = { 1.0, 1.0, 1.0, 1.0 }
	if status == "locked" then
		tint = COLOR_LOCKED_TINT
	elseif status == "done" then
		tint = COLOR_DONE_TINT
	end
	love.graphics.setColor(tint[1], tint[2], tint[3], tint[4] or 1.0)
	draw_utils.draw_fit_inside(tex, center.x - radius, center.y - radius, radius * 2.0, radius * 2.0, 0.0)

	if status == "current" then
		draw_current_pulse(center, radius)
	end
end

-- The "you are here" marker — a small creature icon floating (and gently
-- bobbing) above the current tile, Mario-overworld-sprite style. `center`
-- is token_draw_position (animated), not necessarily the tile's own (x,y).
local function draw_player_token(center, base_radius)
	local bob = math.sin(pulse_time * 3.0) * 4.0
	local native_w, native_h = assets.worldmap.player_token:getDimensions()
	local token_w = 34.0
	local token_h = 34.0 * native_h / native_w
	love.graphics.setColor(1, 1, 1, 1)
	draw_utils.draw_stretched(
		assets.worldmap.player_token,
		center.x,
		center.y - base_radius - token_h / 2.0 - 6.0 + bob,
		token_w,
		token_h
	)
end

-- Real-map overlay (graph mode): the PNG art already shows the tile, so a
-- marker only needs to communicate STATUS (done/current/locked), not
-- identity — matches campaign_map_node.gd's own _draw_case_marker().
local function draw_case_marker(i)
	local center = tile_positions[i]
	local status
	if is_node_resolved(tile_node_ids[i]) then
		status = "done"
	elseif tile_node_ids[i] == current_node_id then
		status = "current"
	else
		status = "locked"
	end
	if status == "done" then
		love.graphics.setColor(COLOR_DONE[1], COLOR_DONE[2], COLOR_DONE[3])
		love.graphics.circle("fill", center.x, center.y, 11.0)
		love.graphics.setColor(0, 0, 0, 0.35)
		love.graphics.setLineWidth(2.0)
		love.graphics.circle("line", center.x, center.y, 11.0)
		love.graphics.setLineWidth(1.0)
	elseif status == "current" then
		draw_current_pulse(center, 18.0)
	else
		love.graphics.setColor(0.1, 0.1, 0.14, 0.6)
		love.graphics.circle("fill", center.x, center.y, 9.0)
		love.graphics.setColor(1, 1, 1, 0.25)
		love.graphics.setLineWidth(1.5)
		love.graphics.circle("line", center.x, center.y, 9.0)
		love.graphics.setLineWidth(1.0)
	end
end

-- 2026-09-15 (Camil: "pour les cases de la worldmap avec space invaders, ce
-- serait bien de mettre un monstre rouge (ceux du jeu) au dessus de la
-- case, qui bouge un peu en flottant" / idem Breakout avec une brique) — a
-- small bobbing icon over any tile whose RivalEncounterData routes to a
-- mini-jeu, mirroring campaign_map_node.gd's own _draw_challenge_icon().
-- Reuses the real alien sprite (tinted the same red space_invaders.lua's
-- own ALIEN_COLOR uses) rather than inventing new art; the brick is a
-- plain engine-drawn shape since Breakout's own bricks are themselves
-- plain colored rectangles, no dedicated art either. Works for both graph
-- mode (real exported map, fixed icon size) and the procedural fallback
-- (per-tile radius via tile_radius()).
local CHALLENGE_MONSTER_COLOR = { 0.85, 0.3, 0.35 } -- matches space_invaders.lua's own ALIEN_COLOR
local function draw_challenge_icon(i)
	local encounter = tile_encounters[i]
	if not encounter or (encounter.challenge_type ~= "space_invaders" and encounter.challenge_type ~= "breakout" and encounter.challenge_type ~= "gradius") then
		return
	end
	local center = tile_positions[i]
	local radius = graph_mode and 18.0 or tile_radius(i)
	local bob = math.sin(pulse_time * 2.4) * 5.0
	local icon_x, icon_y = center.x, center.y - radius - 16.0 + bob
	if encounter.challenge_type == "space_invaders" then
		local alien_image = assets.aliens[1]
		local native_w, native_h = alien_image:getDimensions()
		local size_w, size_h = 22.0, 22.0 * native_h / native_w
		love.graphics.setColor(CHALLENGE_MONSTER_COLOR[1], CHALLENGE_MONSTER_COLOR[2], CHALLENGE_MONSTER_COLOR[3])
		draw_utils.draw_stretched(alien_image, icon_x, icon_y, size_w, size_h)
	elseif encounter.challenge_type == "gradius" then
		-- 2026-09-20 (Camil: "un petit vaisseau qui apparait (par exemple le
		-- drone) [...] qui flotte comme pour space invaders et breakout") —
		-- the real Drone sprite (gradius.lua's own enemy art) now that it
		-- exists, same treatment as Space Invaders' real alien icon above
		-- (plain white tint — the art is already colored, no extra tint
		-- needed, unlike the old vector-triangle placeholder this replaces).
		local drone_image = assets.gradius_drone
		local native_w, native_h = drone_image:getDimensions()
		local size_w, size_h = 22.0, 22.0 * native_h / native_w
		love.graphics.setColor(1.0, 1.0, 1.0)
		draw_utils.draw_stretched(drone_image, icon_x, icon_y, size_w, size_h)
	else
		local w, h = 20.0, 12.0
		love.graphics.setColor(0.75, 0.35, 0.25)
		love.graphics.rectangle("fill", icon_x - w / 2.0, icon_y - h / 2.0, w, h)
		love.graphics.setColor(0.35, 0.15, 0.1)
		love.graphics.setLineWidth(1.5)
		love.graphics.rectangle("line", icon_x - w / 2.0, icon_y - h / 2.0, w, h)
		love.graphics.line(icon_x - w / 2.0, icon_y, icon_x + w / 2.0, icon_y)
		love.graphics.setLineWidth(1.0)
	end
end

local function graph_resolved_count()
	local n = 0
	for i = 0, tile_count() - 1 do
		if is_node_resolved(tile_node_ids[i]) then
			n = n + 1
		end
	end
	return n
end

-- Graph mode's own description text — based on the node the token is
-- ACTUALLY standing on (current_node_id); there is no separate "viewing
-- vs. authoritative" split here the way linear mode's display_step has,
-- since every node (including already-resolved ones) can be revisited
-- freely and always describes itself.
local function graph_description_lines()
	local node = graph_nodes[current_node_id] or {}
	local ntype = node.type or ""
	if ntype == "custom_depart" or ntype == "depart" then
		return { "Debut du chemin — utilisez les fleches pour explorer." }
	elseif ntype == "" then
		return { "En transit..." }
	end
	local encounter = graph_combat_encounters[current_node_id]
	if is_node_resolved(current_node_id) then
		return { "[Termine] vs " .. opponent_name(encounter) }
	end
	if not encounter then
		return { "Case inconnue" }
	end
	if ntype == "boss" then
		return { "Combat final : " .. opponent_name(encounter) .. " (Organisateur)" }
	elseif ntype == "miniboss" then
		return { "Rival : vs " .. opponent_name(encounter) }
	end
	return { "Combat : vs " .. opponent_name(encounter) }
end

function campaign_map.draw()
	local campaign = campaign_context.campaign
	local total = tile_count()
	local character_id = campaign.character.id

	love.graphics.setColor(1, 1, 1)
	love.graphics.printf(campaign.character.display_name .. " — Campagne", 0, 24, 1280, "center")
	love.graphics.setColor(0.8, 0.8, 0.85)
	if graph_mode then
		love.graphics.printf(
			string.format("Devise : %d      Victoires : %d/%d", campaign_save.get_currency(character_id), graph_resolved_count(), total),
			0, 52, 1280, "center"
		)
	else
		love.graphics.printf(
			string.format("Devise : %d      Etape %d/%d", campaign_save.get_currency(character_id), math.min(campaign_context.campaign_step + 1, total), total),
			0, 52, 1280, "center"
		)
	end

	if graph_mode and map_background then
		-- Real exported map: terrain/road/tile art already baked into the
		-- PNG — just lay it down as-is and overlay small status markers.
		love.graphics.setColor(1, 1, 1)
		love.graphics.draw(map_background, 0, 0)
		for i = 0, total - 1 do
			draw_case_marker(i)
			draw_challenge_icon(i)
		end
		draw_player_token(token_draw_position, 18.0)
	else
		-- Fallback: no custom map for this character (or its background
		-- failed to load) — the procedural grass/road/icon rendering.
		love.graphics.setColor(1, 1, 1)
		draw_utils.draw_cover(assets.worldmap.grass_bg, 0.0, 0.0, 1280.0, 720.0)
		local progress = campaign_context.campaign_step / math.max(total - 1, 1)
		local tint_alpha = mathx.clampf(progress, 0.0, 1.0) * 0.35
		love.graphics.setColor(ORGANIZER_MOTIF_COLOR[1], ORGANIZER_MOTIF_COLOR[2], ORGANIZER_MOTIF_COLOR[3], tint_alpha)
		love.graphics.rectangle("fill", 0.0, 0.0, 1280.0, 720.0)

		for i = 0, total - 2 do
			local lit = i < campaign_context.campaign_step
			draw_path_segment(tile_positions[i], tile_positions[i + 1], lit and COLOR_DONE or { 1.0, 1.0, 1.0, 0.55 })
		end

		for i = 0, total - 1 do
			draw_tile(i)
			draw_challenge_icon(i)
		end

		if total > 0 then
			local tok_radius = MOOK_RADIUS
			if display_step >= 0 and display_step < total then
				tok_radius = tile_radius(display_step)
			end
			draw_player_token(token_draw_position, tok_radius)
		end
	end

	local lines
	if graph_mode then
		lines = graph_description_lines()
	else
		-- Current encounter details — reflects the tile the player is
		-- LOOKING AT (display_step), not necessarily the next fight to
		-- trigger (campaign_step).
		local real_step = campaign_context.campaign_step
		local viewed = display_step
		lines = {}
		if viewed >= total then
			table.insert(lines, "Campagne terminee !")
		elseif viewed >= 0 then
			local done_prefix = (viewed ~= real_step) and "[Termine] " or ""
			local encounter = tile_encounters[viewed]
			if tile_types[viewed] == TILE_TYPE.MOOK then
				local branch = tile_branches[viewed]
				if branch then
					table.insert(lines, string.format("%sCombat : %s — Sous-adversaire %d/2 (vs %s)", done_prefix, branch.display_name, tile_mook_index[viewed], opponent_name(encounter)))
				else
					table.insert(lines, string.format("%sCombat %d (vs %s)", done_prefix, tile_mook_number[viewed], opponent_name(encounter)))
				end
			elseif tile_types[viewed] == TILE_TYPE.MINIBOSS then
				local twist_suffix = (encounter and encounter.twist) and (" (Twist : " .. encounter.twist.display_name .. ")") or ""
				table.insert(lines, string.format("%sRival : %s%s", done_prefix, opponent_name(encounter), twist_suffix))
			else
				table.insert(lines, done_prefix .. "Combat final : l'Organisateur du tournoi.")
			end
			if encounter and viewed == real_step then
				if encounter.is_mook then
					table.insert(lines, string.format("Recompense : +%d devise", encounter.reward_currency))
				elseif encounter.unlock_reward then
					table.insert(lines, "Recompense : " .. encounter.unlock_reward.display_name .. " (passif)")
				end
			end
		end
	end

	love.graphics.setColor(0.9, 0.9, 0.95)
	love.graphics.printf(table.concat(lines, "\n"), 240, 545, 800, "center")

	if not_available_message then
		love.graphics.setColor(1.0, 0.55, 0.5)
		love.graphics.printf(not_available_message, 160, 625, 960, "center")
	end

	if confirm_dialog_active then
		love.graphics.setColor(0, 0, 0, 0.55)
		love.graphics.rectangle("fill", 0, 0, 1280, 720)
		local panel_x, panel_y, panel_w, panel_h = 1280.0 / 2.0 - 260.0, 720.0 / 2.0 - 80.0, 520.0, 160.0
		love.graphics.setColor(0.13, 0.13, 0.17, 0.97)
		love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h)
		love.graphics.setColor(0.4, 0.4, 0.48)
		love.graphics.setLineWidth(2.0)
		love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h)
		love.graphics.setLineWidth(1.0)
		love.graphics.setColor(0.95, 0.96, 1.0)
		love.graphics.printf("Voulez-vous declencher le combat ?", panel_x, panel_y + 24.0, panel_w, "center")
		love.graphics.setColor(0.6, 0.9, 0.6)
		love.graphics.printf("Oui (Espace / Entree)", panel_x, panel_y + 90.0, panel_w / 2.0, "center")
		love.graphics.setColor(0.9, 0.6, 0.6)
		love.graphics.printf("Non (Echap)", panel_x + panel_w / 2.0, panel_y + 90.0, panel_w / 2.0, "center")
	end

	love.graphics.setColor(0.65, 0.65, 0.7)
	if confirm_dialog_active then
		love.graphics.printf("Espace/Entree : lancer le combat  |  Echap : annuler", 0, 660, 1280, "center")
	elseif graph_mode then
		love.graphics.printf(
			string.format("Fleches/WASD : naviguer  |  Victoires : %d/%d  |  Echap : retour", graph_resolved_count(), total),
			0, 660, 1280, "center"
		)
	else
		love.graphics.printf(
			string.format("Fleches/WASD : naviguer  |  Etape %d/%d  |  Echap : retour", math.min(campaign_context.campaign_step + 1, total), total),
			0, 660, 1280, "center"
		)
	end
end

function campaign_map.keypressed(key)
	if key == "k" then
		-- Dev/debug shortcut (Camil, 2026-09-27): "mode fantome" — checked
		-- before the confirm_dialog_active gate below so it always works,
		-- even while a fight-confirm dialog is up (e.g. right after
		-- entering the map standing on the next unresolved fight).
		ghost_mode = not ghost_mode
		not_available_message = ghost_mode and "Mode fantome : ON" or "Mode fantome : OFF"
		not_available_timer = NOT_AVAILABLE_DURATION
		return
	end
	if confirm_dialog_active then
		if key == "escape" then
			hide_confirm_dialog()
		end
		return
	end
	if key == "escape" then
		local title_screen = require("screens.title_screen")
		screen_manager.switch_to(title_screen)
	elseif key == "t" then
		-- Dev/debug shortcut (Camil, 2026-08-09) — un-gated here, unlike
		-- Godot's own OS.is_debug_build() guard, since this port has no
		-- release/debug build distinction to hide it behind.
		screen_manager.switch_to(campaign_cheat_menu)
	end
end

return campaign_map
