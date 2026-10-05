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
local charged_shot = require("charged_shot")

-- Third campaign mini-jeu (2026-09-16), alongside Breakout and Space
-- Invaders — classic Gradius-style auto-scroll: a steady stream of enemies
-- spawns off the right edge and drifts left, ending in a real multi-part
-- boss fight.
--
-- Unlike Breakout/Space Invaders, the player is NOT confined to a "half"
-- of the arena — frontier_x is pushed past the arena's own right edge
-- (FULL_FREEDOM_FRONTIER_X below), which makes ship_state's existing
-- side-0 clamp span the WHOLE arena instead, with no change to
-- simulation/ship_state.lua itself needed.
--
-- 2026-09-16 follow-up (Camil, after playtesting): unlike Breakout/Space
-- Invaders, this mode does NOT reuse the player's own character kit
-- (weapon_system_state/WeaponData) — "selon les persos, ca marche pas.
-- Lourd a un tir bien trop lent, Controleur n'en parlons pas [...] il
-- faudrait un tir simple, comme dans Gradius, quel que soit le vaisseau."
-- Controleur's kit is effect_type=="turret" (no projectile fires at all
-- without dedicated turret-placement wiring, which this mode never had —
-- same known gap as Breakout/Space Invaders' own turret/beam dispatch);
-- Lourd's bazooka is a slow, heavy single shot, wrong feel for a
-- continuous scrolling shooter. Rather than special-case every kit, the
-- player gets ONE simple, fast, uniform shot regardless of character —
-- matching the genre convention (a Gradius/R-Type ship's weapon comes from
-- POWERUPS, never "which pilot you picked"). The character only still
-- decides the ship's sprite art and campaign identity (currency/id).
local gradius = {}

local ARENA_BOUNDS = Rect2.new(40.0, 60.0, 1200.0, 600.0)
-- Pushing frontier_x past the arena's own right edge makes ship_state's
-- existing side-0 clamp (`frontier_x - NEUTRAL_ZONE_HALF_WIDTH -
-- half_extents.x`) land exactly on ARENA_BOUNDS's real right edge — full
-- arena freedom with zero changes to the shared clamp logic.
local FULL_FREEDOM_FRONTIER_X = ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x + ship_state.NEUTRAL_ZONE_HALF_WIDTH

