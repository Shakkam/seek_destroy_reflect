local screen_manager = require("screen_manager")
local input = require("input")
local campaign_context = require("campaign.campaign_context")
local campaign_save = require("campaign.campaign_save")
local assets = require("assets")
local draw_utils = require("draw_utils")
local title_music = require("title_music")

local vif_campaign = require("data.campaigns.vif_campaign")
local lourd_campaign = require("data.campaigns.lourd_campaign")
local controleur_campaign = require("data.campaigns.controleur_campaign")
local mitrailleur_campaign = require("data.campaigns.mitrailleur_campaign")
local missiles_campaign = require("data.campaigns.missiles_campaign")
local mini_campaign = require("data.campaigns.mini_campaign")
local perturbateur_campaign = require("data.campaigns.perturbateur_campaign")
local zoneur_campaign = require("data.campaigns.zoneur_campaign")

-- Ported (in spirit — heavily simplified) from
-- godot_project/nodes/campaign_character_select_node.gd. A single cursor
-- over the authored campaigns, distinct from Versus's 2-cursor grid
-- (screens/character_select.lua). All 8 characters now have a fully
-- authored campaign (see data/campaigns/*_campaign.lua).

local campaign_character_select = {}

-- Order matches the roster order used throughout this port (character_select.lua's own CHARACTERS list).
local CAMPAIGNS = {
	lourd_campaign, controleur_campaign, mitrailleur_campaign, vif_campaign,
	zoneur_campaign, perturbateur_campaign, missiles_campaign, mini_campaign,
}

local index, move_up_prev, move_down_prev, confirm_prev

function campaign_character_select.enter()
	index = 0
	move_up_prev, move_down_prev = false, false
	-- Seeded true — same anti-instant-confirm guard used throughout this
	-- project's menus.
	confirm_prev = true
end

function campaign_character_select.update(dt)
	local up = input.solo_up()
	local down = input.solo_down()
	if down and not move_down_prev then
		index = (index + 1) % #CAMPAIGNS
	elseif up and not move_up_prev then
		index = (index - 1) % #CAMPAIGNS
	end
	move_up_prev, move_down_prev = up, down

	local confirm = input.solo_confirm()
	if confirm and not confirm_prev then
		local campaign = CAMPAIGNS[index + 1]
		local step = campaign_save.get_campaign_progress(campaign.character.id)
		campaign_context.enter_campaign(campaign, step)
		-- The title theme plays on through this whole screen, stopping only
		-- here, leaving for the actual campaign map.
		title_music.stop()
		local campaign_map = require("screens.campaign_map")
		screen_manager.switch_to(campaign_map)
	end
	confirm_prev = confirm
end

-- Phase 7: small portrait thumbnail per row (falls back to nothing extra —
-- the text list already carries the info if art is somehow missing), plus
-- a big full-body preview of the currently highlighted campaign's
-- character, mirroring character_select.lua's own big-panel treatment.
local ROW_THUMB_SIZE = 40.0
local ROW_LIST_X, ROW_LIST_W = 470.0, 760.0
local BIG_PREVIEW = { x = 70.0, y = 150.0, w = 300.0, h = 450.0 }

function campaign_character_select.draw()
	love.graphics.setColor(1, 1, 1)
	love.graphics.printf("Choisissez votre campagne", 0, 100, 1280, "center")

	local selected = CAMPAIGNS[index + 1]
	local selected_art = assets.characters[selected.character.id]
	love.graphics.setColor(1, 1, 1, 0.08)
	love.graphics.rectangle("fill", BIG_PREVIEW.x, BIG_PREVIEW.y, BIG_PREVIEW.w, BIG_PREVIEW.h)
	if selected_art then
		love.graphics.setColor(1, 1, 1)
		draw_utils.draw_fit_inside(selected_art.full, BIG_PREVIEW.x, BIG_PREVIEW.y, BIG_PREVIEW.w, BIG_PREVIEW.h, 6.0)
	end
	love.graphics.setColor(0.8, 0.8, 0.85)
	love.graphics.setLineWidth(2.0)
	love.graphics.rectangle("line", BIG_PREVIEW.x, BIG_PREVIEW.y, BIG_PREVIEW.w, BIG_PREVIEW.h)

	for i, campaign in ipairs(CAMPAIGNS) do
		local idx = i - 1
		local marker = (idx == index) and "> " or "  "
		local progress = campaign_save.get_campaign_progress(campaign.character.id)
		local suffix = progress > 0 and string.format(" (etape %d)", progress + 1) or " (nouvelle)"
		local row_y = 200 + idx * 60
		local portrait = assets.characters[campaign.character.id] and assets.characters[campaign.character.id].portrait
		if portrait then
			love.graphics.setColor(1, 1, 1)
			draw_utils.draw_fit_inside(portrait, ROW_LIST_X, row_y, ROW_THUMB_SIZE, ROW_THUMB_SIZE, 2.0)
		end
		if idx == index then
			love.graphics.setColor(1.0, 0.95, 0.6)
		else
			love.graphics.setColor(0.75, 0.75, 0.8)
		end
		love.graphics.printf(
			marker .. campaign.character.display_name .. " — " .. campaign.character.archetype .. suffix,
			ROW_LIST_X + ROW_THUMB_SIZE + 12.0,
			row_y + ROW_THUMB_SIZE / 2.0 - 9.0,
			ROW_LIST_W - ROW_THUMB_SIZE - 12.0,
			"left"
		)
	end

	love.graphics.setColor(0.65, 0.65, 0.7)
	love.graphics.printf("Haut/Bas : naviguer — Espace/Entree : valider — Echap : retour", 0, 660, 1280, "center")
end

function campaign_character_select.keypressed(key)
	if key == "escape" then
		local title_screen = require("screens.title_screen")
		screen_manager.switch_to(title_screen)
	end
end

return campaign_character_select
