local screen_manager = require("screen_manager")
local input = require("input")
local mathx = require("simulation.mathx")
local match_arena = require("screens.match_arena")
local match_setup = require("match_setup")
local assets = require("assets")
local draw_utils = require("draw_utils")
local title_music = require("title_music")

local lourd = require("data.characters.lourd")
local controleur = require("data.characters.controleur")
local mitrailleur = require("data.characters.mitrailleur")
local vif = require("data.characters.vif")
local zoneur = require("data.characters.zoneur")
local perturbateur = require("data.characters.perturbateur")
local missiles = require("data.characters.missiles")
local mini = require("data.characters.mini")

-- Ported from godot_project/nodes/character_select_node.gd — Phase 6 of
-- the LÖVE port. Both players pick independently and locally over a
-- shared 4x2 portrait grid, own cursor color each, can land on the same
-- cell; whoever confirms first just waits on the other. No real
-- portrait/full-body art yet (that's Phase 7 polish, same as the Godot
-- version's own "falls back to a drawn placeholder" path) — every
-- character shows its accent-tinted box + initial for now.

local character_select = {}

-- Order matches character_select_node.gd's own CHARACTERS array and the
-- grid's row-major layout (row = i/GRID_COLS, col = i%GRID_COLS).
local CHARACTERS = { lourd, controleur, mitrailleur, vif, zoneur, perturbateur, missiles, mini }

-- Per-character accent color, from the GDD's character-portrait prompt
-- table ("Accent" column).
local ACCENT_COLORS = {
	lourd = { 0.85, 0.4, 0.15 },
	controleur = { 0.6, 0.63, 0.68 },
	mitrailleur = { 0.65, 0.78, 0.88 },
	vif = { 0.15, 0.55, 1.0 },
	zoneur = { 0.25, 0.9, 0.45 },
	perturbateur = { 0.6, 0.5, 0.9 },
	missiles = { 0.2, 0.85, 0.9 }, -- Traqueur
	mini = { 1.0, 0.85, 0.2 }, -- Spreader
}

local GRID_COLS, GRID_ROWS = 4, 2
local CELL_SIZE, CELL_GAP = 110.0, 22.0
local GRID_ORIGIN_X, GRID_ORIGIN_Y = 388.0, 200.0

local P1_COLOR = { 0.65, 0.9, 1.0 }
local P2_COLOR = { 1.0, 0.55, 0.7 }

local BIG_P1 = { x = 60.0, y = 165.0, w = 250.0, h = 375.0 }
local BIG_P2 = { x = 970.0, y = 165.0, w = 250.0, h = 375.0 }

-- 2026-09-27 (Camil: "il faut pouvoir jouer avec des manettes") — `button`
-- fields added for gamepad confirm; movement goes through
-- input.direction_down() (D-pad + left stick) instead of a per-control
-- scancode, so it's not listed here (see process_player()).
local P1_CONTROLS = { up = "w", down = "s", left = "a", right = "d", confirm = "space", button = "a" }
local P2_CONTROLS = { up = "up", down = "down", left = "left", right = "right", confirm = "return", button = "a" }

-- select_screen_background.gd: an engine-drawn "wacky vibrant arcade"
-- backdrop (deep purple into hot pink into orange, rotating sunburst rays,
-- a faint glowing arena silhouette, twinkling stars) — no external art,
-- same "_draw() shapes" convention as CampaignMapNode. Kept sparse in the
-- center so portraits/panels on top stay readable.
local BG_COLOR_TOP = { 0.16, 0.06, 0.28 } -- deep purple
local BG_COLOR_MID = { 0.55, 0.1, 0.45 } -- hot pink
local BG_COLOR_BOTTOM = { 0.85, 0.35, 0.08 } -- orange
local BG_GRADIENT_STRIPS = 48
local BG_SUNBURST_ORIGIN_X, BG_SUNBURST_ORIGIN_Y = 640.0, 260.0
local BG_RAY_COUNT = 16 -- half of these actually draw — density vs. "not too busy"
local BG_RAY_LENGTH = 900.0
local BG_RAY_ROTATION_SPEED = 0.08
local BG_RAY_COLOR = { 1.0, 0.9, 0.6, 0.05 }
local BG_ARENA_CENTER_X, BG_ARENA_CENTER_Y = 640.0, 720.0 * 0.62
local BG_ARENA_RADIUS = 260.0
local BG_STAR_COUNT = 40

-- A tiny deterministic LCG, seeded once, used ONLY for the stars' fixed
-- layout — deliberately NOT math.random/math.randomseed, which would
-- perturb this port's real (gameplay-facing) global RNG stream.
local function seeded_random(seed)
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local bg_stars = {}
do
	local rand = seeded_random(20260812) -- STAR_SEED — stable layout every run, matching Godot's own fixed seed
	for _ = 1, BG_STAR_COUNT do
		table.insert(bg_stars, {
			x = rand() * 1280.0,
			y = rand() * 720.0,
			phase = rand() * math.pi * 2.0,
			size = 1.5 + rand() * 2.0,
		})
	end
end

local function draw_background(time)
	local strip_height = 720.0 / BG_GRADIENT_STRIPS
	for i = 0, BG_GRADIENT_STRIPS - 1 do
		local t = i / (BG_GRADIENT_STRIPS - 1)
		local r, g, b
		if t < 0.5 then
			local lt = t / 0.5
			r, g, b = mathx.lerp(BG_COLOR_TOP[1], BG_COLOR_MID[1], lt), mathx.lerp(BG_COLOR_TOP[2], BG_COLOR_MID[2], lt), mathx.lerp(BG_COLOR_TOP[3], BG_COLOR_MID[3], lt)
		else
			local lt = (t - 0.5) / 0.5
			r, g, b = mathx.lerp(BG_COLOR_MID[1], BG_COLOR_BOTTOM[1], lt), mathx.lerp(BG_COLOR_MID[2], BG_COLOR_BOTTOM[2], lt), mathx.lerp(BG_COLOR_MID[3], BG_COLOR_BOTTOM[3], lt)
		end
		love.graphics.setColor(r, g, b)
		love.graphics.rectangle("fill", 0, strip_height * i, 1280.0, strip_height + 1.0) -- +1px overlap so seams don't show
	end

	-- Faint glowing abstract arena silhouette, far in the distance.
	love.graphics.setLineWidth(6.0)
	love.graphics.setColor(1.0, 0.85, 0.5, 0.10)
	love.graphics.arc("line", "open", BG_ARENA_CENTER_X, BG_ARENA_CENTER_Y, BG_ARENA_RADIUS, math.pi * 1.05, math.pi * 1.95, 48)
	love.graphics.setLineWidth(4.0)
	love.graphics.setColor(1.0, 0.6, 0.8, 0.08)
	love.graphics.arc("line", "open", BG_ARENA_CENTER_X, BG_ARENA_CENTER_Y, BG_ARENA_RADIUS * 0.85, math.pi * 1.1, math.pi * 1.9, 40)
	love.graphics.setLineWidth(1.0)

	-- Slowly rotating sunburst rays — every other ray only, half density
	-- keeps the center readable for the panels/portraits drawn on top.
	love.graphics.setColor(BG_RAY_COLOR[1], BG_RAY_COLOR[2], BG_RAY_COLOR[3], BG_RAY_COLOR[4])
	for i = 0, BG_RAY_COUNT - 1 do
		if i % 2 ~= 0 then
			local angle = (2.0 * math.pi / BG_RAY_COUNT) * i + time * BG_RAY_ROTATION_SPEED
			local dir_x, dir_y = math.cos(angle), math.sin(angle)
			local perp_x, perp_y = -dir_y, dir_x
			local far_x, far_y = BG_SUNBURST_ORIGIN_X + dir_x * BG_RAY_LENGTH, BG_SUNBURST_ORIGIN_Y + dir_y * BG_RAY_LENGTH
			local half_width = BG_RAY_LENGTH * 0.05
			love.graphics.polygon(
				"fill",
				BG_SUNBURST_ORIGIN_X, BG_SUNBURST_ORIGIN_Y,
				far_x + perp_x * half_width, far_y + perp_y * half_width,
				far_x - perp_x * half_width, far_y - perp_y * half_width
			)
		end
	end

	for _, star in ipairs(bg_stars) do
		local twinkle = 0.5 + 0.5 * math.sin(time * 2.0 + star.phase)
		love.graphics.setColor(1.0, 1.0, 0.95, 0.3 + 0.5 * twinkle)
		love.graphics.circle("fill", star.x, star.y, star.size)
	end
end

local p1, p2, pulse_time

local function new_player_cursor(index)
	return {
		index = index,
		confirmed = false,
		left_prev = false,
		right_prev = false,
		up_prev = false,
		down_prev = false,
		-- Seeded true — the same key that confirmed arriving at THIS screen
		-- (e.g. P1's Space from the title screen) must not instantly
		-- auto-confirm cell 0 before the player has even seen the grid.
		confirm_prev = true,
	}
end

function character_select.enter()
	p1 = new_player_cursor(0)
	p2 = new_player_cursor(1)
	pulse_time = 0.0
end

local function step_grid(index, step, axis)
	local col = index % GRID_COLS
	local row = math.floor(index / GRID_COLS)
	if axis == 0 then
		col = (col + step) % GRID_COLS
	else
		row = (row + step) % GRID_ROWS
	end
	if col < 0 then
		col = col + GRID_COLS
	end
	if row < 0 then
		row = row + GRID_ROWS
	end
	return row * GRID_COLS + col
end

local function process_player(cursor, controls, joystick)
	if cursor.confirmed then
		return
	end
	local left = love.keyboard.isScancodeDown(controls.left) or input.direction_down(joystick, "left")
	local right = love.keyboard.isScancodeDown(controls.right) or input.direction_down(joystick, "right")
	local up = love.keyboard.isScancodeDown(controls.up) or input.direction_down(joystick, "up")
	local down = love.keyboard.isScancodeDown(controls.down) or input.direction_down(joystick, "down")
	if right and not cursor.right_prev then
		cursor.index = step_grid(cursor.index, 1, 0)
	end
	if left and not cursor.left_prev then
		cursor.index = step_grid(cursor.index, -1, 0)
	end
	if down and not cursor.down_prev then
		cursor.index = step_grid(cursor.index, 1, 1)
	end
	if up and not cursor.up_prev then
		cursor.index = step_grid(cursor.index, -1, 1)
	end
	cursor.left_prev, cursor.right_prev, cursor.up_prev, cursor.down_prev = left, right, up, down

	local confirm = love.keyboard.isScancodeDown(controls.confirm) or input.button_down(joystick, controls.button)
	if confirm and not cursor.confirm_prev then
		cursor.confirmed = true
	end
	cursor.confirm_prev = confirm
end

function character_select.update(dt)
	pulse_time = pulse_time + dt
	process_player(p1, P1_CONTROLS, input.get_joystick(1))
	process_player(p2, P2_CONTROLS, input.get_joystick(2))
	if p1.confirmed and p2.confirmed then
		match_setup.p1_character = CHARACTERS[p1.index + 1]
		match_setup.p2_character = CHARACTERS[p2.index + 1]
		-- character_select_node.gd's _start_match(): the title theme plays
		-- on through this whole screen, stopping only here, leaving for a
		-- real match.
		title_music.stop()
		screen_manager.switch_to(match_arena)
	end
end

local function cell_position(index)
	local col = index % GRID_COLS
	local row = math.floor(index / GRID_COLS)
	return GRID_ORIGIN_X + col * (CELL_SIZE + CELL_GAP), GRID_ORIGIN_Y + row * (CELL_SIZE + CELL_GAP)
end

local function describe(character)
	local weapon_name = "?"
	if #character.kit > 0 then
		weapon_name = character.kit[1].display_name
	end
	return string.format("%s\nArme : %s", character.archetype, weapon_name)
end

local function draw_placeholder_initial(display_name, cx, cy, font_size, color)
	local initial = display_name:sub(1, 1):upper()
	love.graphics.setColor(color[1], color[2], color[3])
	local font = love.graphics.getFont()
	local scale = font_size / font:getHeight()
	local w = font:getWidth(initial) * scale
	love.graphics.print(initial, cx - w / 2.0, cy - font_size / 2.0, 0, scale, scale)
end

local function draw_grid_cell(index)
	local character = CHARACTERS[index + 1]
	local accent = ACCENT_COLORS[character.id] or { 0.6, 0.6, 0.6 }
	local x, y = cell_position(index)
	love.graphics.setColor(accent[1], accent[2], accent[3], 0.22)
	love.graphics.rectangle("fill", x, y, CELL_SIZE, CELL_SIZE)
	love.graphics.setColor(1, 1, 1)
	local portrait = assets.characters[character.id] and assets.characters[character.id].portrait
	if portrait then
		draw_utils.draw_fit_inside(portrait, x, y, CELL_SIZE, CELL_SIZE, 4.0)
	else
		draw_placeholder_initial(character.display_name, x + CELL_SIZE / 2.0, y + CELL_SIZE / 2.0, 40, accent)
	end
	love.graphics.setColor(accent[1], accent[2], accent[3])
	love.graphics.setLineWidth(3.0)
	love.graphics.rectangle("line", x, y, CELL_SIZE, CELL_SIZE)
	love.graphics.setColor(0.9, 0.91, 0.97)
	love.graphics.printf(character.display_name, x - 20.0, y + CELL_SIZE + 6.0, CELL_SIZE + 40.0, "center")
end

-- The bold player cursor: a thick rectangular frame with outward corner
-- ticks (HUD "target lock" look). Padding differs per player so two
-- cursors landing on the same cell nest instead of perfectly overlapping.
local function draw_corner_ticks(x, y, w, h, color)
	local tick = 12.0
	local corners = {
		{ x, y, -1.0, -1.0 },
		{ x + w, y, 1.0, -1.0 },
		{ x, y + h, -1.0, 1.0 },
		{ x + w, y + h, 1.0, 1.0 },
	}
	love.graphics.setColor(color[1], color[2], color[3])
	love.graphics.setLineWidth(5.0)
	for _, c in ipairs(corners) do
		local cx, cy, sx, sy = c[1], c[2], c[3], c[4]
		love.graphics.line(cx, cy, cx + tick * sx, cy)
		love.graphics.line(cx, cy, cx, cy + tick * sy)
	end
end

local function draw_selection_frame(index, tag, base_pad, color, confirmed)
	local pad = confirmed and base_pad or (base_pad + math.sin(pulse_time * 4.0) * 3.0)
	local cx, cy = cell_position(index)
	local x, y = cx - pad, cy - pad
	local w, h = CELL_SIZE + pad * 2.0, CELL_SIZE + pad * 2.0
	love.graphics.setColor(color[1], color[2], color[3])
	love.graphics.setLineWidth(5.0)
	love.graphics.rectangle("line", x, y, w, h)
	draw_corner_ticks(x, y, w, h, color)
	love.graphics.print(tag, x + 6.0, y + 8.0)
end

local function draw_big_panel(panel, cursor, tag_color)
	local character = CHARACTERS[cursor.index + 1]
	local accent = ACCENT_COLORS[character.id] or { 0.6, 0.6, 0.6 }
	love.graphics.setColor(accent[1], accent[2], accent[3], 0.18)
	love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h)
	love.graphics.setColor(1, 1, 1)
	local full_image = assets.characters[character.id] and assets.characters[character.id].full
	if full_image then
		draw_utils.draw_fit_inside(full_image, panel.x, panel.y, panel.w, panel.h, 4.0)
	else
		draw_placeholder_initial(character.display_name, panel.x + panel.w / 2.0, panel.y + panel.h / 2.0 - 20.0, 90, accent)
	end
	love.graphics.setColor(accent[1], accent[2], accent[3])
	love.graphics.setLineWidth(3.0)
	love.graphics.rectangle("line", panel.x, panel.y, panel.w, panel.h)

	love.graphics.setColor(1, 1, 1)
	love.graphics.printf(character.display_name, panel.x, panel.y + panel.h + 10.0, panel.w, "center")
	love.graphics.setColor(0.85, 0.86, 0.9)
	love.graphics.printf(describe(character), panel.x, panel.y + panel.h + 34.0, panel.w, "center")
	if cursor.confirmed then
		love.graphics.setColor(tag_color[1], tag_color[2], tag_color[3])
		love.graphics.printf("PRET !", panel.x, panel.y + panel.h + 78.0, panel.w, "center")
	end
end

function character_select.draw()
	draw_background(pulse_time)

	for i = 0, #CHARACTERS - 1 do
		draw_grid_cell(i)
	end
	-- Drawn AFTER every cell so a frame is never partly hidden behind a
	-- neighboring cell's own border.
	draw_selection_frame(p1.index, "J1", 6.0, P1_COLOR, p1.confirmed)
	draw_selection_frame(p2.index, "J2", 12.0, P2_COLOR, p2.confirmed)
	draw_big_panel(BIG_P1, p1, P1_COLOR)
	draw_big_panel(BIG_P2, p2, P2_COLOR)

	love.graphics.setColor(0.7, 0.7, 0.75)
	love.graphics.printf(
		"J1 : ZQSD + Espace     J2 : Fleches + Entree     Echap : retour",
		0,
		20.0,
		1280,
		"center"
	)
end

function character_select.keypressed(key)
	if key == "escape" then
		-- Lazy require to break the title_screen <-> character_select cycle
		-- (title_screen requires this module up front to switch INTO it) —
		-- by the time a keypress can happen, every screen is long since
		-- fully loaded, so this just returns the cached module instantly.
		local title_screen = require("screens.title_screen")
		screen_manager.switch_to(title_screen)
	end
end

return character_select