-- 2026-09-21 (Camil, after playtesting: "il y avait des ennemis
-- intouchables car ils etaient trop hauts / bas") — the player's own ship
-- (half_extents.y=28, see player.ship's own ship_state.new() call below)
-- can only ever reach Y in [ARENA_BOUNDS top + 28, ARENA_BOUNDS bottom -
-- 28] (ship_state's own clamp_to_half()) — enemies spawning or bobbing
-- anywhere outside that band (Waver's own vertical bob especially, up to
-- +-60px on top of an unclamped spawn Y across the WHOLE arena height)
-- could end up somewhere the player's own ship physically cannot align
-- with vertically to shoot back.
local PLAYER_SHIP_HALF_EXTENTS_Y = 28.0 * 1.5 -- 2026-10-05 "tout plus gros" pass — must stay in sync with the ship's own half_extents below
local PLAYABLE_Y_MIN = ARENA_BOUNDS.position.y + PLAYER_SHIP_HALF_EXTENTS_Y
local PLAYABLE_Y_MAX = ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y - PLAYER_SHIP_HALF_EXTENTS_Y

-- A simple, fast, uniform shot — see the header note above. Roughly
-- matches machine_gun.lua's own baseline feel (damage 2, ~5-6 shots/sec)
-- rather than any one character's real kit.
local PLAYER_FIRE_RATE = 6.0 -- shots/sec
local PLAYER_SHOT_DAMAGE = 2.0
local PLAYER_SHOT_SPEED = 700.0

-- 2026-09-19 (Camil: "j'aime bien l'idee de garder quand meme l'identite de
-- chaque perso [...] se baser sur le tir charge") — Gradius never had any
-- charge mechanic at all before this; the NORMAL shot above (including its
-- weapon-level fan pattern) is untouched, this only adds a hold-to-charge
-- release that fires the player's character-specific special move (see
-- charged_shot.lua) — same grace/duration convention Space Invaders/
-- Breakout's own (now-removed) uniform 6-shot charge used.
local CHARGE_GRACE = 1.0
local CHARGE_DURATION = 1.0

-- 2026-09-18 (Camil, after playtesting the simple-shot version: "pas mal
-- mais il faudrait que ce soit au moins 2x plus long, 2x plus dur") —
-- spawn threshold doubled outright (2x longer, literally); the rest of
-- these bumped ~30-60% (spawning faster/denser, tougher enemies/boss) —
-- compounding several "harder" dials at once multiplies fast, so this
-- stops short of a flat 2x on everything to avoid landing unplayable on
-- the first pass. Tune further after another playtest.
local ENEMY_SPAWN_INTERVAL = 0.9
local ENEMY_MAX_ALIVE = 14
local ENEMY_SPAWN_X = ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x + 40.0 -- just off the right edge

-- 2026-09-19 (Camil: "et les ennemis doivent tirer") — every archetype
-- fires now, not just "shooter": drone fires a slow, weak, non-homing shot
-- (barely more than a moving obstacle); waver fires a bit faster with mild
-- homing, since it's already partly dodging via its bob; shooter (below)
-- remains the dedicated heavy-hitter.
local DRONE_HALF_EXTENTS = Vector2.new(16.0, 16.0)
local DRONE_HP = 3.0
local DRONE_SPEED = 140.0
local DRONE_FIRE_RATE = 0.35
local DRONE_DAMAGE = 4.0
-- 2026-09-20 (Camil: "un petit effet de reacteur avec des particules
-- derriere aux serait un plus") — a small trailing engine-glow particle
-- emitted periodically behind the Drone as it flies.
local DRONE_TRAIL_INTERVAL = 0.04
local DRONE_TRAIL_DURATION = 0.3
local DRONE_TRAIL_COLOR = { 1.0, 0.65, 0.2 }

local WAVER_HALF_EXTENTS = Vector2.new(16.0, 16.0)
local WAVER_HP = 3.0
local WAVER_SPEED = 110.0
local WAVER_BOB_AMPLITUDE = 60.0
local WAVER_BOB_ANGULAR_SPEED = 2.0 -- rad/s
local WAVER_FIRE_RATE = 0.5
local WAVER_DAMAGE = 5.0
local WAVER_HOMING_STRENGTH = 0.4 -- weaker than shooter's — it's already dodging via its bob

local SHOOTER_HALF_EXTENTS = Vector2.new(18.0, 18.0)
local SHOOTER_HP = 7.0
local SHOOTER_SPEED = 90.0
local SHOOTER_FIRE_RATE = 0.8
local SHOOTER_DAMAGE = 7.0
local SHOOTER_HOMING_STRENGTH = 0.6 -- same modest "un peu a tete chercheuse" value Space Invaders' aliens use

-- 2026-09-19 (Camil, v1: "il faudrait qu'on ait 3 PV [...]") then v2 (after
-- playtesting v1 — "trop dur [...] on va bien garder la jauge 1/2/3 [...]
-- mais on va aussi ajouter 3 coeurs") tried a classic Gradius-style
-- discrete-lives model. 2026-09-20 (Camil, after more playtesting: "pour
-- les coeurs dans gradius, on laisse tomber, on va revenir sur la barre de
-- vie classique") — reverted back to the same continuous ship_state.hp bar
-- Breakout/Space Invaders both use. The weapon-level gauge is UNCHANGED
-- (still drops by 1 on every hit, see player_hit() below) — only the
-- life/HP side of "on se fait toucher" moves back to a continuous bar.
local CONTACT_INVULN_DURATION = 0.5 -- a single hit can't multi-tick across several overlapping sources the same instant
-- Enemy/boss BULLETS already carry their own tuned `damage` field (see
-- DRONE_DAMAGE/WAVER_DAMAGE/SHOOTER_DAMAGE/BOSS_WEAK_POINT_DAMAGE below) —
-- these two are only for physically TOUCHING something, which never had a
-- damage number of its own under the discrete-lives model.
local CONTACT_DAMAGE = 12.0
local BOSS_CONTACT_DAMAGE = 16.0
local BOSS_LASER_DAMAGE = 20.0

local BOSS_SPAWN_THRESHOLD = 60 -- enemies cleared (killed or drifted off) before the boss shows up; spawner stops once it does — was 30, doubled per Camil's "2x plus long"

-- 2026-09-19 (Camil: "encore beaucoup trop facile. Le boss doit etre bien
-- plus gros, avec plus de tourelles") — 3 -> 5 weak points, spread over a
-- much taller formation (BOSS_ANCHOR_BOB_AMPLITUDE=80 plus the widest
-- +-180 offset still fits inside ARENA_BOUNDS's 600px height), plus a
-- visible hull backdrop behind them (see BOSS_HULL_* below and the draw
-- code) so the whole thing actually reads as one big ship, not 3-5 boxes
-- floating in space.
local BOSS_WEAK_POINT_HP = 32.0
local BOSS_WEAK_POINT_HALF_EXTENTS = Vector2.new(24.0, 24.0)
local BOSS_WEAK_POINT_OFFSETS = {
	Vector2.new(0.0, -180.0), Vector2.new(0.0, -90.0), Vector2.new(0.0, 0.0),
	Vector2.new(0.0, 90.0), Vector2.new(0.0, 180.0),
}
-- 2026-09-20 (Camil: "le boss est vraiment chaud [...] reduire sa
-- frequence de tir normal de 20%") — was 0.5.
local BOSS_WEAK_POINT_FIRE_RATE = 0.5 * 0.8
local BOSS_WEAK_POINT_DAMAGE = 8.0
local BOSS_WEAK_POINT_HOMING_STRENGTH = 0.8
local BOSS_ANCHOR_X = ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x - 180.0
local BOSS_ANCHOR_BASE_Y = ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0
local BOSS_ANCHOR_BOB_AMPLITUDE = 60.0
local BOSS_ANCHOR_BOB_ANGULAR_SPEED = 0.6 -- rad/s
local BOSS_HULL_HALF_WIDTH = 70.0
local BOSS_HULL_PADDING_Y = 40.0 -- extends the hull past the top/bottom weak points
local BOSS_PHASE2_HP_FRACTION = 0.66
local BOSS_PHASE3_HP_FRACTION = 0.33
local BOSS_PHASE2_FIRE_RATE_MULTIPLIER = 1.5
local BOSS_PHASE3_FIRE_RATE_MULTIPLIER = 2.2
local BOSS_PHASE_MESSAGE_DURATION = 2.2

-- 2026-09-20 (Camil: "quand on le tue, il faudrait une grosse explosion
-- (particules), sur 3 secondes, puis fin du niveau") — once every weak
-- point hits 0, the boss stops acting (no more attack-cycle/continuous
-- fire) and a rolling series of big_explosion impacts (reusing
-- charged_shot's own real "bazooka" impact style) fires across the hull
-- for this long before the level actually resolves as a win.
local BOSS_DEATH_DURATION = 3.0
local BOSS_DEATH_EXPLOSION_INTERVAL = 0.25

-- 2026-09-20 (Camil, after playtesting: "c'est bien les petites explosions
-- partout, mais a la fin il faut que ce soit le sprite qui eclate") — in
-- the closing stretch of the death sequence, the hull/weak-point SPRITES
-- themselves stop being drawn and are replaced by a burst of tumbling
-- fragments (colors sampled from the hull's own dark purple and the weak
-- points' own magenta), reading as the ship physically breaking apart
-- rather than just taking hits while still intact.
local BOSS_SHATTER_TRIGGER_TIME = 0.8 -- seconds of boss_death_timer REMAINING when the shatter fires
local BOSS_SHATTER_FRAGMENT_COUNT = 22
local BOSS_SHATTER_FRAGMENT_MIN_SIZE = 6.0
local BOSS_SHATTER_FRAGMENT_MAX_SIZE = 16.0
local BOSS_SHATTER_FRAGMENT_MIN_SPEED = 90.0
local BOSS_SHATTER_FRAGMENT_MAX_SPEED = 260.0
local BOSS_SHATTER_FRAGMENT_SPIN_MAX = 540.0 -- deg/sec
local BOSS_SHATTER_FRAGMENT_DURATION = 1.1
local BOSS_SHATTER_FRAGMENT_COLORS = {
	{ 0.2, 0.08, 0.22 }, -- hull dark purple
	{ 0.55, 0.15, 0.55 }, -- weak-point magenta
}

-- 2026-09-19 (Camil: "le boss est vraiment nul, il faut qu'il tire plus,
-- en alternant des tirs en spirale, des tirs lasers, et des missiles") —
-- ON TOP OF the 3 weak points' own continuous straight-homing fire above,
-- the boss now cycles through one of these three special attacks,
-- switching every BOSS_ATTACK_CYCLE_DURATION.
local BOSS_ATTACK_PATTERNS = { "spiral", "laser", "missile" }
local BOSS_ATTACK_CYCLE_DURATION = 4.0
local BOSS_ATTACK_MESSAGES = { spiral = "Tirs en spirale !", laser = "LASER !", missile = "Missiles !" }

local SPIRAL_BURST_INTERVAL = 0.45
local SPIRAL_BULLET_COUNT = 10
local SPIRAL_BULLET_SPEED = 260.0
local SPIRAL_ROTATION_STEP_DEG = 24.0

local LASER_INTERVAL = 1.8
local LASER_TELEGRAPH_DURATION = 0.7
local LASER_ACTIVE_DURATION = 0.4
local LASER_THICKNESS = 22.0
local LASER_TELEGRAPH_COLOR = { 1.0, 0.3, 0.3, 0.5 }
local LASER_ACTIVE_COLOR = { 1.0, 0.25, 0.2, 0.85 }

local MISSILE_INTERVAL = 0.5
local MISSILE_COUNT_PER_VOLLEY = 2
local MISSILE_VOLLEY_OFFSET_Y = 24.0
local MISSILE_SPEED = 320.0
local MISSILE_HOMING_STRENGTH = 1.4

local STARFIELD_LAYER_SPEEDS = { 40.0, 80.0, 140.0 }
local STARFIELD_STARS_PER_LAYER = 24

-- 2026-09-18 (Camil: "il faudrait [...] quelques bonus (speed up, power up
-- (tir double, puis quadruple avec le tir du haut qui part a 30 et celui
-- du bas a -30)") — classic Gradius-style pickups. A killed enemy (never
-- an off-screen despawn — no free drops for ignoring a threat) has a
-- chance to drop one, drifting left slowly until collected or it exits
-- the arena.
--
-- 2026-09-19 (Camil, v1: "les bonus n'apparaissent que quand on a tue un
-- certain nombre d'ennemis (15 par exemple)") — replaces the old per-kill
-- random chance with a kill-count milestone, guaranteed, instead of drop
-- RNG that could (and did) go many kills without ever paying out.
--
-- 2026-09-19 (Camil, v2: "on peut descendre les kills a 10, puis 11 pour
-- le suivant, puis 12... etc.") — a flat interval was replaced with a
-- growing one: the first drop lands at 10 kills, the next after 11 more
-- (21), the next after 12 more (33), and so on — each gap one kill longer
-- than the last, so drops start out generous and gradually space out as
-- the run goes on. See init_powerup_schedule()/its use in enemy-kill
-- handling below.
local POWERUP_HALF_EXTENTS = Vector2.new(12.0 * 1.5, 12.0 * 1.5) -- 2026-10-05 "tout plus gros" pass (Camil: "augmente la taille des bonus aussi") — drives both the sprite size AND the pickup hitbox
local POWERUP_FIRST_KILL_INTERVAL = 10
local POWERUP_DRIFT_SPEED = 60.0
local POWERUP_SPEED_COLOR = { 0.4, 0.85, 1.0 }
local POWERUP_WEAPON_COLOR = { 1.0, 0.55, 0.15 }
-- 2026-09-19 (Camil: "il peut y avoir Power, Speed, et Coeur") — a third
-- drop kind, alongside speed/weapon. 2026-09-20 (Camil, after reverting to
-- the classic HP bar: "un bonus de coeur redonne 20% de l'energie") — heals
-- a flat fraction of ship_state.START_HP rather than granting a life.
local HEART_HEAL_FRACTION = 0.2

-- Speed-up: +25%/pickup, capped at +75% (4 stacks) — a permanent boost for
-- the rest of the run, same "collect and keep" convention Gradius itself
-- uses.
local SPEED_POWERUP_STEP = 0.25
local SPEED_POWERUP_MAX_MULTIPLIER = 1.75

-- Power-up (weapon level): 0 = the single simple shot: 1 = two parallel
-- shots; 2 = those two PLUS a pair angled outward at WEAPON_LEVEL_SPREAD_DEG
-- (top shot steers further up, bottom further down) — 4 shots at once.
local WEAPON_LEVEL_MAX = 2
local WEAPON_LEVEL_OFFSET_Y = 10.0
local WEAPON_LEVEL_SPREAD_DEG = 30.0

-- The player's simple shot always looks/behaves like a machine-gun bullet
-- (real texture, spark-ring impact) — see the header note on why this mode
-- doesn't read the character's own weapon.id. Impact styles for every
-- OTHER weapon id (the charged shots) come from charged_shot.lua's own
-- IMPACT_STYLE_BY_WEAPON — see spawn_impact() below.
local BULLET_VISUALS = {
	machine_gun = { radius = 3.0, color = { 1.0, 1.0, 0.6 }, scale = 1.4 * 1.5 }, -- 2026-10-05 "tout plus gros" pass
}
local SIDE_SPLIT_BULLET_WEAPONS = { machine_gun = true, turret = true }

local player, bullets, impacts, enemies, powerups
local player_turrets, player_lasers
local enemy_spawn_timer, enemies_cleared, enemy_kills
local next_powerup_kill_threshold, next_powerup_kill_interval
local boss
local boss_dying, boss_death_timer, boss_death_explosion_timer
local boss_shatter_triggered, boss_shatter_particles
local enemy_trail_particles
local resolved, message
local contact_invuln_timer
local wave_time
local starfield
local cheat_win_prev
local escape_prev

local function rects_overlap(a_pos, a_half, b_pos, b_half)
	return math.abs(a_pos.x - b_pos.x) < (a_half.x + b_half.x)
		and math.abs(a_pos.y - b_pos.y) < (a_half.y + b_half.y)
end

-- Any hit — contact or bullet, from any source — chips the classic
-- continuous HP bar by its own `damage` amount AND drops the weapon level
-- by one (Camil: "on va bien garder la jauge 1/2/3 [...] avec une
-- redescente quand on se fait toucher" — that part survived the hearts
-- revert). A no-op while still invulnerable from the last hit, so a single
-- exposure (one bullet, one graze) can never multi-tick.
local function player_hit(damage)
	if contact_invuln_timer > 0.0 then
		return
	end
	player.ship = ship_state.damaged(player.ship, damage)
	player.weapon_level = math.max(player.weapon_level - 1, 0)
	contact_invuln_timer = CONTACT_INVULN_DURATION
end

local function init_starfield()
	starfield = {}
	for layer = 1, #STARFIELD_LAYER_SPEEDS do
		local stars = {}
		for i = 1, STARFIELD_STARS_PER_LAYER do
			table.insert(stars, {
				x = ARENA_BOUNDS.position.x + math.random() * ARENA_BOUNDS.size.x,
				y = ARENA_BOUNDS.position.y + math.random() * ARENA_BOUNDS.size.y,
			})
		end
		starfield[layer] = stars
	end
end

function gradius.enter()
	local character = campaign_context.campaign.character
	player = {
		ship = ship_state.new(Vector2.new(160.0, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0), 0, Vector2.new(14 * 1.5, PLAYER_SHIP_HALF_EXTENTS_Y)),
		fire_cooldown = 0.0,
		character = character,
		speed_multiplier = 1.0,
		weapon_level = 0,
		fire_held_duration = 0.0,
		-- Vif's charged-shot recoil kick (charged_shot.lua's own "recoil"
		-- spec) — 0 for every other character, who never call apply_recoil().
		recoil_peak = 0.0,
		recoil_timer = 0.0,
		recoil_decay_time = 1.0,
	}
	bullets = {}
	impacts = {}
	enemies = {}
	powerups = {}
	player_turrets = {}
	player_lasers = {}
	enemy_spawn_timer = ENEMY_SPAWN_INTERVAL
	enemies_cleared = 0
	enemy_kills = 0
	next_powerup_kill_threshold = POWERUP_FIRST_KILL_INTERVAL
	next_powerup_kill_interval = POWERUP_FIRST_KILL_INTERVAL + 1
	boss = nil
	boss_dying = false
	boss_death_timer = 0.0
	boss_death_explosion_timer = 0.0
	boss_shatter_triggered = false
	boss_shatter_particles = {}
	enemy_trail_particles = {}
	contact_invuln_timer = 0.0
	wave_time = 0.0
	cheat_win_prev = false
	-- true, not false: if Escape is still physically held from whatever
	-- keypress launched this screen (e.g. the cheat menu's own launch key
	-- overlapping a not-yet-released Escape), the edge check below must NOT
	-- treat that as a fresh press — Camil: "il m'arrive de revenir sur
	-- l'ecran de selection en plein game sans toucher echap".
	escape_prev = true
	init_starfield()
	resolved = false
	message = ""
end

local function spawn_impact(position, weapon_id, target_half_extents)
	table.insert(impacts, charged_shot.build_impact(position, weapon_id, target_half_extents))
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

		if bullet.is_homing_toward_player then
			-- projectile_node.gd's non-full-turn homing branch: only the
			-- vertical speed steers toward the target, horizontal speed
			-- stays constant so it can never turn around.
			local desired_vy = mathx.clampf((player.ship.position.y - bullet.position.y) * 2.0, -260.0, 260.0)
			local new_vy = mathx.lerp(bullet.velocity.y, desired_vy, mathx.clampf(bullet.homing_strength * dt, 0.0, 1.0))
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
			local target_lists = { enemies }
			if boss then
				table.insert(target_lists, boss.weak_points)
			end
			charged_shot.update_homing_bullet(bullet, dt, target_lists)
		end
		bullet.position = bullet.position + bullet.velocity * dt
		if bullet.position.x < ARENA_BOUNDS.position.x - 32.0 or bullet.position.x > ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x + 32.0 then
			remove = true
		end

		if bullet.is_player_shot then
			local hit = false
			for _, enemy in ipairs(enemies) do
				if enemy.hp > 0.0 and point_in_obstacle(enemy, bullet.position) then
					enemy.hp = enemy.hp - bullet.damage
					enemy.flash_timer = 0.08
					spawn_impact(bullet.position, bullet.weapon_id, enemy.half_extents)
					remove = true
					hit = true
					break
				end
			end
			if not hit and boss then
				for _, weak_point in ipairs(boss.weak_points) do
					if weak_point.hp > 0.0 and point_in_obstacle(weak_point, bullet.position) then
						weak_point.hp = weak_point.hp - bullet.damage
						weak_point.flash_timer = 0.08
						spawn_impact(bullet.position, bullet.weapon_id, weak_point.half_extents)
						remove = true
						break
					end
				end
			end
		else
			if point_in_obstacle({ position = player.ship.position, half_extents = player.ship.half_extents }, bullet.position) then
				player_hit(bullet.damage)
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

local function update_enemy_trails(dt)
	local i = 1
	while i <= #enemy_trail_particles do
		local particle = enemy_trail_particles[i]
		particle.age = particle.age + dt
		if particle.age >= DRONE_TRAIL_DURATION then
			table.remove(enemy_trail_particles, i)
		else
			i = i + 1
		end
	end
end

local function spawn_enemy()
	if #enemies >= ENEMY_MAX_ALIVE then
		return
	end
	local y = PLAYABLE_Y_MIN + math.random() * (PLAYABLE_Y_MAX - PLAYABLE_Y_MIN)
	local roll = math.random()
	if roll < 0.45 then
		table.insert(enemies, {
			kind = "drone", position = Vector2.new(ENEMY_SPAWN_X, y), half_extents = DRONE_HALF_EXTENTS,
			hp = DRONE_HP, flash_timer = 0.0,
			fire_cooldown = math.random() * (1.0 / DRONE_FIRE_RATE),
			trail_timer = 0.0,
		})
	elseif roll < 0.8 then
		table.insert(enemies, {
			kind = "waver", position = Vector2.new(ENEMY_SPAWN_X, y), half_extents = WAVER_HALF_EXTENTS,
			hp = WAVER_HP, flash_timer = 0.0,
			base_y = y, phase = math.random() * math.pi * 2.0,
			fire_cooldown = math.random() * (1.0 / WAVER_FIRE_RATE),
		})
	else
		table.insert(enemies, {
			kind = "shooter", position = Vector2.new(ENEMY_SPAWN_X, y), half_extents = SHOOTER_HALF_EXTENTS,
			hp = SHOOTER_HP, flash_timer = 0.0,
			hold_x = ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x * (0.45 + math.random() * 0.3),
			holding = false,
			fire_cooldown = math.random() * (1.0 / SHOOTER_FIRE_RATE),
			fire_cooldown_period = 1.0 / SHOOTER_FIRE_RATE,
		})
	end
end

local function update_enemies(dt)
	enemy_spawn_timer = enemy_spawn_timer - dt
	if enemy_spawn_timer <= 0.0 then
		enemy_spawn_timer = ENEMY_SPAWN_INTERVAL
		if not boss then
			spawn_enemy()
		end
	end

	local still_alive = {}
	for _, enemy in ipairs(enemies) do
		if enemy.hp <= 0.0 then
			enemies_cleared = enemies_cleared + 1
			-- Camil: "il faudrait aussi que les petits ennemis explosent
			-- quand on les tue" — a real death explosion, distinct from the
			-- small hit-spark every non-lethal hit already gets. Reuses
			-- charged_shot's own real "bazooka" impact style (big_explosion).
			table.insert(impacts, charged_shot.build_impact(enemy.position, "bazooka"))
			-- A real kill (not an off-screen despawn, handled separately
			-- below) counts toward the growing kill-count milestone that
			-- drops a powerup — see POWERUP_FIRST_KILL_INTERVAL's own doc
			-- comment for the schedule (10, then +11, then +12, ...).
			enemy_kills = enemy_kills + 1
			if enemy_kills >= next_powerup_kill_threshold then
				next_powerup_kill_threshold = next_powerup_kill_threshold + next_powerup_kill_interval
				next_powerup_kill_interval = next_powerup_kill_interval + 1
				local roll = math.random()
				local kind = roll < (1.0 / 3.0) and "speed" or (roll < (2.0 / 3.0) and "weapon" or "heart")
				table.insert(powerups, {
					kind = kind,
					position = Vector2.new(enemy.position.x, enemy.position.y),
				})
			end
		else
			enemy.flash_timer = math.max(enemy.flash_timer - dt, 0.0)
			if enemy.kind == "drone" then
				enemy.position = Vector2.new(enemy.position.x - DRONE_SPEED * dt, enemy.position.y)
				enemy.fire_cooldown = enemy.fire_cooldown - dt
				if enemy.fire_cooldown <= 0.0 then
					enemy.fire_cooldown = 1.0 / DRONE_FIRE_RATE
					table.insert(bullets, {
						position = enemy.position,
						velocity = Vector2.new(-420.0, 0.0),
						damage = DRONE_DAMAGE,
						weapon_id = "machine_gun",
						is_player_shot = false,
					})
				end
				-- Thruster trail — see DRONE_TRAIL_*'s own doc comment.
				enemy.trail_timer = enemy.trail_timer - dt
				if enemy.trail_timer <= 0.0 then
					enemy.trail_timer = DRONE_TRAIL_INTERVAL
					table.insert(enemy_trail_particles, {
						position = Vector2.new(
							enemy.position.x + enemy.half_extents.x * 0.7,
							enemy.position.y + (math.random() - 0.5) * enemy.half_extents.y
						),
						age = 0.0,
					})
				end
			elseif enemy.kind == "waver" then
				local bobbed_y = enemy.base_y + math.sin(wave_time * WAVER_BOB_ANGULAR_SPEED + enemy.phase) * WAVER_BOB_AMPLITUDE
				enemy.position = Vector2.new(
					enemy.position.x - WAVER_SPEED * dt,
					mathx.clampf(bobbed_y, PLAYABLE_Y_MIN, PLAYABLE_Y_MAX)
				)
				enemy.fire_cooldown = enemy.fire_cooldown - dt
				if enemy.fire_cooldown <= 0.0 then
					enemy.fire_cooldown = 1.0 / WAVER_FIRE_RATE
					table.insert(bullets, {
						position = enemy.position,
						velocity = Vector2.new(-440.0, 0.0),
						damage = WAVER_DAMAGE,
						weapon_id = "machine_gun",
						is_player_shot = false,
						is_homing_toward_player = true,
						homing_strength = WAVER_HOMING_STRENGTH,
					})
				end
			elseif enemy.kind == "shooter" then
				if enemy.position.x > enemy.hold_x then
					enemy.position = Vector2.new(enemy.position.x - SHOOTER_SPEED * dt, enemy.position.y)
				else
					enemy.holding = true
					enemy.fire_cooldown = enemy.fire_cooldown - dt
					if enemy.fire_cooldown <= 0.0 then
						enemy.fire_cooldown = enemy.fire_cooldown_period
						table.insert(bullets, {
							position = enemy.position,
							velocity = Vector2.new(-480.0, 0.0),
							damage = SHOOTER_DAMAGE,
							weapon_id = "machine_gun",
							is_player_shot = false,
							is_homing_toward_player = true,
							homing_strength = SHOOTER_HOMING_STRENGTH,
						})
					end
				end
			end
			if enemy.position.x < ARENA_BOUNDS.position.x - 60.0 then
				enemies_cleared = enemies_cleared + 1
			else
				table.insert(still_alive, enemy)
			end
		end
	end
	enemies = still_alive
end

local function update_powerups(dt)
	local still_alive = {}
	for _, powerup in ipairs(powerups) do
		powerup.position = Vector2.new(powerup.position.x - POWERUP_DRIFT_SPEED * dt, powerup.position.y)
		if rects_overlap(player.ship.position, player.ship.half_extents, powerup.position, POWERUP_HALF_EXTENTS) then
			if powerup.kind == "speed" then
				player.speed_multiplier = math.min(player.speed_multiplier + SPEED_POWERUP_STEP, SPEED_POWERUP_MAX_MULTIPLIER)
			elseif powerup.kind == "weapon" then
				player.weapon_level = math.min(player.weapon_level + 1, WEAPON_LEVEL_MAX)
			else -- "heart" — Camil: "un bonus de coeur redonne 20% de l'energie"
				player.ship = ship_state.healed(player.ship, ship_state.START_HP * HEART_HEAL_FRACTION, ship_state.START_HP)
			end
		elseif powerup.position.x > ARENA_BOUNDS.position.x - 40.0 then
			table.insert(still_alive, powerup)
		end
	end
	powerups = still_alive
end

local function spawn_boss()
	local weak_points = {}
	for i, offset in ipairs(BOSS_WEAK_POINT_OFFSETS) do
		table.insert(weak_points, {
			offset = offset,
			position = Vector2.new(BOSS_ANCHOR_X, BOSS_ANCHOR_BASE_Y) + offset,
			hp = BOSS_WEAK_POINT_HP,
			half_extents = BOSS_WEAK_POINT_HALF_EXTENTS,
			flash_timer = 0.0,
			fire_rate_multiplier = 1.0,
			fire_cooldown = math.random() * (1.0 / BOSS_WEAK_POINT_FIRE_RATE),
			-- Camil provided 2 hand-picked art variations — alternated so
			-- the 5 weak points don't all look identical.
			sprite_variant = (i % #assets.gradius_boss_weakpoints) + 1,
		})
	end
	boss = {
		phase = 1,
		anchor_time = 0.0,
		anchor_position = Vector2.new(BOSS_ANCHOR_X, BOSS_ANCHOR_BASE_Y),
		weak_points = weak_points,
		phase_message_timer = BOSS_PHASE_MESSAGE_DURATION,
		-- Camil: "il faut qu'il tire plus, en alternant des tirs en
		-- spirale, des tirs lasers, et des missiles" — cycled on top of
		-- the weak points' own continuous fire above.
		attack_pattern_index = 1,
		attack_cycle_timer = BOSS_ATTACK_CYCLE_DURATION,
		attack_fire_timer = 0.0,
		spiral_angle = 0.0,
		lasers = {},
	}
	message = "Le Vaisseau-mere arrive !"
end

local function flash_boss_message(text)
	message = text
	boss.phase_message_timer = BOSS_PHASE_MESSAGE_DURATION
end

local function update_boss_attack_cycle(dt)
	boss.attack_cycle_timer = boss.attack_cycle_timer - dt
	if boss.attack_cycle_timer <= 0.0 then
		boss.attack_cycle_timer = BOSS_ATTACK_CYCLE_DURATION
		boss.attack_pattern_index = (boss.attack_pattern_index % #BOSS_ATTACK_PATTERNS) + 1
		boss.attack_fire_timer = 0.0
		flash_boss_message(BOSS_ATTACK_MESSAGES[BOSS_ATTACK_PATTERNS[boss.attack_pattern_index]])
	end

	local pattern = BOSS_ATTACK_PATTERNS[boss.attack_pattern_index]
	boss.attack_fire_timer = boss.attack_fire_timer - dt
	if boss.attack_fire_timer > 0.0 then
		return
	end

	if pattern == "spiral" then
		boss.attack_fire_timer = SPIRAL_BURST_INTERVAL
		boss.spiral_angle = boss.spiral_angle + SPIRAL_ROTATION_STEP_DEG
		for i = 0, SPIRAL_BULLET_COUNT - 1 do
			local angle = boss.spiral_angle + (360.0 / SPIRAL_BULLET_COUNT) * i
			table.insert(bullets, {
				position = boss.anchor_position,
				velocity = Vector2.new(SPIRAL_BULLET_SPEED, 0.0):rotated(mathx.deg_to_rad(angle)),
				damage = 1.0,
				weapon_id = "machine_gun",
				is_player_shot = false,
			})
		end
	elseif pattern == "missile" then
		boss.attack_fire_timer = MISSILE_INTERVAL
		for i = 1, MISSILE_COUNT_PER_VOLLEY do
			local offset_y = (i - (MISSILE_COUNT_PER_VOLLEY + 1) / 2.0) * MISSILE_VOLLEY_OFFSET_Y
			table.insert(bullets, {
				position = boss.anchor_position + Vector2.new(0.0, offset_y),
				velocity = Vector2.new(-MISSILE_SPEED, 0.0),
				damage = 1.0,
				weapon_id = "machine_gun",
				is_player_shot = false,
				is_homing_toward_player = true,
				homing_strength = MISSILE_HOMING_STRENGTH,
			})
		end
	elseif pattern == "laser" then
		boss.attack_fire_timer = LASER_INTERVAL
		table.insert(boss.lasers, {
			y = player.ship.position.y, -- aimed once at the player's current row, doesn't track afterward
			state = "telegraph",
			timer = LASER_TELEGRAPH_DURATION,
		})
	end
end

local function update_boss_lasers(dt)
	local still_active = {}
	for _, laser in ipairs(boss.lasers) do
		laser.timer = laser.timer - dt
		if laser.state == "telegraph" then
			if laser.timer <= 0.0 then
				laser.state = "active"
				laser.timer = LASER_ACTIVE_DURATION
			end
			table.insert(still_active, laser)
		elseif laser.state == "active" then
			if rects_overlap(
				player.ship.position, player.ship.half_extents,
				Vector2.new(ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x / 2.0, laser.y), Vector2.new(ARENA_BOUNDS.size.x / 2.0, LASER_THICKNESS / 2.0)
			) then
				player_hit(BOSS_LASER_DAMAGE)
			end
			if laser.timer > 0.0 then
				table.insert(still_active, laser)
			end
		end
	end
	boss.lasers = still_active
end

local function update_boss(dt)
	boss.anchor_time = boss.anchor_time + dt
	boss.anchor_position = Vector2.new(
		BOSS_ANCHOR_X,
		BOSS_ANCHOR_BASE_Y + math.sin(boss.anchor_time * BOSS_ANCHOR_BOB_ANGULAR_SPEED) * BOSS_ANCHOR_BOB_AMPLITUDE
	)

	update_boss_attack_cycle(dt)
	update_boss_lasers(dt)

	local total_start = 0.0
	local total_current = 0.0
	for _, weak_point in ipairs(boss.weak_points) do
		total_start = total_start + BOSS_WEAK_POINT_HP
		if weak_point.hp > 0.0 then
			total_current = total_current + weak_point.hp
			weak_point.position = boss.anchor_position + weak_point.offset
			weak_point.flash_timer = math.max(weak_point.flash_timer - dt, 0.0)
			weak_point.fire_cooldown = weak_point.fire_cooldown - dt
			if weak_point.fire_cooldown <= 0.0 then
				weak_point.fire_cooldown = 1.0 / (BOSS_WEAK_POINT_FIRE_RATE * weak_point.fire_rate_multiplier)
				table.insert(bullets, {
					position = weak_point.position,
					velocity = Vector2.new(-480.0, 0.0),
					damage = BOSS_WEAK_POINT_DAMAGE,
					weapon_id = "machine_gun",
					is_player_shot = false,
					is_homing_toward_player = true,
					homing_strength = BOSS_WEAK_POINT_HOMING_STRENGTH,
				})
			end
		end
	end
	local hp_fraction = total_current / total_start

	if boss.phase == 1 and hp_fraction <= BOSS_PHASE2_HP_FRACTION then
		boss.phase = 2
		for _, weak_point in ipairs(boss.weak_points) do
			weak_point.fire_rate_multiplier = BOSS_PHASE2_FIRE_RATE_MULTIPLIER
		end
		flash_boss_message("Ca chauffe !")
	elseif boss.phase == 2 and hp_fraction <= BOSS_PHASE3_HP_FRACTION then
		boss.phase = 3
		for _, weak_point in ipairs(boss.weak_points) do
			weak_point.fire_rate_multiplier = BOSS_PHASE3_FIRE_RATE_MULTIPLIER
		end
		flash_boss_message("DERNIERE TOURELLE !")
	end

	if boss.phase_message_timer > 0.0 then
		boss.phase_message_timer = math.max(boss.phase_message_timer - dt, 0.0)
		if boss.phase_message_timer <= 0.0 then
			message = ""
		end
	end
end

-- Camil: "quand on le tue, il faudrait une grosse explosion (particules),
-- sur 3 secondes, puis fin du niveau" — the boss stops acting entirely
-- once this starts (update_boss()/its attack cycle are no longer called),
-- while a rolling series of big_explosion impacts fires across its hull.
local function spawn_boss_shatter()
	local top_offset_y = BOSS_WEAK_POINT_OFFSETS[1].y
	local bottom_offset_y = BOSS_WEAK_POINT_OFFSETS[#BOSS_WEAK_POINT_OFFSETS].y
	for _ = 1, BOSS_SHATTER_FRAGMENT_COUNT do
		local angle = math.random() * math.pi * 2.0
		local speed = BOSS_SHATTER_FRAGMENT_MIN_SPEED + math.random() * (BOSS_SHATTER_FRAGMENT_MAX_SPEED - BOSS_SHATTER_FRAGMENT_MIN_SPEED)
		local color = BOSS_SHATTER_FRAGMENT_COLORS[math.random(1, #BOSS_SHATTER_FRAGMENT_COLORS)]
		table.insert(boss_shatter_particles, {
			position = Vector2.new(
				boss.anchor_position.x + (math.random() - 0.5) * BOSS_HULL_HALF_WIDTH * 1.4,
				boss.anchor_position.y + top_offset_y + math.random() * (bottom_offset_y - top_offset_y)
			),
			velocity = Vector2.new(math.cos(angle) * speed, math.sin(angle) * speed),
			size = BOSS_SHATTER_FRAGMENT_MIN_SIZE + math.random() * (BOSS_SHATTER_FRAGMENT_MAX_SIZE - BOSS_SHATTER_FRAGMENT_MIN_SIZE),
			rotation = math.random() * math.pi * 2.0,
			spin_speed = (math.random() - 0.5) * 2.0 * BOSS_SHATTER_FRAGMENT_SPIN_MAX,
			color = color,
			age = 0.0,
		})
	end
end

local function update_boss_shatter_particles(dt)
	for _, particle in ipairs(boss_shatter_particles) do
		particle.age = particle.age + dt
		particle.position = particle.position + particle.velocity * dt
		particle.rotation = particle.rotation + mathx.deg_to_rad(particle.spin_speed) * dt
	end
end

local function update_boss_death(dt)
	boss_death_timer = boss_death_timer - dt
	if not boss_shatter_triggered and boss_death_timer <= BOSS_SHATTER_TRIGGER_TIME then
		boss_shatter_triggered = true
		spawn_boss_shatter()
	end
	if not boss_shatter_triggered then
		boss_death_explosion_timer = boss_death_explosion_timer - dt
		if boss_death_explosion_timer <= 0.0 then
			boss_death_explosion_timer = BOSS_DEATH_EXPLOSION_INTERVAL
			local top_offset_y = BOSS_WEAK_POINT_OFFSETS[1].y
			local bottom_offset_y = BOSS_WEAK_POINT_OFFSETS[#BOSS_WEAK_POINT_OFFSETS].y
			local explosion_position = Vector2.new(
				boss.anchor_position.x + (math.random() - 0.5) * BOSS_HULL_HALF_WIDTH * 1.6,
				boss.anchor_position.y + top_offset_y + math.random() * (bottom_offset_y - top_offset_y)
			)
			-- Reuses charged_shot's own real "bazooka" impact style (a big,
			-- slow orange ring) — no need to invent a separate explosion look.
			table.insert(impacts, charged_shot.build_impact(explosion_position, "bazooka"))
		end
	else
		update_boss_shatter_particles(dt)
	end
	if boss_death_timer <= 0.0 then
		resolved = true
		resolve(true)
	end
end

local function update_contact_damage(dt)
	contact_invuln_timer = math.max(contact_invuln_timer - dt, 0.0)
	if contact_invuln_timer > 0.0 then
		return
	end
	for _, enemy in ipairs(enemies) do
		if enemy.kind ~= "shooter" and rects_overlap(player.ship.position, player.ship.half_extents, enemy.position, enemy.half_extents) then
			player_hit(CONTACT_DAMAGE)
			enemy.hp = 0.0 -- consumed next update_enemies() pass, same as a weapon kill
			return
		end
	end
	if boss then
		for _, weak_point in ipairs(boss.weak_points) do
			if weak_point.hp > 0.0 and rects_overlap(player.ship.position, player.ship.half_extents, weak_point.position, weak_point.half_extents) then
				player_hit(BOSS_CONTACT_DAMAGE)
				return
			end
		end
	end
end

-- Weapon-level shot pattern (see WEAPON_LEVEL_MAX's own doc comment): 0 =
-- one centered shot; 1 = two parallel shots; 2 = those two plus a pair
-- angled outward (top steers up, bottom steers down) for 4 total.
local function spawn_player_shots()
	local function fire_one(offset_y, angle_deg)
		table.insert(bullets, {
			position = player.ship.position + Vector2.new(0.0, offset_y),
			velocity = Vector2.new(PLAYER_SHOT_SPEED, 0.0):rotated(mathx.deg_to_rad(angle_deg)),
			damage = PLAYER_SHOT_DAMAGE,
			weapon_id = "machine_gun",
			is_player_shot = true,
		})
	end
	if player.weapon_level <= 0 then
		fire_one(0.0, 0.0)
		return
	end
	fire_one(-WEAPON_LEVEL_OFFSET_Y, 0.0)
	fire_one(WEAPON_LEVEL_OFFSET_Y, 0.0)
	if player.weapon_level >= 2 then
		fire_one(-WEAPON_LEVEL_OFFSET_Y, -WEAPON_LEVEL_SPREAD_DEG)
		fire_one(WEAPON_LEVEL_OFFSET_Y, WEAPON_LEVEL_SPREAD_DEG)
	end
end

-- Guards a staggered charged-shot burst's delayed callback against firing
-- after the level has already resolved (won/lost) and moved on.
local function level_still_active()
	return not resolved
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

function gradius.update(dt)
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

	-- 2026-09-19 bug found while wiring up the new per-character charged
	-- shot (which relies entirely on timer.after() for its staggered
	-- bursts): NOTHING was draining the shared timer.lua queue while this
	-- screen (or space_invaders.lua/breakout.lua) was active — only
	-- match_arena.lua ever called timer.update(). That means Space
	-- Invaders/Breakout's earlier "6 tirs d'affilee" charge burst has never
	-- actually fired more than its first shot in real play. Fixed here and
	-- in the other two screens.
	-- MUST run even after resolved=true: resolve() schedules the delayed
	-- switch_to(campaign_map) via timer.after(), and the early return below
	-- used to skip this line forever once resolved, permanently stranding
	-- the player on the win/loss screen with no way back to the map
	-- (2026-09-27 bug report: "je n'ai pas le bouton continuer").
	timer.update(dt)

	if resolved then
		return
	end

	-- 'K' instant-win cheat (edge-triggered) — Breakout/Space Invaders'
	-- LÖVE ports are missing this vs. their Godot originals; given to
	-- Gradius in both engines from day one instead of repeating that gap.
	local cheat_win_pressed = love.keyboard.isScancodeDown("k")
	if cheat_win_pressed and not cheat_win_prev then
		for _, enemy in ipairs(enemies) do
			enemy.hp = 0.0
		end
		if boss then
			for _, weak_point in ipairs(boss.weak_points) do
				weak_point.hp = 0.0
			end
		end
	end
	cheat_win_prev = cheat_win_pressed

	wave_time = wave_time + dt
	update_bullets(dt)
	update_impacts(dt)
	update_enemy_trails(dt)

	-- Player movement/fire — same controls as everywhere else in this
	-- port, but full arena freedom (see FULL_FREEDOM_FRONTIER_X above) and
	-- a simple uniform shot regardless of character (see header note).
	local move = Vector2.new(0.0, 0.0)
	if input.solo_right() then move.x = move.x + 1.0 end
	if input.solo_left() then move.x = move.x - 1.0 end
	if input.solo_down() then move.y = move.y + 1.0 end
	if input.solo_up() then move.y = move.y - 1.0 end
	-- Vif's charged-shot recoil kick (see charged_shot.lua's "recoil" spec)
	-- — decays linearly to 0 over recoil_decay_time; re-firing resets the
	-- window rather than stacking (vortex.lua's own real behavior).
	player.recoil_timer = math.max(player.recoil_timer - dt, 0.0)
	local recoil_boost = player.recoil_timer > 0.0 and player.recoil_peak * (player.recoil_timer / player.recoil_decay_time) or 0.0

	-- Normal fire stays the simple uniform shot (see spawn_player_shots'
	-- own header note) — only the CHARGED release differs per character now
	-- (Camil: "garder l'identite de chaque perso [...] se baser sur le tir
	-- charge"). Same hold-to-charge convention Space Invaders/Breakout use.
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
	player.ship = ship_state.update(
		player.ship, move, dt, ARENA_BOUNDS, FULL_FREEDOM_FRONTIER_X,
		charged_shot.charge_speed_multiplier(player.speed_multiplier + recoil_boost, is_charging)
	)

	player.fire_cooldown = math.max(player.fire_cooldown - dt, 0.0)
	if is_charging then
		-- normal fire suspended while actively charging (past the grace window)
	elseif firing and player.fire_cooldown <= 0.0 then
		player.fire_cooldown = 1.0 / PLAYER_FIRE_RATE
		spawn_player_shots()
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
		local lists = { enemies }
		if boss then
			table.insert(lists, boss.weak_points)
		end
		return lists
	end)

	update_enemies(dt)
	update_powerups(dt)
	if boss then
		if boss_dying then
			update_boss_death(dt)
		else
			update_boss(dt)
		end
	elseif enemies_cleared >= BOSS_SPAWN_THRESHOLD then
		spawn_boss()
	end
	update_contact_damage(dt)

	for layer = 1, #STARFIELD_LAYER_SPEEDS do
		local speed = STARFIELD_LAYER_SPEEDS[layer]
		for _, star in ipairs(starfield[layer]) do
			star.x = star.x - speed * dt
			if star.x < ARENA_BOUNDS.position.x then
				star.x = ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x
				star.y = ARENA_BOUNDS.position.y + math.random() * ARENA_BOUNDS.size.y
			end
		end
	end

	if player.ship.hp <= 0.0 then
		resolved = true
		resolve(false, "Vous avez ete detruit")
		return
	end
	if boss and not boss_dying then
		local boss_alive = false
		for _, weak_point in ipairs(boss.weak_points) do
			if weak_point.hp > 0.0 then
				boss_alive = true
				break
			end
		end
		if not boss_alive then
			boss_dying = true
			boss_death_timer = BOSS_DEATH_DURATION
			boss_death_explosion_timer = 0.0
			boss.lasers = {} -- cut short any laser still mid-telegraph/active at the moment of death
			message = ""
		end
	end
end

-- Real sprites (2026-09-20) — see ENEMY_SPRITE_BY_KIND's own doc comment.
local ENEMY_SPRITE_BY_KIND = {
	drone = assets.gradius_drone,
	waver = assets.gradius_waver,
	shooter = assets.gradius_shooter,
}
-- 2026-09-20 (Camil, after playtesting: "les drones sont orientes vers la
-- droite => il faut qu'ils soient vers la gauche") — the generated art is
-- already nose-left natively; no flip needed (an earlier assumption that
-- it needed flipping, matching the missile.png convention, was wrong for
-- this particular generation). The Shooter's art was also generated
-- facing left; the Waver has no strong directional nose either way.
local ENEMY_FLIP_H_BY_KIND = {}

-- Blinking pickups (Camil: "pour les bonus, tu peux les faire clignoter
-- (les 3)") — a smooth alpha pulse driven by the same wave_time every
-- other animation in this screen already uses, not a per-powerup timer.
-- 2026-09-20 (Camil, after playtesting: "le clignotement est bien mais
-- trop sombre") — was 0.45, a much gentler dip now.
local POWERUP_BLINK_PERIOD = 0.5
local POWERUP_BLINK_MIN_ALPHA = 0.75

function gradius.draw()
	love.graphics.setColor(0.03, 0.03, 0.08)
	love.graphics.rectangle("fill", ARENA_BOUNDS.position.x, ARENA_BOUNDS.position.y, ARENA_BOUNDS.size.x, ARENA_BOUNDS.size.y)

	for layer = 1, #STARFIELD_LAYER_SPEEDS do
		local brightness = 0.3 + 0.2 * layer
		local radius = 1.0 + layer * 0.5
		love.graphics.setColor(brightness, brightness, brightness + 0.05, 0.8)
		for _, star in ipairs(starfield[layer]) do
			love.graphics.circle("fill", star.x, star.y, radius)
		end
	end

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

	for _, particle in ipairs(enemy_trail_particles) do
		local t = particle.age / DRONE_TRAIL_DURATION
		love.graphics.setColor(DRONE_TRAIL_COLOR[1], DRONE_TRAIL_COLOR[2], DRONE_TRAIL_COLOR[3], 1.0 - t)
		love.graphics.circle("fill", particle.position.x, particle.position.y, mathx.lerp(4.0, 0.5, t))
	end

	for _, enemy in ipairs(enemies) do
		local flash = enemy.flash_timer > 0.0 and 1.6 or 1.0
		love.graphics.setColor(flash, flash, flash)
		draw_utils.draw_stretched(
			ENEMY_SPRITE_BY_KIND[enemy.kind],
			enemy.position.x, enemy.position.y,
			enemy.half_extents.x * 2.0, enemy.half_extents.y * 2.0,
			ENEMY_FLIP_H_BY_KIND[enemy.kind]
		)
	end

	local powerup_blink_alpha = mathx.lerp(
		POWERUP_BLINK_MIN_ALPHA, 1.0,
		0.5 + 0.5 * math.sin(wave_time * (2.0 * math.pi / POWERUP_BLINK_PERIOD))
	)
	for _, powerup in ipairs(powerups) do
		local image = assets.powerup_power
		if powerup.kind == "speed" then
			image = assets.powerup_speed
		elseif powerup.kind == "heart" then
			image = assets.powerup_heart
		end
		love.graphics.setColor(1.0, 1.0, 1.0, powerup_blink_alpha)
		draw_utils.draw_stretched(image, powerup.position.x, powerup.position.y, POWERUP_HALF_EXTENTS.x * 2.0, POWERUP_HALF_EXTENTS.y * 2.0)
	end

	if boss then
		if not boss_shatter_triggered then
			-- Hull backdrop, drawn BEHIND the weak points, spanning the
			-- formation's full vertical extent — see BOSS_HULL_*'s own doc
			-- comment (this is what actually reads as "one big ship" rather
			-- than several boxes floating in space).
			local top_offset_y = BOSS_WEAK_POINT_OFFSETS[1].y
			local bottom_offset_y = BOSS_WEAK_POINT_OFFSETS[#BOSS_WEAK_POINT_OFFSETS].y
			local hull_top = boss.anchor_position.y + top_offset_y - BOSS_HULL_PADDING_Y
			local hull_bottom = boss.anchor_position.y + bottom_offset_y + BOSS_HULL_PADDING_Y
			love.graphics.setColor(1.0, 1.0, 1.0)
			draw_utils.draw_stretched(
				assets.gradius_boss_hull,
				boss.anchor_position.x, (hull_top + hull_bottom) / 2.0,
				BOSS_HULL_HALF_WIDTH * 2.0, hull_bottom - hull_top
			)

			for _, weak_point in ipairs(boss.weak_points) do
				if weak_point.hp > 0.0 then
					local flash = weak_point.flash_timer > 0.0 and 1.6 or 1.0
					love.graphics.setColor(flash, flash, flash)
					draw_utils.draw_stretched(
						assets.gradius_boss_weakpoints[weak_point.sprite_variant],
						weak_point.position.x, weak_point.position.y,
						weak_point.half_extents.x * 2.0, weak_point.half_extents.y * 2.0
					)
				end
			end
		else
			-- "a la fin il faut que ce soit le sprite qui eclate" — the hull/
			-- weak-point sprites are gone entirely once triggered, replaced
			-- by tumbling fragments of the ship's own colors.
			for _, particle in ipairs(boss_shatter_particles) do
				local t = mathx.clampf(particle.age / BOSS_SHATTER_FRAGMENT_DURATION, 0.0, 1.0)
				local c = particle.color
				love.graphics.setColor(c[1], c[2], c[3], 1.0 - t)
				love.graphics.push()
				love.graphics.translate(particle.position.x, particle.position.y)
				love.graphics.rotate(particle.rotation)
				love.graphics.rectangle("fill", -particle.size / 2.0, -particle.size / 2.0, particle.size, particle.size)
				love.graphics.pop()
			end
		end
		for _, laser in ipairs(boss.lasers) do
			if laser.state == "telegraph" then
				local c = LASER_TELEGRAPH_COLOR
				love.graphics.setColor(c[1], c[2], c[3], c[4])
				love.graphics.setLineWidth(2.0)
				love.graphics.line(ARENA_BOUNDS.position.x, laser.y, ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x, laser.y)
				love.graphics.setLineWidth(1.0)
			else
				local c = LASER_ACTIVE_COLOR
				love.graphics.setColor(c[1], c[2], c[3], c[4])
				love.graphics.rectangle("fill", ARENA_BOUNDS.position.x, laser.y - LASER_THICKNESS / 2.0, ARENA_BOUNDS.size.x, LASER_THICKNESS)
			end
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
	end

	love.graphics.setLineWidth(2.0)
	for _, impact in ipairs(impacts) do
		charged_shot.draw_impact(impact)
	end
	love.graphics.setLineWidth(1.0)

	love.graphics.setColor(1, 1, 1)
	if boss then
		local alive_weak_points = 0
		for _, weak_point in ipairs(boss.weak_points) do
			if weak_point.hp > 0.0 then
				alive_weak_points = alive_weak_points + 1
			end
		end
		love.graphics.print(string.format("%s   Tourelles du boss restantes : %d", player.character.display_name, alive_weak_points), 40, 24)
	else
		love.graphics.print(string.format("%s   Progression avant le boss : %d/%d", player.character.display_name, math.min(enemies_cleared, BOSS_SPAWN_THRESHOLD), BOSS_SPAWN_THRESHOLD), 40, 24)
	end
	-- Classic continuous HP bar (Camil: "on va revenir sur la barre de vie
	-- classique") — same look as Breakout/Space Invaders' own.
	love.graphics.setColor(0.15, 0.15, 0.18)
	love.graphics.rectangle("fill", 40, 44, 240, 10)
	love.graphics.setColor(0.3, 0.9, 0.4)
	love.graphics.rectangle("fill", 40, 44, 240 * mathx.clampf(player.ship.hp / ship_state.START_HP, 0.0, 1.0), 10)

	-- Weapon level — one square per WEAPON_LEVEL_MAX+1 step, same orange as
	-- the "P" powerup that fills them.
	for i = 0, WEAPON_LEVEL_MAX do
		local x = 40 + i * 26
		if i <= player.weapon_level then
			love.graphics.setColor(POWERUP_WEAPON_COLOR[1], POWERUP_WEAPON_COLOR[2], POWERUP_WEAPON_COLOR[3])
			love.graphics.rectangle("fill", x, 66, 20, 14)
		else
			love.graphics.setColor(0.2, 0.2, 0.24)
			love.graphics.rectangle("fill", x, 66, 20, 14)
		end
		love.graphics.setColor(1.0, 1.0, 1.0, 0.5)
		love.graphics.rectangle("line", x, 66, 20, 14)
	end

	love.graphics.setColor(POWERUP_WEAPON_COLOR[1], POWERUP_WEAPON_COLOR[2], POWERUP_WEAPON_COLOR[3])
	love.graphics.print(string.format("Tir niveau %d/%d", player.weapon_level, WEAPON_LEVEL_MAX), 40, 88)
	love.graphics.setColor(POWERUP_SPEED_COLOR[1], POWERUP_SPEED_COLOR[2], POWERUP_SPEED_COLOR[3])
	love.graphics.print(string.format("Vitesse x%.2f", player.speed_multiplier), 180, 88)

	if message ~= "" then
		love.graphics.setColor(1, 1, 1)
		love.graphics.printf(message, ARENA_BOUNDS.position.x, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0 - 10, ARENA_BOUNDS.size.x, "center")
	end

	love.graphics.setColor(0.65, 0.65, 0.7)
	love.graphics.printf("ZQSD : deplacer — Espace : tirer (maintenir = attaque speciale) — Echap : abandonner", 0, 20, 1280, "center")
end

return gradius
