local input = require("input")
local Vector2 = require("simulation.vector2")
local Rect2 = require("simulation.rect2")
local mathx = require("simulation.mathx")
local ball_state = require("simulation.ball_state")
local ship_state = require("simulation.ship_state")
local weapon_system_state = require("simulation.weapon_system_state")
local screen_manager = require("screen_manager")
local campaign_context = require("campaign.campaign_context")
local campaign_save = require("campaign.campaign_save")
local timer = require("timer")
local assets = require("assets")
local draw_utils = require("draw_utils")
local charged_shot = require("charged_shot")

-- Ported (simplified) from godot_project/nodes/breakout_node.gd — a
-- campaign mook encounter slot can be this instead of a real fight
-- (RivalEncounterData.challenge_type == "breakout"). Reuses the same
-- simulation/ pieces the real match does (ship movement, ball) rather than
-- a separate arcade-clone simulation.
--
-- 2026-09-16 fidelity pass (Camil playtest: "beaucoup trop facile et ne
-- ressemble pas a celui qu'on avait dans Godot") — two real gaps found and
-- fixed against ball_node.gd:
--   - Ball-vs-brick/enemy collision now expands the target rect by
--     ball_state.RADIUS (ball_overlaps_obstacle()), matching ball_node.gd's
--     _turret_rect() — the ball's own size was never accounted for, making
--     bricks/enemies a noticeably smaller target than in Godot (fewer
--     bounces, slower speed ramp, faster/easier clears).
--   - Enemy shots vs. the player now use a small hit-margin
--     (ENEMY_SHOT_HIT_MARGIN), matching projectile_node.gd's own
--     hit_half_size Minkowski-sum fallback for a shot with no dedicated art.
--
-- 2026-09-18 (Camil, same simplification already applied to gradius.lua
-- and space_invaders.lua: "on va mettre un tir simple, le meme pour tous
-- les persos. Et une charge qui lance 6 tirs d'affilee") — the player's
-- WEAPON (character-kit-based weapon_system_state firing) is now one
-- simple uniform shot for every character, plus a hold-to-charge release
-- that fires CHARGE_BURST_COUNT shots in a rapid volley. The ball-return
-- gauge/lift-charge mechanic is UNCHANGED (that's Breakout's own paddle
-- economy, not "which weapon you have") — weapon_system_state is only
-- still required for its RETURN_GAUGE_FILL*/gauge_max constants, not for
-- a real per-character kit anymore (player.gauge is a plain float now).
local breakout = {}

local ARENA_BOUNDS = Rect2.new(40.0, 60.0, 1200.0, 600.0)
-- 2026-08-18 (Camil, reference screenshot): moved right of the real
-- match's own center frontier so the player's zone reads closer to a
-- normal half instead of a narrow strip, leaving more room for the brick
-- wall.
local FRONTIER_X = 580.0
local MISS_DAMAGE = 18.0

local BRICK_HALF_EXTENTS = Vector2.new(28.0, 48.0)
local BRICK_COLS, BRICK_ROWS = 8, 5
-- 2026-09-20 (Camil, after playtesting: "c'est vraiment trop facile [...]
-- il faudrait que les briques soient un peu espacees entre eux, et qu'ils
-- aient plusieurs PV") — was 0 gap (pitch == brick size exactly) and
-- BRICK_HP=1.0 (any single hit destroyed a brick outright).
local BRICK_GAP = 6.0
local BRICK_PITCH_X, BRICK_PITCH_Y = BRICK_HALF_EXTENTS.x * 2.0 + BRICK_GAP, BRICK_HALF_EXTENTS.y * 2.0 + BRICK_GAP
local BRICK_FIELD_START_X, BRICK_FIELD_START_Y = 690.0, 130.0
-- 2026-10-05 (Camil, after the x1.5 size pass: "le mode breakout est
-- vraiment trop facile [...] 2 coups de balle pour detruire une brique
-- [...] multiplier les PV au moins par 5 pour eviter de tout detruire
-- facilement avec les tirs") — the ball's own flat 1.0 dmg/bounce (see
-- update_ball_and_twist()'s obstacle-bounce block) now kills a brick in
-- exactly 2 hits (the classic Breakout way to clear them); weapon fire is
-- deliberately made a much weaker tool against bricks/enemies via
-- WEAPON_DAMAGE_VS_OBSTACLE_SCALE below, rather than raising this HP value
-- itself (which would also make the ball less effective).
local BRICK_HP = 2.0 * 2.0 -- 2026-10-05 (Camil: "augmente encore les PV des briques, x2") — now 4 ball hits (was 2), ~10 machine_gun hits via WEAPON_DAMAGE_VS_OBSTACLE_SCALE (was ~5)
-- Divides weapon damage (not the ball's) against bricks/enemies by 5 —
-- equivalent to a x5 HP multiplier from a gun's point of view alone.
local WEAPON_DAMAGE_VS_OBSTACLE_SCALE = 1.0 / 5.0
local BRICK_COLUMN_COLORS = {
	{ 0.8, 0.3, 0.9 }, { 0.3, 0.55, 0.95 }, { 0.35, 0.85, 0.4 },
	{ 0.95, 0.85, 0.25 }, { 0.95, 0.6, 0.2 }, { 0.9, 0.3, 0.3 },
}

-- Flat now (was scaled by the player's own weapon fire_rate) — every
-- character fires at the same PLAYER_FIRE_RATE now, so there's no more
-- "slow weapon vs. fast weapon" gap to compensate for.
local ENEMY_SPAWN_INTERVAL = 6.0
local ENEMY_MAX_ALIVE = 5
local ENEMY_HP = 2.0 -- 2026-10-05: same "2 ball hits" rule as bricks now — see BRICK_HP's own doc comment
local ENEMY_FIRE_RATE = 0.6
local ENEMY_DAMAGE = 4.0
local ENEMY_COLOR = { 0.85, 0.3, 0.9 }

local COUNTDOWN_TICK = 1.0

-- The player's simple shot always looks/behaves like a machine-gun bullet
-- (real texture, spark-ring impact) — see the header note on why this mode
-- doesn't read the character's own weapon.id.
local PLAYER_FIRE_RATE = 6.0
local PLAYER_SHOT_DAMAGE = 2.0
local PLAYER_SHOT_SPEED = 700.0

-- 2026-09-19 (Camil: "j'aime bien l'idee de garder quand meme l'identite de
-- chaque perso [...] se baser sur le tir charge") — the uniform "6 tirs
-- d'affilee" charge burst is replaced by charged_shot.lua's per-character
-- special move, shared with gradius.lua/space_invaders.lua. Hold-to-charge
-- timing convention unchanged: holding past CHARGE_GRACE suspends normal
-- single shots; releasing after CHARGE_GRACE + CHARGE_DURATION unleashes
-- the character's special; releasing mid-charge wastes the attempt.
local CHARGE_GRACE = 1.0
local CHARGE_DURATION = 1.0

local GAUGE_MAX = 100.0

-- 2026-09-16 (Camil playtest, "ne ressemble pas a celui qu'on avait dans
-- Godot") — in a real match, ship_node.gd's own _physics_process() reads
-- the lift key and charges _lift_charge_timer completely independently of
-- MatchArenaNode/BreakoutNode, so BreakoutNode's real ShipNode got a
-- working lift-charge-on-return "for free". This port's ship_state is a
-- passive data struct with no input-reading of its own — match_arena.lua
-- hand-reads the lift key itself, but breakout.lua never did, leaving
-- `player.lift_charge_timer` initialized and then never touched. Every
-- return landed at the flat (minimum) RETURN_GAUGE_FILL, and the ball never
-- got the spin/aim payoff a charged lift return gives in a real match.
local LIFT_CHARGE_CAP = 2.0 -- seconds to reach 100% — matches match_arena.lua's SHIP_FEEL.LIFT_CHARGE_CAP
local function lift_charge_fraction(held_time)
	if held_time < 0.3 then
		return 0.0
	elseif held_time < 0.6 then
		return 0.33
	elseif held_time < LIFT_CHARGE_CAP then
		return 0.66
	end
	return 1.0
end

-- Impact styles for the charged shots' own weapon ids come from
-- charged_shot.lua's own IMPACT_STYLE_BY_WEAPON — see spawn_impact() below.
local BULLET_VISUALS = {
	machine_gun = { radius = 3.0, color = { 1.0, 1.0, 0.6 }, scale = 1.4 * 1.5 }, -- 2026-10-05 "tout plus gros" pass
}
-- Enemy shots (and the player's own simple shot) are always plain
-- machine_gun-style, split by owner_side — the side-tinted art always
-- resolves correctly.
local SIDE_SPLIT_BULLET_WEAPONS = { machine_gun = true, turret = true }

local player, ball, bullets, impacts, bricks, enemies
local player_turrets, player_lasers
local enemy_spawn_timer
local resolved, countdown_value, countdown_timer, message
local escape_prev, confirm_prev

local function spawn_brick_grid()
	bricks = {}
	for row = 0, BRICK_ROWS - 1 do
		for col = 0, BRICK_COLS - 1 do
			table.insert(bricks, {
				position = Vector2.new(BRICK_FIELD_START_X + col * BRICK_PITCH_X, BRICK_FIELD_START_Y + row * BRICK_PITCH_Y),
				half_extents = BRICK_HALF_EXTENTS,
				hp = BRICK_HP,
				color = BRICK_COLUMN_COLORS[(col % #BRICK_COLUMN_COLORS) + 1],
				flash_timer = 0.0,
				bounce_cooldown = 0.0,
			})
		end
	end
end

function breakout.enter()
	local character = campaign_context.campaign.character
	player = {
		ship = ship_state.new(Vector2.new(140.0, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0), 0, Vector2.new(14 * 1.5, 28 * 1.5)), -- 2026-10-05 "tout plus gros" pass
		gauge = 0.0,
		lift_charge_timer = 0.0,
		fire_cooldown = 0.0,
		fire_held_duration = 0.0,
		character = character,
		-- Vif's charged-shot recoil kick (charged_shot.lua's "recoil" spec)
		-- — 0 for every other character, who never call apply_recoil().
		recoil_peak = 0.0,
		recoil_timer = 0.0,
		recoil_decay_time = 1.0,
	}
	ball = ball_state.new(Vector2.new(FRONTIER_X, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0), Vector2.new(-ball_state.BASE_SPEED * 0.7, 0.0))
	bullets = {}
	impacts = {}
	enemies = {}
	player_turrets = {}
	player_lasers = {}
	spawn_brick_grid()
	enemy_spawn_timer = ENEMY_SPAWN_INTERVAL
	resolved = false
	countdown_value = 0
	countdown_timer = 0.0
	message = ""
	escape_prev = true
	confirm_prev = true
end

local function spawn_impact(position, weapon_id, target_half_extents)
	table.insert(impacts, charged_shot.build_impact(position, weapon_id, target_half_extents))
end

-- Guards a staggered burst's delayed callback against firing after the
-- level has already resolved (won/lost) and moved on.
local function level_still_active()
	return not resolved
end

local function fire_simple_shot()
	table.insert(bullets, {
		position = player.ship.position,
		velocity = Vector2.new(PLAYER_SHOT_SPEED, 0.0),
		owner_side = 0,
		is_player_shot = true,
		damage = PLAYER_SHOT_DAMAGE,
		weapon_id = "machine_gun",
	})
end

local function fire_charged_shot()
	charged_shot.fire(player.character.id, {
		get_position = function() return player.ship.position end,
		spawn_bullet = function(fields)
			fields.owner_side = 0
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

local function freeze_for_countdown()
	for _, enemy in ipairs(enemies) do
		enemy.autofire = false
	end
end

local function start_countdown()
	freeze_for_countdown()
	countdown_value = 3
	countdown_timer = COUNTDOWN_TICK
	message = tostring(countdown_value)
end

local function end_countdown()
	message = ""
	for _, enemy in ipairs(enemies) do
		enemy.autofire = true
	end
end

local function spawn_enemy_group()
	local alive = #enemies
	if alive >= ENEMY_MAX_ALIVE then
		return
	end
	local group_size = math.random(2, 3)
	for _ = 1, group_size do
		table.insert(enemies, {
			position = Vector2.new(
				BRICK_FIELD_START_X - 20.0 + math.random() * ((BRICK_COLS - 1) * BRICK_PITCH_X + 40.0),
				BRICK_FIELD_START_Y - 10.0 + math.random() * ((BRICK_ROWS - 1) * BRICK_PITCH_Y + 20.0)
			),
			half_extents = Vector2.new(15.0, 15.0),
			hp = ENEMY_HP,
			fire_cooldown_period = 1.0 / ENEMY_FIRE_RATE,
			fire_cooldown = 1.0 / ENEMY_FIRE_RATE,
			autofire = true,
			flash_timer = 0.0,
			bounce_cooldown = 0.0,
		})
	end
end

local function point_in_obstacle(obstacle, point, margin_x, margin_y)
	margin_x = margin_x or 0.0
	margin_y = margin_y or margin_x
	local left = obstacle.position.x - obstacle.half_extents.x - margin_x
	local right = obstacle.position.x + obstacle.half_extents.x + margin_x
	local top = obstacle.position.y - obstacle.half_extents.y - margin_y
	local bottom = obstacle.position.y + obstacle.half_extents.y + margin_y
	return point.x >= left and point.x <= right and point.y >= top and point.y <= bottom
end

-- 2026-09-16 (Camil: "beaucoup trop facile et ne ressemble pas a celui
-- qu'on avait dans Godot") — ball_node.gd expands EVERY ball-vs-obstacle
-- rect (ships AND turrets/bricks, _ship_rect()/_turret_rect()) by
-- BallState.RADIUS on every side, since the ball has real size; this port's
-- point_in_obstacle() only ever tested the ball's bare CENTER point against
-- the obstacle's own unexpanded rect for bricks/enemies (the paddle check
-- a few lines down already did this correctly) — bricks/enemies read as a
-- meaningfully smaller (~30-65%, depending on size) target than in Godot,
-- both cheating the player out of bounces/speed-ramp and making the whole
-- level clear faster than intended.
local function ball_overlaps_obstacle(obstacle, ball_position)
	return point_in_obstacle(obstacle, ball_position, ball_state.RADIUS)
end

-- Godot's projectile_node.gd inflates the HIT target by the shooter's own
-- `hit_half_size` (a Minkowski sum with the bullet's visual size) rather
-- than testing a bare point — defaults to Vector2(4,4) for a shot with no
-- dedicated art (turret_bullet.png IS real art in Godot, so its actual
-- texture*visual_scale size is used there; this port has no per-bullet
-- hit_half_size at all, so a flat 4px match Godot's own no-art fallback,
-- narrowing the "too easy to dodge" gap without inventing new per-bullet
-- sizing machinery this port doesn't otherwise have).
local ENEMY_SHOT_HIT_MARGIN = 4.0

local function resolve(won)
	-- Cheat menu fight (campaign_context.debug_encounter set): mirrors
	-- match_arena.lua's own resolve_campaign_result() guard exactly — "no
	-- currency/unlock/progress side effects", bounces back to the cheat
	-- menu instead of CampaignMap so a debug fight can never corrupt real
	-- campaign progress on disk.
	if campaign_context.debug_encounter then
		message = won and "Victoire (test)" or "Defaite..."
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
		-- Graph-mode characters (a real Atelier Cartographe export) mark
		-- this node resolved by id; branch/linear-mode characters keep the
		-- old linear step counter (see campaign_map.lua's own doc comment).
		if campaign_context.is_graph_mode then
			campaign_save.add_resolved_case_id(character_id, campaign_context.current_graph_node_id)
		else
			campaign_context.advance_step()
			campaign_save.set_campaign_progress(character_id, campaign_context.campaign_step)
		end
	else
		message = "Defaite..."
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
			charged_shot.update_homing_bullet(bullet, dt, { bricks, enemies })
		end
		bullet.position = bullet.position + bullet.velocity * dt
		if bullet.position.x < ARENA_BOUNDS.position.x - 32.0 or bullet.position.x > ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x + 32.0 then
			remove = true
		end

		if bullet.is_player_shot then
			-- Player shots hit bricks/enemies.
			local hit_something = false
			for _, obstacle_list in ipairs({ bricks, enemies }) do
				for _, obstacle in ipairs(obstacle_list) do
					if obstacle.hp > 0.0 and point_in_obstacle(obstacle, bullet.position) then
						obstacle.hp = obstacle.hp - bullet.damage * WEAPON_DAMAGE_VS_OBSTACLE_SCALE
						obstacle.flash_timer = 0.08
						spawn_impact(bullet.position, bullet.weapon_id, obstacle.half_extents)
						hit_something = true
						break
					end
				end
				if hit_something then
					break
				end
			end
			if hit_something then
				remove = true
			end
		else
			-- Enemy shots hit the player.
			if point_in_obstacle({ position = player.ship.position, half_extents = player.ship.half_extents }, bullet.position, ENEMY_SHOT_HIT_MARGIN) then
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

local function update_obstacles(list, dt)
	local i = 1
	while i <= #list do
		local obstacle = list[i]
		obstacle.flash_timer = math.max(obstacle.flash_timer - dt, 0.0)
		obstacle.bounce_cooldown = math.max(obstacle.bounce_cooldown - dt, 0.0)
		if obstacle.hp <= 0.0 then
			-- Camil: "il faudrait aussi que les petits ennemis explosent
			-- quand on les tue" (asked for Gradius, applied here too for
			-- consistency) — a real death explosion, distinct from the
			-- small hit-spark any non-lethal hit already gets.
			table.insert(impacts, charged_shot.build_impact(obstacle.position, "bazooka"))
			table.remove(list, i)
		else
			if obstacle.autofire ~= nil and countdown_value == 0 then
				obstacle.fire_cooldown = obstacle.fire_cooldown - dt
				if obstacle.autofire and obstacle.fire_cooldown <= 0.0 then
					obstacle.fire_cooldown = obstacle.fire_cooldown_period
					local aim = (player.ship.position - obstacle.position):normalized()
					table.insert(bullets, {
						position = obstacle.position,
						velocity = aim * 480.0,
						owner_side = 1,
						is_player_shot = false,
						damage = ENEMY_DAMAGE,
						weapon_id = "machine_gun",
					})
				end
			end
			i = i + 1
		end
	end
end

function breakout.update(dt)
	local escape = input.solo_escape()
	if escape and not escape_prev then
		-- Cheat-menu fights bail straight back to the cheat menu instead of
		-- CampaignMap (mirrors match_arena.lua's own debug-escape handling)
		-- — counts as neither a win nor a loss, nothing granted/advanced.
		-- Read debug_encounter BEFORE return_to_map() clears it.
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
	update_obstacles(bricks, dt)
	update_obstacles(enemies, dt)

	if countdown_value > 0 then
		countdown_timer = countdown_timer - dt
		if countdown_timer <= 0.0 then
			countdown_value = countdown_value - 1
			countdown_timer = COUNTDOWN_TICK
			if countdown_value > 0 then
				message = tostring(countdown_value)
			else
				end_countdown()
			end
		end
		return -- ship/ball/enemy-spawn stay frozen for the whole countdown
	end

	-- Player movement/fire.
	local move = Vector2.new(0.0, 0.0)
	if input.solo_right() then move.x = move.x + 1.0 end
	if input.solo_left() then move.x = move.x - 1.0 end
	if input.solo_down() then move.y = move.y + 1.0 end
	if input.solo_up() then move.y = move.y - 1.0 end
	local lift_held = input.solo_lift()
	if lift_held then
		player.lift_charge_timer = math.min(player.lift_charge_timer + dt, LIFT_CHARGE_CAP)
	else
		player.lift_charge_timer = 0.0
	end

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
		fields.owner_side = 0
		fields.is_player_shot = true
		table.insert(bullets, fields)
	end)
	charged_shot.update_lasers(player_lasers, dt, function()
		return { bricks, enemies }
	end)

	enemy_spawn_timer = enemy_spawn_timer - dt
	if enemy_spawn_timer <= 0.0 then
		enemy_spawn_timer = ENEMY_SPAWN_INTERVAL
		spawn_enemy_group()
	end

	-- Ball.
	ball = ball_state.update(ball, dt)
	local min_y = ARENA_BOUNDS.position.y + ball_state.RADIUS
	local max_y = ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y - ball_state.RADIUS
	if ball.position.y <= min_y then
		ball = ball_state.bounced_off_wall(ball, min_y)
	elseif ball.position.y >= max_y then
		ball = ball_state.bounced_off_wall(ball, max_y)
	end
	-- Far wall bounces instead of scoring (Camil: "la balle rebondisse
	-- aussi au fond oppose, au lieu de reapparaitre au milieu").
	local max_x = ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x - ball_state.RADIUS
	if ball.position.x >= max_x then
		ball = ball_state.bounced_off_side_wall(ball, max_x)
	end

	-- Ball vs bricks/enemies: mirror-deflect AND chip 1 hp ("on casse les
	-- regles pour ce mode" — a real Controleur turret never takes ball-
	-- bounce damage, but Breakout's obstacles do).
	for _, obstacle_list in ipairs({ bricks, enemies }) do
		for _, obstacle in ipairs(obstacle_list) do
			if obstacle.bounce_cooldown <= 0.0 and ball_overlaps_obstacle(obstacle, ball.position) then
				ball = ball_state.returned(ball, Vector2.ZERO, 0.0, -1, ball_state.SPEED_INCREMENT_PER_RETURN * 0.5)
				obstacle.bounce_cooldown = 0.2
				obstacle.hp = obstacle.hp - 1.0
				obstacle.flash_timer = 0.08
			end
		end
	end

	-- Ball vs player paddle.
	local bx, by = ball.position.x, ball.position.y
	local hx, hy = player.ship.half_extents.x + ball_state.RADIUS, player.ship.half_extents.y + ball_state.RADIUS
	if ball.velocity.x < 0.0
		and bx >= player.ship.position.x - hx and bx <= player.ship.position.x + hx
		and by >= player.ship.position.y - hy and by <= player.ship.position.y + hy then
		local move_dir = Vector2.new(move.x, move.y)
		local lift = lift_charge_fraction(player.lift_charge_timer)
		-- 2026-10-05 (same paddle-feel fix as match_arena.lua's own — see
		-- ball_state.returned()'s doc comment): where the ball hit the
		-- paddle drives the bounce angle, movement direction only nudges it.
		local contact_offset = (ball.position.y - player.ship.position.y) / player.ship.half_extents.y
		ball = ball_state.returned(ball, move_dir, lift, 1, ball_state.SPEED_INCREMENT_PER_RETURN * 0.5, contact_offset)
		local fill_amount = mathx.lerp(weapon_system_state.RETURN_GAUGE_FILL, weapon_system_state.RETURN_GAUGE_FILL_MAX_LIFT, lift)
		player.gauge = math.min(player.gauge + fill_amount, GAUGE_MAX)
	end

	-- Miss (past the player, off the left edge).
	if ball.position.x < ARENA_BOUNDS.position.x - ball_state.RADIUS then
		player.ship = ship_state.damaged(player.ship, MISS_DAMAGE)
		ball = ball_state.new(Vector2.new(FRONTIER_X, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0), Vector2.new(-ball_state.BASE_SPEED * 0.7, 0.0))
		start_countdown()
		return
	end

	if #bricks == 0 then
		resolved = true
		resolve(true)
	elseif player.ship.hp <= 0.0 then
		resolved = true
		resolve(false)
	end
end

local function draw_obstacle(obstacle, base_color)
	local flash = obstacle.flash_timer > 0.0 and 1.6 or 1.0
	love.graphics.setColor(math.min(base_color[1] * flash, 1.0), math.min(base_color[2] * flash, 1.0), math.min(base_color[3] * flash, 1.0))
	love.graphics.rectangle(
		"fill",
		obstacle.position.x - obstacle.half_extents.x,
		obstacle.position.y - obstacle.half_extents.y,
		obstacle.half_extents.x * 2.0,
		obstacle.half_extents.y * 2.0
	)
end

function breakout.draw()
	love.graphics.setColor(0.08, 0.09, 0.12)
	love.graphics.rectangle("fill", ARENA_BOUNDS.position.x, ARENA_BOUNDS.position.y, ARENA_BOUNDS.size.x, ARENA_BOUNDS.size.y)

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

	for _, brick in ipairs(bricks) do
		draw_obstacle(brick, brick.color)
	end
	for _, enemy in ipairs(enemies) do
		draw_obstacle(enemy, ENEMY_COLOR)
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
				image = image[bullet.owner_side]
			end
		end
		love.graphics.setColor(1, 1, 1)
		local flip_h = bullet.velocity.x < 0.0
		draw_utils.draw_scaled(image, bullet.position.x, bullet.position.y, scale, flip_h, bullet.rotation or 0.0)
	end

	love.graphics.setLineWidth(2.0)
	for _, impact in ipairs(impacts) do
		charged_shot.draw_impact(impact)
	end
	love.graphics.setLineWidth(1.0)

	love.graphics.setColor(1, 1, 1)
	draw_utils.draw_scaled(assets.ball, ball.position.x, ball.position.y, 1.4 * 1.5) -- 2026-10-05 "tout plus gros" pass — same RADIUS-independent draw scale bug as match_arena.lua's own ball

	love.graphics.setColor(1, 1, 1)
	love.graphics.print(string.format("%s   Briques restantes : %d", player.character.display_name, #bricks), 40, 24)
	love.graphics.setColor(0.15, 0.15, 0.18)
	love.graphics.rectangle("fill", 40, 44, 240, 10)
	love.graphics.setColor(0.3, 0.9, 0.4)
	love.graphics.rectangle("fill", 40, 44, 240 * mathx.clampf(player.ship.hp / ship_state.START_HP, 0.0, 1.0), 10)
	love.graphics.setColor(0.15, 0.15, 0.18)
	love.graphics.rectangle("fill", 40, 58, 240, 6)
	love.graphics.setColor(1.0, 0.85, 0.2)
	love.graphics.rectangle("fill", 40, 58, 240 * mathx.clampf(player.gauge / GAUGE_MAX, 0.0, 1.0), 6)

	if message ~= "" then
		love.graphics.setColor(1, 1, 1)
		love.graphics.printf(message, ARENA_BOUNDS.position.x, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0 - 10, ARENA_BOUNDS.size.x, "center")
	end

	love.graphics.setColor(0.65, 0.65, 0.7)
	love.graphics.printf("ZQSD : deplacer — Espace : tirer (maintenir = attaque speciale) — Maj : charger le lift — Echap : abandonner", 0, 20, 1280, "center")
end

return breakout
