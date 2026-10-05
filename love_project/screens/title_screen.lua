local screen_manager = require("screen_manager")
local input = require("input")
local character_select = require("screens.character_select")
local campaign_character_select = require("screens.campaign_character_select")
local campaign_map = require("screens.campaign_map")
local campaign_context = require("campaign.campaign_context")
local campaign_save = require("campaign.campaign_save")
local title_music = require("title_music")
local fonts = require("fonts")

local vif_campaign = require("data.campaigns.vif_campaign")
local lourd_campaign = require("data.campaigns.lourd_campaign")
local controleur_campaign = require("data.campaigns.controleur_campaign")
local mitrailleur_campaign = require("data.campaigns.mitrailleur_campaign")
local missiles_campaign = require("data.campaigns.missiles_campaign")
local mini_campaign = require("data.campaigns.mini_campaign")
local perturbateur_campaign = require("data.campaigns.perturbateur_campaign")
local zoneur_campaign = require("data.campaigns.zoneur_campaign")

-- Ported from godot_project/nodes/title_screen_node.gd — Phase 6 built the
-- functional menu only; Phase 7 (2026-09-13) adds the real TitleScreen.tscn
-- palette/layout and the title-word "slam-in" entrance (Camil, re: 1.wav:
-- "les mots arrivent petit a petit en meme temps [que la voix]... facon
-- Street Fighter 2"), timed against the theme's own playback via
-- title_music.on_loop(). The reset-confirm popup stays simplified to an
-- inline "press again to confirm" window rather than a separate Oui/Non
-- menu state — same safety property (an accidental double-press can't wipe
-- a save), less machinery.
--
-- All 8 characters now have an authored campaign; "Continuer" looks the
-- right one up by the saved character_id.
local CAMPAIGNS_BY_CHARACTER_ID = {
	vif = vif_campaign,
	lourd = lourd_campaign,
	controleur = controleur_campaign,
	mitrailleur = mitrailleur_campaign,
	missiles = missiles_campaign,
	mini = mini_campaign,
	perturbateur = perturbateur_campaign,
	zoneur = zoneur_campaign,
}

local title_screen = {}

local MENU_ENTRIES = { "Nouvelle partie", "Continuer la partie", "Mode Versus" }
local DENIED_MESSAGE_DURATION = 1.6
local RESET_CONFIRM_WINDOW = 3.0

-- TitleScreen.tscn's own literal palette/layout — kept local to this
-- screen (not worth sharing constants for a one-off title card).
local BACKGROUND_COLOR = { 0.07, 0.09, 0.15 }
local CENTER_LINE_COLOR = { 0.27, 0.85, 1.0, 0.25 }
local TITLE_TOP_COLOR = { 0.65, 0.9, 1.0 }
local TITLE_BOTTOM_COLOR = { 1.0, 0.55, 0.7 }
local TAGLINE_COLOR = { 0.6, 0.62, 0.7, 0.9 }
local MENU_COLOR = { 1.0, 0.84, 0.29 }
local POPUP_COLOR = { 1.0, 0.55, 0.7 }
local HINT_COLOR = { 0.6, 0.62, 0.7, 0.9 }
local VERSION_COLOR = { 0.6, 0.62, 0.7, 0.6 }

local TITLE_FONT_SIZE = 40
local TAGLINE_FONT_SIZE = 16
local MENU_FONT_SIZE = 26
local POPUP_FONT_SIZE = 22
local HINT_FONT_SIZE = 16
local VERSION_FONT_SIZE = 12

-- title_word_seek/and_destroy sit on one row, title_bottom on the next —
-- rest_y is each row's VERTICAL CENTER (Godot's offset_top + half the
-- 60px-tall label box), since the drop/squash animation below scales and
-- positions around a centered origin, not a top-left corner.
local TITLE_WORD_GAP = 16.0
local TITLE_TOP_REST_Y = 250.0
local TITLE_BOTTOM_REST_Y = 310.0

