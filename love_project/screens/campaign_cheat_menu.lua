local screen_manager = require("screen_manager")
local input = require("input")
local campaign_context = require("campaign.campaign_context")
local campaign_save = require("campaign.campaign_save")
local rival_encounter_data = require("simulation.rival_encounter_data")
local match_arena = require("screens.match_arena")

local lourd = require("data.characters.lourd")
local controleur = require("data.characters.controleur")
local mitrailleur = require("data.characters.mitrailleur")
local vif = require("data.characters.vif")
local zoneur = require("data.characters.zoneur")
local perturbateur = require("data.characters.perturbateur")
local missiles = require("data.characters.missiles")
local mini = require("data.characters.mini")

local none_twist = nil
local gauge_floor = require("data.twists.gauge_floor")
local shrinking_arena = require("data.twists.shrinking_arena")
local hazard_zones = require("data.twists.hazard_zones")
local invisible_opponent = require("data.twists.invisible_opponent")
local energy_orb_boss = require("data.twists.energy_orb_boss")
local drifting_neutral_zone = require("data.twists.drifting_neutral_zone")
local visual_decoy = require("data.twists.visual_decoy")
local multi_ball = require("data.twists.multi_ball")

-- Ported (simplified) from godot_project/nodes/campaign_cheat_menu_node.gd
-- — a dev/debug tool, not part of the normal campaign flow: jump straight
-- into a match/mini-jeu against any of the 8 characters, playing as any of
-- them, with any twist active (or none), full hp both sides. No currency/
-- unlock/progress side effects (see each screen's own resolve()/escape
-- handler — all of them check campaign_context.debug_encounter and bounce
-- back HERE instead of CampaignMap, exactly like match_arena.lua's own
-- resolve_campaign_result() already did before this mode picker existed).
-- Reached from CampaignMap via "T" (un-gated here — this port has no
-- release/debug build distinction to hide it behind, unlike Godot's own
-- OS.is_debug_build() guard).
--
-- 2026-09-16 (Camil: "il me faudrait un menu cheat qui me permet de tester
-- tous les modes, avec n'importe quel perso") — was combat-only, with the
-- PLAYER's character always following whichever real campaign happened to
-- be loaded already (only Vif's campaign was authored back then, so this
-- was a reasonable simplification). Now that every character has real
-- content across all challenge_types, both the player's own character and
-- the mini-jeu type (challenge_type) are pickable here too, decoupled from
-- whatever the player was doing on the real map before opening this menu.

local campaign_cheat_menu = {}

local CHARACTERS = { lourd, controleur, mitrailleur, vif, zoneur, perturbateur, missiles, mini }

-- One campaign_data module per character — needed so launch() can seed
-- campaign_context.campaign with the CHOSEN player character's own
-- campaign (for campaign_save currency/id lookups, and so mini-jeu
-- screens' `campaign_context.campaign.character` resolves to the right
-- person), independent of whatever campaign was active before this menu
-- was opened.
local CAMPAIGNS_BY_CHARACTER_ID = {
	lourd = require("data.campaigns.lourd_campaign"),
	controleur = require("data.campaigns.controleur_campaign"),
	mitrailleur = require("data.campaigns.mitrailleur_campaign"),
	vif = require("data.campaigns.vif_campaign"),
	zoneur = require("data.campaigns.zoneur_campaign"),
	perturbateur = require("data.campaigns.perturbateur_campaign"),
	missiles = require("data.campaigns.missiles_campaign"),
	mini = require("data.campaigns.mini_campaign"),
}

-- index 0 (Lua index 1) is always "Aucun twist". "Double balle" is listed
-- for parity but not actually wired up yet (see data/twists/multi_ball.lua's
-- own header) — selecting it currently plays like no twist at all. Twists
-- only ever apply to the "combat" mode — the three mini-jeux never call
-- apply_twist() at all, so this field is greyed out (but still visible,
-- not skipped) whenever a mini-jeu mode is selected.
local TWISTS = { none_twist, gauge_floor, shrinking_arena, hazard_zones, invisible_opponent, energy_orb_boss, drifting_neutral_zone, visual_decoy, multi_ball }

local MODES = { "combat", "breakout", "space_invaders", "gradius" }
local MODE_LABELS = { combat = "Combat (1v1)", breakout = "Breakout", space_invaders = "Space Invaders", gradius = "Gradius" }

-- Fields, top to bottom — Haut/Bas moves between these, Gauche/Droite
-- changes the selected field's own value.
local FIELD_PLAYER, FIELD_MODE, FIELD_OPPONENT, FIELD_TWIST = 0, 1, 2, 3
local FIELD_COUNT = 4

local field_index, player_index, mode_index, twist_index, opponent_index
local field_move_prev, value_move_prev, confirm_prev
local with_all_unlocks, unlocks_toggle_prev

function campaign_cheat_menu.enter()
	field_index = FIELD_PLAYER
	player_index = 0
	mode_index = 0
	twist_index = 0
	opponent_index = 0
	field_move_prev, value_move_prev = false, false
	confirm_prev = true
	with_all_unlocks = false
	unlocks_toggle_prev = false
end

-- Grants every rival's unlock_reward across the whole campaign — "as if"
-- every branch had already been beaten for real — WITHOUT touching
-- resolved_case_ids/campaign_progress/organizer_defeated, so this can
-- never be mistaken for real progress.
local function grant_all_branch_unlocks(campaign_data)
	local character_id = campaign_data.character.id
	for _, branch in ipairs(campaign_data.mini_branches) do
		if branch and branch.rival and branch.rival.unlock_reward then
			campaign_save.grant_unlock(character_id, branch.rival.unlock_reward.id)
		end
	end
end

local function launch()
	local player_character = CHARACTERS[player_index + 1]
	local campaign_data = CAMPAIGNS_BY_CHARACTER_ID[player_character.id]
	if with_all_unlocks then
		grant_all_branch_unlocks(campaign_data)
	end
	local mode = MODES[mode_index + 1]
	local encounter = rival_encounter_data.new({
		opponent = CHARACTERS[opponent_index + 1],
		is_mook = false,
		twist = mode == "combat" and TWISTS[twist_index + 1] or nil,
		challenge_type = mode,
		reward_currency = 100,
	})
	campaign_context.start_debug_fight(campaign_data, encounter)
	local target_screen = match_arena
	if mode == "breakout" then
		target_screen = require("screens.breakout")
	elseif mode == "space_invaders" then
		target_screen = require("screens.space_invaders")
	elseif mode == "gradius" then
		target_screen = require("screens.gradius")
	end
	screen_manager.switch_to(target_screen)
end

function campaign_cheat_menu.update(dt)
	local move_down = input.solo_down()
	local move_up = input.solo_up()
	if move_down and not field_move_prev then
		field_index = (field_index + 1) % FIELD_COUNT
	elseif move_up and not field_move_prev then
		field_index = (field_index - 1) % FIELD_COUNT
	end
	field_move_prev = move_down or move_up

	local value_right = input.solo_right()
	local value_left = input.solo_left()
	if (value_right or value_left) and not value_move_prev then
		local step = value_right and 1 or -1
		if field_index == FIELD_PLAYER then
			player_index = (player_index + step) % #CHARACTERS
		elseif field_index == FIELD_MODE then
			mode_index = (mode_index + step) % #MODES
		elseif field_index == FIELD_OPPONENT then
			opponent_index = (opponent_index + step) % #CHARACTERS
		elseif field_index == FIELD_TWIST then
			twist_index = (twist_index + step) % #TWISTS
		end
	end
	value_move_prev = value_right or value_left

	local unlocks_toggle = love.keyboard.isScancodeDown("u")
	if unlocks_toggle and not unlocks_toggle_prev then
		with_all_unlocks = not with_all_unlocks
	end
	unlocks_toggle_prev = unlocks_toggle

	local confirm = input.solo_confirm()
	if confirm and not confirm_prev then
		launch()
	end
	confirm_prev = confirm
end

local function draw_field(y, label, value_text, is_selected, is_dimmed)
	local marker = is_selected and "> " or "  "
	if is_dimmed then
		love.graphics.setColor(0.5, 0.5, 0.55)
	elseif is_selected then
		love.graphics.setColor(1.0, 0.95, 0.6)
	else
		love.graphics.setColor(0.85, 0.85, 0.9)
	end
	love.graphics.printf(string.format("%s%s :  <  %s  >", marker, label, value_text), 0, y, 1280, "center")
end

function campaign_cheat_menu.draw()
	love.graphics.setColor(1, 1, 1)
	love.graphics.printf("Cheat menu — tester un mode / personnage / twist", 0, 60, 1280, "center")

	local mode = MODES[mode_index + 1]
	draw_field(160, "Personnage (joueur)", CHARACTERS[player_index + 1].display_name, field_index == FIELD_PLAYER, false)
	draw_field(196, "Mode", MODE_LABELS[mode], field_index == FIELD_MODE, false)
	draw_field(232, "Adversaire", CHARACTERS[opponent_index + 1].display_name, field_index == FIELD_OPPONENT, false)
	local twist = TWISTS[twist_index + 1]
	draw_field(268, "Twist", twist and twist.display_name or "Aucun twist", field_index == FIELD_TWIST, mode ~= "combat")
	if mode ~= "combat" then
		love.graphics.setColor(0.55, 0.55, 0.6)
		love.graphics.printf("(ignore hors mode Combat)", 0, 290, 1280, "center")
	end

	love.graphics.setColor(1, 1, 1)
	love.graphics.printf(
		string.format("[U] Unlocks tous rivaux (du joueur choisi) : %s", with_all_unlocks and "ON" or "off"),
		0, 420, 1280, "center"
	)

	love.graphics.setColor(0.65, 0.65, 0.7)
	love.graphics.printf(
		"Haut/Bas : champ — Gauche/Droite : valeur — U : unlocks — Espace : lancer — Echap : retour",
		0,
		660,
		1280,
		"center"
	)
end

function campaign_cheat_menu.keypressed(key)
	if key == "escape" then
		local campaign_map = require("screens.campaign_map")
		screen_manager.switch_to(campaign_map)
	end
end

return campaign_cheat_menu
