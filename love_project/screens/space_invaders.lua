local input = require("input")
local Vector2 = require("simulation.vector2")
local Rect2 = require("simulation.rect2")
local mathx = require("simulation.mathx")
local ship_state = require("simulation.ship_state")
local screen_manager = require("screen_manager")
local campaign_context = require("campaign.campaign_context")
local campaign_save = require("campaign.campaign_save")
local timer = require("timer")
local assets = require("assets")
local draw_utils = require("draw_utils")
local bullet_fx = require("bullet_fx")
local charged_shot = require("charged_shot")

-- Ported (simplified) from godot_project/nodes/space_invaders_node.gd — a
-- campaign mook encounter slot can be this instead of a real fight
-- (RivalEncounterData.challenge_type == "space_invaders"). No ball at all
-- ("aucun rapport avec la balle"). A 5x8 portrait formation of aliens
-- advances leftward (faster as it thins out) and bobs vertically; win by
-- clearing it, lose on 0 hp OR the formation's leading edge reaching the
-- frontier.
--
-- 2026-09-18 (Camil, same simplification already applied to gradius.lua:
-- "on va mettre un tir simple, le meme pour tous les persos. Et une charge
-- qui lance 6 tirs d'affilee (un peu comme mitrailleur)") — dropped the
-- character-kit-based weapon_system_state entirely (it was already a
-- known-gap-riddled port: Controleur's turret kit never fired at all,
-- Lourd's bazooka felt wrong for this pace) in favor of ONE simple shot
-- for every character, plus a hold-to-charge release that fires
-- CHARGE_BURST_COUNT shots in a rapid volley — a fixed mechanic, not tied
-- to any weapon data. The character only still decides the ship's sprite
-- art and campaign identity (currency/id).
local space_invaders = {}

local ARENA_BOUNDS = Rect2.new(40.0, 60.0, 1200.0, 600.0)
local FRONTIER_X = 580.0 -- same as Breakout, for visual consistency between the two mini-jeux

local FORMATION_COLS, FORMATION_ROWS = 5, 8
local FORMATION_HALF_EXTENTS = Vector2.new(20.0, 20.0)
local FORMATION_PITCH_X, FORMATION_PITCH_Y = 68.0, 60.0
local FORMATION_START_X, FORMATION_START_Y = 910.0, 150.0

local ALIEN_HP = 4.0
-- 2026-09-19 (Camil playtest: "c'est vraiment trop facile") — bumped back
-- up a bit now that the player's own fire rate is nerfed below.
local ALIEN_FIRE_RATE = 0.2
local ALIEN_DAMAGE = 7.0
local ALIEN_COLOR = { 0.85, 0.3, 0.35 }
local ALIEN_HOMING_STRENGTH = 0.6 -- "un peu a tete chercheuse" — a gentle steer, not a guided missile

local ADVANCE_SPEED = 8.0 -- px/s leftward drift, scales up as the formation thins out
local BOB_AMPLITUDE = 10.0
local BOB_ANGULAR_SPEED = 1.2 -- rad/s

-- The player's simple shot always looks/behaves like a machine-gun bullet
-- (real texture, spark-ring impact) — see the header note on why this mode
-- doesn't read the character's own weapon.id.
-- 2026-09-19 (Camil playtest: "le tir est trop rapide, il faudrait un peu
-- le nerfer") — was 6.0.
local PLAYER_FIRE_RATE = 4.0
local PLAYER_SHOT_DAMAGE = 2.0
local PLAYER_SHOT_SPEED = 700.0

-- 2026-09-19 (Camil: "j'aime bien l'idee de garder quand meme l'identite de
-- chaque perso [...] se baser sur le tir charge") — the uniform "6 tirs
-- d'affilee" charge burst is replaced by charged_shot.lua's per-character
-- special move, shared with gradius.lua/breakout.lua. Hold-to-charge
-- timing convention unchanged: holding past CHARGE_GRACE suspends normal
-- single shots; releasing after CHARGE_GRACE + CHARGE_DURATION unleashes
-- the character's special; releasing mid-charge wastes the attempt.
local CHARGE_GRACE = 1.0
local CHARGE_DURATION = 1.0

-- Impact styles for the charged shots' own weapon ids come from
-- charged_shot.lua's own IMPACT_STYLE_BY_WEAPON — see spawn_impact() below.
local BULLET_VISUALS = {
	machine_gun = { radius = 3.0, color = { 1.0, 1.0, 0.6 }, scale = 1.4 * 1.5 }, -- 2026-10-05 "tout plus gros" pass
}
local SIDE_SPLIT_BULLET_WEAPONS = { machine_gun = true, turret = true }

-- turret_node.gd's SPRITE_FRAME_DURATION — aliens reuse that same generic
-- sprite-flipbook entity in the Godot source (ALIEN_TEXTURES = [alien_1,
-- alien_2]), animated as one shared flipbook here rather than per-alien
-- independent timers (visually equivalent, much simpler state).
local ALIEN_FRAME_DURATION = 0.4

local player, bullets, impacts, formation
local player_turrets, player_lasers
local formation_total, bob_time
local alien_frame_index, alien_frame_timer
local resolved, message
local escape_prev

local function level_still_active()
	return not resolved
end

local function spawn_formation()
	formation = {}
	for row = 0, FORMATION_ROWS - 1 do
		for col = 0, FORMATION_COLS - 1 do
			table.insert(formation, {
				position = Vector2.new(FORMATION_START_X + col * FORMATION_PITCH_X, FORMATION_START_Y + row * FORMATION_PITCH_Y),
				half_extents = FORMATION_HALF_EXTENTS,
				hp = ALIEN_HP,
				-- 2026-08-22 bug fix carried over: randomize each alien's own
				-- first cooldown, or every alien (seeded from the same
				-- fire_rate, spawned the same frame) fires in perfect
				-- lockstep — a synchronized volley instead of individually-
				-- timed fire.
				fire_cooldown = math.random() * (1.0 / ALIEN_FIRE_RATE),
				fire_cooldown_period = 1.0 / ALIEN_FIRE_RATE,
				flash_timer = 0.0,
			})
		end
	end
	formation_total = #formation
end

function space_invaders.enter()
	local character = campaign_context.campaign.character
	player = {
		ship = ship_state.new(Vector2.new(140.0, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0), 0, Vector2.new(14 * 1.5, 28 * 1.5)), -- 2026-10-05 "tout plus gros" pass
		fire_cooldown = 0.0,
		fire_held_duration = 0.0,
		character = character,
		-- Vif's charged-shot recoil kick (charged_shot.lua's "recoil" spec)
		-- — 0 for every other character, who never call apply_recoil().
		recoil_peak = 0.0,
		recoil_timer = 0.0,
		recoil_decay_time = 1.0,
	}
	bullets = {}
	impacts = {}
	player_turrets = {}
	player_lasers = {}
	spawn_formation()
	bob_time = 0.0
	alien_frame_index = 0
	alien_frame_timer = ALIEN_FRAME_DURATION
	resolved = false
	message = ""
	-- true, not false: if Escape is still physically held from whatever
	-- keypress launched this screen, the edge check below must NOT treat
	-- that as a fresh press — Camil: "il m'arrive de revenir sur l'ecran de
	-- selection en plein game sans toucher echap".
	escape_prev = true
end

local function spawn_impact(position, weapon_id, target_half_extents)
	table.insert(impacts, charged_shot.build_impact(position, weapon_id, target_half_extents))
end

local function fire_simple_shot()
	table.insert(bullets, {
		position = player.ship.position,
		velocity = Vector2.new(PLAYER_SHOT_SPEED, 0.0),
		damage = PLAYER_SHOT_DAMAGE,
		weapon_id = "machine_gun",
		is_player_shot = true,
	})
end

local function fire_charged_shot()
	charged_shot.fire(player.character.id, {
		get_position = function() return player.ship.position end,
		spawn_bullet = function(fields)
			fields.is_player_shot = true
			table.insert(bullets, fields)
		end,
		spawn_turret = function(turret)
			table.insert(player_turrets, turret)
		end,
		spawn_laser = function(laser)
			table.insert(player_lasers, laser)
		end,
		apply_recoil = function(speed_boost, decay_time)
			player.recoil_peak = speed_boost
			player.recoil_timer = decay_time
			player.recoil_decay_time = decay_time
		end,
		still_active = level_still_active,
	})
end

local function point_in_obstacle(obstacle, point)
	local left = obstacle.position.x - obstacle.half_extents.x
	local right = obstacle.position.x + obstacle.half_extents.x
	local top = obstacle.position.y - obstacle.half_extents.y
	local bottom = obstacle.position.y + obstacle.half_extents.y
	return point.x >= left and point.x <= right and point.y >= top and point.y <= bottom
end

local function resolve(won, loss_reason)
	-- Cheat menu fight (campaign_context.debug_encounter set): mirrors
	-- match_arena.lua's own resolve_campaign_result() guard exactly — "no
	-- currency/unlock/progress side effects", bounces back to the cheat
	-- menu instead of CampaignMap so a debug fight can never corrupt real
	-- campaign progress on disk.
	if campaign_context.debug_encounter then
		message = won and "Victoire (test)" or (loss_reason and ("Defaite... (" .. loss_reason .. ")") or "Defaite...")
		campaign_context.return_to_map()
		local campaign_cheat_menu = require("screens.campaign_cheat_menu")
		timer.after(won and 1.5 or 2.0, function()
			screen_manager.switch_to(campaign_cheat_menu)
		end)
		return
	end
	local character_id = campaign_context.campaign.character.id
	local encounter = campaign_context.current_encounter()
	if won then
		campaign_save.add_currency(character_id, encounter.reward_currency)
		message = string.format("Victoire (+%d)", encounter.reward_currency)
		if campaign_context.is_graph_mode then
			campaign_save.add_resolved_case_id(character_id, campaign_context.current_graph_node_id)
		else
			campaign_context.advance_step()
			campaign_save.set_campaign_progress(character_id, campaign_context.campaign_step)
		end
	else
		message = loss_reason and ("Defaite... (" .. loss_reason .. ")") or "Defaite..."
	end
	campaign_context.return_to_map()
	local campaign_map = require("screens.campaign_map")
	timer.after(won and 1.5 or 2.0, function()
		screen_manager.switch_to(campaign_map)
	end)
end

local function update_bullets(dt)
	local i = 1
	while i <= #bullets do
		local bullet = bullets[i]
		local remove = false

		if bullet.is_alien_homing then
			-- projectile_node.gd's non-full-turn homing branch: only the
			-- vertical speed steers toward the target, horizontal speed
			-- (left/right) stays constant so it can never turn around.
			local desired_vy = mathx.clampf((player.ship.position.y - bullet.position.y) * 2.0, -260.0, 260.0)
			local new_vy = mathx.lerp(bullet.velocity.y, desired_vy, mathx.clampf(ALIEN_HOMING_STRENGTH * dt, 0.0, 1.0))
			bullet.velocity = Vector2.new(bullet.velocity.x, new_vy)
		end
		if bullet.is_boomerang then
			charged_shot.update_boomerang_bullet(bullet, dt)
		end
		if bullet.spin_speed and bullet.spin_speed ~= 0.0 then
			charged_shot.update_spin_bullet(bullet, dt)
		end
		if bullet.is_sine then
			charged_shot.update_sine_bullet(bullet, dt)
		end
		if bullet.anim_textures then
			charged_shot.update_anim_bullet(bullet, dt)
		end
		if bullet.is_player_shot and bullet.homing_strength then
			charged_shot.update_homing_bullet(bullet, dt, { formation })
		end
		bullet.position = bullet.position + bullet.velocity * dt
		if bullet.position.x < ARENA_BOUNDS.position.x - 32.0 or bullet.position.x > ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x + 32.0 then
			remove = true
		end

		if bullet.is_player_shot then
			for _, alien in ipairs(formation) do
				if alien.hp > 0.0 and point_in_obstacle(alien, bullet.position) then
					alien.hp = alien.hp - bullet.damage
					alien.flash_timer = 0.08
					spawn_impact(bullet.position, bullet.weapon_id, alien.half_extents)
					if alien.hp <= 0.0 then
						-- Camil: "il faudrait aussi que les petits ennemis
						-- explosent quand on les tue" (asked for Gradius,
						-- applied here too) — the formation never actually
						-- REMOVES a dead alien (a fixed grid, just skipped
						-- everywhere via hp>0 checks), so this transition
						-- point is the only place a real death happens.
						table.insert(impacts, charged_shot.build_impact(alien.position, "bazooka"))
					end
					remove = true
					break
				end
			end
		else
			if point_in_obstacle({ position = player.ship.position, half_extents = player.ship.half_extents }, bullet.position) then
				player.ship = ship_state.damaged(player.ship, bullet.damage)
				spawn_impact(bullet.position, bullet.weapon_id, player.ship.half_extents)
				remove = true
			end
		end

		if remove then
			table.remove(bullets, i)
		else
			i = i + 1
		end
	end
end

local function update_impacts(dt)
	local i = 1
	while i <= #impacts do
		local impact = impacts[i]
		impact.age = impact.age + dt
		if impact.age >= impact.duration then
			table.remove(impacts, i)
		else
			i = i + 1
		end
	end
end

function space_invaders.update(dt)
	local escape = input.solo_escape()
	if escape and not escape_prev then
		-- Cheat-menu fights bail straight back to the cheat menu instead of
		-- CampaignMap (mirrors match_arena.lua's own debug-escape handling)
		-- — counts as neither a win nor a loss. Read debug_encounter BEFORE
		-- return_to_map() clears it.
		local was_debug_fight = campaign_context.debug_encounter ~= nil
		campaign_context.return_to_map()
		if was_debug_fight then
			local campaign_cheat_menu = require("screens.campaign_cheat_menu")
			screen_manager.switch_to(campaign_cheat_menu)
		else
			local campaign_map = require("screens.campaign_map")
			screen_manager.switch_to(campaign_map)
		end
		escape_prev = escape
		return
	end
	escape_prev = escape

	-- Drains charged_shot.lua's staggered-burst timer.after() callbacks —
	-- see gradius.lua's own doc comment on the bug this fixes (nothing was
	-- draining timer.lua's shared queue while this screen was active, so
	-- the old 6-shot burst never actually fired more than its first shot).
	-- MUST run even after resolved=true: resolve() schedules the delayed
	-- switch_to(campaign_map) via timer.after(), and the early return below
	-- used to skip this line forever once resolved, permanently stranding
	-- the player on the win/loss screen with no way back to the map
	-- (2026-09-27 bug report: "je n'ai pas le bouton continuer").
	timer.update(dt)

	if resolved then
		return
	end

	update_bullets(dt)
	update_impacts(dt)

	alien_frame_timer = alien_frame_timer - dt
	if alien_frame_timer <= 0.0 then
		alien_frame_timer = ALIEN_FRAME_DURATION
		alien_frame_index = (alien_frame_index + 1) % 2
	end

	-- Player movement/fire — same controls as everywhere else in this port.
	local move = Vector2.new(0.0, 0.0)
	if input.solo_right() then move.x = move.x + 1.0 end
	if input.solo_left() then move.x = move.x - 1.0 end
	if input.solo_down() then move.y = move.y + 1.0 end
	if input.solo_up() then move.y = move.y - 1.0 end

	local firing = input.solo_fire()
	local released_charge_attempt = false
	local charge_duration_at_release = 0.0
	if firing then
		player.fire_held_duration = player.fire_held_duration + dt
	elseif player.fire_held_duration > CHARGE_GRACE then
		released_charge_attempt = true
		charge_duration_at_release = player.fire_held_duration
		player.fire_held_duration = 0.0
	else
		player.fire_held_duration = 0.0
	end
	local is_charging = player.fire_held_duration > CHARGE_GRACE

	-- "quand ca charge le vaisseau ralentit" — same
	-- charge_fire_slow_multiplier feel every real weapon uses in a match.
	player.recoil_timer = math.max(player.recoil_timer - dt, 0.0)
	local recoil_boost = player.recoil_timer > 0.0 and player.recoil_peak * (player.recoil_timer / player.recoil_decay_time) or 0.0
	player.ship = ship_state.update(player.ship, move, dt, ARENA_BOUNDS, FRONTIER_X, charged_shot.charge_speed_multiplier(1.0 + recoil_boost, is_charging))

	player.fire_cooldown = math.max(player.fire_cooldown - dt, 0.0)
	if is_charging then
		-- normal fire suspended while actively charging (past the grace window)
	elseif firing and player.fire_cooldown <= 0.0 then
		player.fire_cooldown = 1.0 / PLAYER_FIRE_RATE
		fire_simple_shot()
	end
	if released_charge_attempt then
		if charge_duration_at_release >= CHARGE_GRACE + CHARGE_DURATION then
			fire_charged_shot()
		end
		-- else: released mid-charge — the attempt is lost, nothing fires.
	end

	charged_shot.update_turrets(player_turrets, dt, function(fields)
		fields.is_player_shot = true
		table.insert(bullets, fields)
	end)
	charged_shot.update_lasers(player_lasers, dt, function()
		return { formation }
	end)

	-- Enemy fire.
	for _, alien in ipairs(formation) do
		alien.flash_timer = math.max(alien.flash_timer - dt, 0.0)
		if alien.hp > 0.0 then
			alien.fire_cooldown = alien.fire_cooldown - dt
			if alien.fire_cooldown <= 0.0 then
				alien.fire_cooldown = alien.fire_cooldown_period
				table.insert(bullets, {
					position = alien.position,
					velocity = Vector2.new(-480.0, 0.0),
					damage = ALIEN_DAMAGE,
					weapon_id = "machine_gun",
					is_player_shot = false,
					is_alien_homing = true,
				})
			end
		end
	end

	-- Formation advance/bob + win/loss checks.
	local alive_count = 0
	for _, alien in ipairs(formation) do
		if alien.hp > 0.0 then
			alive_count = alive_count + 1
		end
	end
	if alive_count == 0 then
		resolved = true
		resolve(true)
		return
	end
	if player.ship.hp <= 0.0 then
		resolved = true
		resolve(false, "Vous avez ete detruit")
		return
	end

	-- Fewer aliens left -> faster advance, same "the room gets smaller"
	-- tension curve the genre is built on.
	local alive_ratio = alive_count / formation_total
	local speed_scale = mathx.lerp(1.0, 2.5, 1.0 - alive_ratio)
	bob_time = bob_time + dt
	local bob_offset = math.sin(bob_time * BOB_ANGULAR_SPEED) * BOB_AMPLITUDE * dt
	for _, alien in ipairs(formation) do
		if alien.hp > 0.0 then
			alien.position = Vector2.new(alien.position.x - ADVANCE_SPEED * speed_scale * dt, alien.position.y + bob_offset)
			if alien.position.x - FORMATION_HALF_EXTENTS.x <= FRONTIER_X then
				resolved = true
				resolve(false, "L'ennemi a atteint la ligne centrale")
				return
			end
		end
	end
end

function space_invaders.draw()
	love.graphics.setColor(0.08, 0.09, 0.12)
	love.graphics.rectangle("fill", ARENA_BOUNDS.position.x, ARENA_BOUNDS.position.y, ARENA_BOUNDS.size.x, ARENA_BOUNDS.size.y)

	love.graphics.setColor(0.3, 0.3, 0.35)
	love.graphics.line(FRONTIER_X, ARENA_BOUNDS.position.y, FRONTIER_X, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y)

	local player_art = assets.characters[player.character.id]
	local ship_r, ship_g, ship_b = charged_shot.charge_tint(player.fire_held_duration, CHARGE_GRACE, CHARGE_DURATION)
	if player_art and player_art.ship then
		love.graphics.setColor(ship_r, ship_g, ship_b)
		draw_utils.draw_stretched(player_art.ship, player.ship.position.x, player.ship.position.y, player.ship.half_extents.x * 2.0, player.ship.half_extents.y * 2.0)
	else
		love.graphics.setColor(0.65 * ship_r, 0.9 * ship_g, 1.0 * ship_b)
		love.graphics.rectangle(
			"fill",
			player.ship.position.x - player.ship.half_extents.x,
			player.ship.position.y - player.ship.half_extents.y,
			player.ship.half_extents.x * 2.0,
			player.ship.half_extents.y * 2.0
		)
	end

	local alien_image = assets.aliens[alien_frame_index + 1]
	for _, alien in ipairs(formation) do
		if alien.hp > 0.0 then
			local flash = alien.flash_timer > 0.0 and 1.6 or 1.0
			love.graphics.setColor(flash, flash, flash)
			draw_utils.draw_stretched(alien_image, alien.position.x, alien.position.y, alien.half_extents.x * 2.0, alien.half_extents.y * 2.0)
		end
	end

	charged_shot.draw_lasers(player_lasers, ARENA_BOUNDS)
	charged_shot.draw_turrets(player_turrets)

	for _, bullet in ipairs(bullets) do
		local visual = BULLET_VISUALS[bullet.weapon_id] or BULLET_VISUALS.machine_gun
		local scale = bullet.visual_scale or visual.scale
		local image
		if bullet.anim_textures then
			image = bullet.anim_textures[bullet.anim_frame_index]
		else
			local weapon_id = assets.bullets[bullet.weapon_id] and bullet.weapon_id or "machine_gun"
			image = assets.bullets[weapon_id]
			if SIDE_SPLIT_BULLET_WEAPONS[weapon_id] then
				image = image[bullet.is_player_shot and 0 or 1]
			end
		end
		love.graphics.setColor(1, 1, 1)
		local flip_h = bullet.velocity.x < 0.0
		draw_utils.draw_scaled(image, bullet.position.x, bullet.position.y, scale, flip_h, bullet.rotation or 0.0)
		bullet_fx.draw(bullet, image) -- decorative particles (Traqueur's missile plume)
	end

	love.graphics.setLineWidth(2.0)
	for _, impact in ipairs(impacts) do
		charged_shot.draw_impact(impact)
	end
	love.graphics.setLineWidth(1.0)

	local alive_count = 0
	for _, alien in ipairs(formation) do
		if alien.hp > 0.0 then
			alive_count = alive_count + 1
		end
	end
	love.graphics.setColor(1, 1, 1)
	love.graphics.print(string.format("%s   Envahisseurs restants : %d", player.character.display_name, alive_count), 40, 24)
	love.graphics.setColor(0.15, 0.15, 0.18)
	love.graphics.rectangle("fill", 40, 44, 240, 10)
	love.graphics.setColor(0.3, 0.9, 0.4)
	love.graphics.rectangle("fill", 40, 44, 240 * mathx.clampf(player.ship.hp / ship_state.START_HP, 0.0, 1.0), 10)

	if message ~= "" then
		love.graphics.setColor(1, 1, 1)
		love.graphics.printf(message, ARENA_BOUNDS.position.x, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0 - 10, ARENA_BOUNDS.size.x, "center")
	end

	love.graphics.setColor(0.65, 0.65, 0.7)
	love.graphics.printf("ZQSD : deplacer — Espace : tirer (maintenir = attaque speciale) — Echap : abandonner", 0, 20, 1280, "center")
end

return space_invaders