-- 2026-08-16 (Camil, with 1.wav — "ce serait bien que les mots arrivent
-- petit a petit en meme temps [que la voix]") — timestamps given by ear,
-- listening to the real track: "Seek" => 2.5s, "and destroy" => 3.5s, "and
-- return the ball" => 4.5s.
local WORD_SEEK_DROP_TIME = 2.5
local WORD_AND_DESTROY_DROP_TIME = 3.5
local WORD_BOTTOM_DROP_TIME = 4.5
local TITLE_START_Y = -160.0
local TITLE_START_SCALE = 2.0
local TITLE_DROP_DURATION = 0.35 -- fast, a slam not a float
local TITLE_SQUASH_DURATION = 0.4
local SQUASH_SCALE_X, SQUASH_SCALE_Y = 1.18, 0.7 -- flattened wide on impact

-- Presentational-only easing (this project's simulation/mathx.lua stays
-- limited to what the pure gameplay layer/Busted specs actually need).
local function ease_out_quad(t)
	return 1.0 - (1.0 - t) * (1.0 - t)
end

-- Standard "back" ease-out: overshoots past 1.0 before settling — the
-- punchy landing bounce (title_screen_node.gd's TRANS_BACK/EASE_OUT).
local function ease_out_back(t)
	local s = 1.70158
	t = t - 1.0
	return t * t * ((s + 1.0) * t + s) + 1.0
end

-- Standard elastic ease-out — the springy recover-from-squash (mirrors
-- TRANS_ELASTIC/EASE_OUT).
local function ease_out_elastic(t)
	if t <= 0.0 then
		return 0.0
	end
	if t >= 1.0 then
		return 1.0
	end
	local p = 0.3
	return 2.0 ^ (-10.0 * t) * math.sin((t - p / 4.0) * (2.0 * math.pi) / p) + 1.0
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- The three slam-in words (title_word_seek/and_destroy/bottom). Built once
-- at module load — text/color/drop_time/layout never change, only each
-- word's own y/scale animates (mirrors _position_title_words() running
-- once in _ready()).
local words
local loop_timer

local function reset_word(word)
	word.state = "pending"
	word.timer = 0.0
	word.y = TITLE_START_Y
	word.scale_x = TITLE_START_SCALE
	word.scale_y = TITLE_START_SCALE
end

-- Re-arms all three slam-ins against the music's own playback clock —
-- registered on title_music.on_loop() below, which fires on both the
-- theme's initial start() AND every subsequent loop-back, so the entrance
-- replays each time the track loops while the player is still here.
local function reset_all_words()
	loop_timer = 0.0
	for _, word in ipairs(words) do
		reset_word(word)
	end
end

local function build_words()
	-- A real Font rasterized AT size 40 (not the default font stretched up
	-- via a scale factor — see fonts.lua's own doc comment for why that
	-- read as blurry) — widths measured off THIS font need no more
	-- font_scale correction, they're already in on-screen pixels.
	local font = fonts.get(TITLE_FONT_SIZE)
	local seek_w = font:getWidth("SEEK")
	local and_destroy_w = font:getWidth("AND DESTROY")
	local bottom_text = "AND RETURN THE BALL"
	local bottom_w = font:getWidth(bottom_text)
	local total_width = seek_w + TITLE_WORD_GAP + and_destroy_w
	local start_x = (1280.0 - total_width) / 2.0

	words = {
		{
			text = "SEEK", color = TITLE_TOP_COLOR, drop_time = WORD_SEEK_DROP_TIME,
			rest_x = start_x + seek_w / 2.0, rest_y = TITLE_TOP_REST_Y, native_width = seek_w,
		},
		{
			text = "AND DESTROY", color = TITLE_TOP_COLOR, drop_time = WORD_AND_DESTROY_DROP_TIME,
			rest_x = start_x + seek_w + TITLE_WORD_GAP + and_destroy_w / 2.0, rest_y = TITLE_TOP_REST_Y, native_width = and_destroy_w,
		},
		{
			text = bottom_text, color = TITLE_BOTTOM_COLOR, drop_time = WORD_BOTTOM_DROP_TIME,
			rest_x = 640.0, rest_y = TITLE_BOTTOM_REST_Y, native_width = bottom_w,
		},
	}
	reset_all_words()
end

build_words()
title_music.on_loop(reset_all_words)

local function update_words(dt)
	loop_timer = loop_timer + dt
	for _, word in ipairs(words) do
		if word.state == "pending" then
			if loop_timer >= word.drop_time then
				word.state = "dropping"
				word.timer = 0.0
			end
		elseif word.state == "dropping" then
			word.timer = word.timer + dt
			local t = math.min(word.timer / TITLE_DROP_DURATION, 1.0)
			word.y = lerp(TITLE_START_Y, word.rest_y, ease_out_back(t))
			local s = lerp(TITLE_START_SCALE, 1.0, ease_out_quad(t))
			word.scale_x, word.scale_y = s, s
			if word.timer >= TITLE_DROP_DURATION then
				word.y = word.rest_y
				word.state = "squash"
				word.timer = 0.0
				word.scale_x, word.scale_y = SQUASH_SCALE_X, SQUASH_SCALE_Y
			end
		elseif word.state == "squash" then
			word.timer = word.timer + dt
			local t = math.min(word.timer / TITLE_SQUASH_DURATION, 1.0)
			local e = ease_out_elastic(t)
			word.scale_x = lerp(SQUASH_SCALE_X, 1.0, e)
			word.scale_y = lerp(SQUASH_SCALE_Y, 1.0, e)
			if word.timer >= TITLE_SQUASH_DURATION then
				word.scale_x, word.scale_y = 1.0, 1.0
				word.state = "rest"
			end
		end
	end
end

local menu_index, move_up_prev, move_down_prev, confirm_prev
local denied_message, denied_timer
local reset_confirm_armed, reset_confirm_timer

function title_screen.enter()
	menu_index = 0
	move_up_prev, move_down_prev = false, false
	-- Seeded true — same anti-instant-confirm guard used throughout this
	-- project's menus (e.g. character_select.lua's cursors): the key that
	-- confirmed a PREVIOUS screen must not instantly fire again here.
	confirm_prev = true
	denied_message = nil
	denied_timer = 0.0
	reset_confirm_armed = false
	reset_confirm_timer = 0.0
	-- title_music.gd's start(): always (re)starts the theme from 0, no
	-- isPlaying() guard — its own `looped` signal fires immediately on that
	-- fresh start, replaying the word-drop entrance via the on_loop
	-- callback registered above.
	title_music.start()
end

local function deny(message)
	denied_message = message
	denied_timer = DENIED_MESSAGE_DURATION
end

local function start_new_game()
	campaign_save.reset_all()
	-- campaign_character_select.lua itself sets campaign_context.campaign
	-- once the player actually picks one — nothing to enter here yet.
	screen_manager.switch_to(campaign_character_select)
end

local function confirm_selection()
	if menu_index == 0 then -- Nouvelle partie
		if campaign_save.has_any_progress() and not reset_confirm_armed then
			reset_confirm_armed = true
			reset_confirm_timer = RESET_CONFIRM_WINDOW
			deny("Une progression existe : appuyez a nouveau pour confirmer (elle sera perdue).")
			return
		end
		start_new_game()
	elseif menu_index == 1 then -- Continuer la partie
		local character_id = campaign_save.character_with_progress()
		if character_id == "" then
			-- 2026-08-16 UX audit precedent (Sally): a mistimed confirm on a
			-- dead entry gets real feedback, not a silent no-op.
			deny("Aucune sauvegarde a continuer.")
			return
		end
		local campaign = CAMPAIGNS_BY_CHARACTER_ID[character_id]
		if not campaign then
			deny("Sauvegarde pour un personnage dont la campagne n'est pas encore portee.")
			return
		end
		local step = campaign_save.get_campaign_progress(character_id)
		campaign_context.enter_campaign(campaign, step)
		-- "Continuer" skips character select entirely — the save already
		-- knows which character. That screen's own stop() call never runs
		-- in this path, so stop the theme here instead (title_screen_node.
		-- gd's own comment on this exact branch).
		title_music.stop()
		screen_manager.switch_to(campaign_map)
	else -- Mode Versus
		screen_manager.switch_to(character_select)
	end
end

function title_screen.update(dt)
	update_words(dt)

	if denied_timer > 0.0 then
		denied_timer = denied_timer - dt
		if denied_timer <= 0.0 then
			denied_message = nil
		end
	end
	if reset_confirm_armed then
		reset_confirm_timer = reset_confirm_timer - dt
		if reset_confirm_timer <= 0.0 then
			reset_confirm_armed = false
		end
	end

	-- Both WASD and arrows navigate — this is a solo screen, no reason to
	-- force it to be "J2's" input scheme the way the arena's own P2
	-- controls are.
	local move_up = input.solo_up()
	local move_down = input.solo_down()
	if move_down and not move_down_prev then
		menu_index = (menu_index + 1) % #MENU_ENTRIES
		reset_confirm_armed = false
	elseif move_up and not move_up_prev then
		menu_index = (menu_index - 1) % #MENU_ENTRIES
		reset_confirm_armed = false
	end
	move_up_prev, move_down_prev = move_up, move_down

	local confirm = input.solo_confirm()
	if confirm and not confirm_prev then
		confirm_selection()
	end
	confirm_prev = confirm
end

-- Draws with a real Font rasterized at `size` (fonts.lua) — crisp at any
-- size, unlike scaling the default font up.
local function print_scaled(text, x, y, size, align, box_w)
	love.graphics.setFont(fonts.get(size))
	if align then
		love.graphics.printf(text, x, y, box_w, align)
	else
		love.graphics.print(text, x, y)
	end
end

function title_screen.draw()
	love.graphics.setColor(BACKGROUND_COLOR[1], BACKGROUND_COLOR[2], BACKGROUND_COLOR[3])
	love.graphics.rectangle("fill", 0, 0, 1280, 720)

	love.graphics.setColor(CENTER_LINE_COLOR[1], CENTER_LINE_COLOR[2], CENTER_LINE_COLOR[3], CENTER_LINE_COLOR[4])
	love.graphics.setLineWidth(2.0)
	love.graphics.line(640, 0, 640, 720)
	love.graphics.setLineWidth(1.0)

	local title_font = fonts.get(TITLE_FONT_SIZE)
	love.graphics.setFont(title_font)
	local native_height = title_font:getHeight()
	for _, word in ipairs(words) do
		love.graphics.setColor(word.color[1], word.color[2], word.color[3])
		love.graphics.print(
			word.text, word.rest_x, word.y, 0,
			word.scale_x, word.scale_y,
			word.native_width / 2.0, native_height / 2.0
		)
	end

	love.graphics.setColor(TAGLINE_COLOR[1], TAGLINE_COLOR[2], TAGLINE_COLOR[3], TAGLINE_COLOR[4])
	print_scaled("Pong  x  Shoot'em Up  x  Fighting Game", 0, 355, TAGLINE_FONT_SIZE, "center", 1280)

	local has_save = campaign_save.has_any_progress()
	love.graphics.setColor(MENU_COLOR[1], MENU_COLOR[2], MENU_COLOR[3])
	for i, entry in ipairs(MENU_ENTRIES) do
		local index = i - 1
		local marker = (index == menu_index) and "> " or "  "
		local suffix = ""
		if index == 1 and not has_save then
			suffix = " [aucune sauvegarde]"
		end
		print_scaled(marker .. entry .. suffix, 0, 440 + index * 40, MENU_FONT_SIZE, "center", 1280)
	end

	if denied_message then
		love.graphics.setColor(POPUP_COLOR[1], POPUP_COLOR[2], POPUP_COLOR[3])
		print_scaled(denied_message, 240, 345, POPUP_FONT_SIZE, "center", 800)
	end

	love.graphics.setColor(HINT_COLOR[1], HINT_COLOR[2], HINT_COLOR[3], HINT_COLOR[4])
	print_scaled("Haut/Bas : naviguer — Espace/Entree : valider", 0, 640, HINT_FONT_SIZE, "center", 1280)

	love.graphics.setColor(VERSION_COLOR[1], VERSION_COLOR[2], VERSION_COLOR[3], VERSION_COLOR[4])
	print_scaled("prototype — pixel art placeholder", 20, 692, VERSION_FONT_SIZE, nil, nil)

	-- Every other screen implicitly relies on love.graphics.getFont() being
	-- the original default (none of them call setFont themselves) — restore
	-- it so leaving this screen doesn't leak a custom Font into the next one.
	love.graphics.setFont(fonts.default)
end

return title_screen
