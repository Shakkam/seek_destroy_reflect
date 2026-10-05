local Vector2 = require("simulation.vector2")
local mathx = require("simulation.mathx")
local timer = require("timer")
local assets = require("assets")
local draw_utils = require("draw_utils")

-- Shared per-character "charged shot" special attack, used by all three
-- mini-jeu screens (gradius.lua, space_invaders.lua, breakout.lua).
--
-- 2026-09-19 (Camil: "j'aime bien l'idee de garder quand meme l'identite de
-- chaque perso [...] se baser sur le tir charge") — these three mini-jeux
-- had all converged on ONE uniform simple shot for every character (see
-- each screen's own header note on why: Controleur's turret kit never
-- fired, Lourd's bazooka felt too slow, etc.). The NORMAL (uncharged) shot
-- stays that same simple uniform machine_gun-style shot everywhere — this
-- module only replaces what happens on a charge RELEASE, giving every
-- character back a distinct, recognizable special move without
-- reintroducing the old per-character normal-fire problems.
--
-- Numbers either come straight from the character's real combat weapon
-- (data/weapons/*.lua) when Camil said "meme chose qu'en versus" (Spreader,
-- Traqueur), or are bespoke ones he specified directly (Lourd, Mitrailleur,
-- Vif, Perturbateur) — explicitly NOT the same as that weapon's own
-- charged-fire numbers in a real match. Controleur and Zoneur reuse real
-- weapon behavior too (a real turret's charged form; a real laser's NORMAL
-- form respectively).
local charged_shot = {}

local BASE_SHOT_SPEED = 700.0 -- matches every mini-jeu's own PLAYER_SHOT_SPEED

-- 2026-09-20 (Camil, after playtesting: "il faut que ce soit exactement le
-- meme qu'ingame [...] ne reinventons pas la roue [...] le meme algo") —
-- real per-weapon numbers pulled straight from match_arena.lua's own
-- BULLET_VISUALS/TURRET/BEAM tables and spawn_projectile()/spawn_turret(),
-- not approximated. Kept here (not re-derived from data/weapons/*.lua's
-- own fields) because match_arena.lua itself hand-picks these scale/size
-- values independently of WeaponData — see BULLET_VISUALS' own doc
-- comment there ("radius still drives nothing [...] the real draw uses
-- assets.bullets + scale").
-- 2026-10-05 "tout plus gros" pass: x1.5, matching match_arena.lua's own
-- BULLET_VISUALS bump (same reasoning — see that file's doc comment).
local REAL_BULLET_SCALE = {
	bazooka = 1.4 * 1.5,
	stun_boomerang = 1.4 * 1.5,
	homing_missile = 0.8 * 1.5,
	vortex = 2.4 * 1.5,
	mini_shot = 1.0 * 1.5,
}
local VORTEX_WEAPON_FRAME_DURATION = 0.12 -- match_arena.lua's own constant
local TURRET_HALF_EXTENTS = 15.0 -- match_arena.lua's TURRET.HALF_EXTENTS (drawn stretched to half_extents*2, not scaled like a bullet)
local TURRET_SHOT_SPEED = 480.0 -- match_arena.lua's TURRET.SHOT_SPEED
-- 2026-09-20 (Camil, after playtesting: "les tirs de controleur sont trop
-- gros => 70% de leur taille actuelle serait parfait") — the turret's
-- bullets have no dedicated BULLET_VISUALS entry in any of the 3 mini-jeu
-- screens, so they were falling back to machine_gun's own 1.4 scale.
local TURRET_BULLET_SCALE = 1.4 * 0.7 * 1.5 -- 2026-10-05 "tout plus gros" pass
local BEAM_BASE_THICKNESS = 6.0 -- match_arena.lua's BEAM.BASE_THICKNESS
local BEAM_TICK_INTERVAL = 0.1 -- match_arena.lua's BEAM.TICK_INTERVAL
local BEAM_FADE_DURATION = 0.08 -- match_arena.lua's BEAM.FADE_DURATION
local BEAM_COLOR = { 0.4, 1.0, 0.5 } -- match_arena.lua's real beam draw color

-- 2026-09-20 (Camil: "il faut bien penser aussi aux effets de contact des
-- armes, comme en vs. Lourd => ca fait une explosion. [...] le boomerang se
-- dechiquette (comme en VS)") — match_arena.lua's real per-weapon impact
-- styles (IMPACT_STYLE_BY_WEAPON/spawn_impact/its own draw loop), reused
-- verbatim rather than every mini-jeu's own generic spark_ring-only impact.
-- weapon ids not listed here (machine_gun, and anything unknown) fall back
-- to spark_ring, same as the real game.
charged_shot.IMPACT_STYLE_BY_WEAPON = {
	bazooka = "big_explosion",
	mini_shot = "fan_shatter", -- "l'eventail se decompose... comme un petit feu d'artifice"
	stun_boomerang = "saber_slash", -- "une ligne tres rapide et courte... comme un coup de sabre"
	vortex = "vortex_split", -- "le tourbillon se divise en huit et s'eclate dans les 8 directions en fadant"
	turret = "spark_ring",
	homing_missile = "spark_ring",
}
local RING_IMPACT_PARAMS = {
	spark_ring = { duration = 0.15, radius = 14.0, color = { 1.0, 0.9, 0.5 } },
	big_explosion = { duration = 0.3, radius = 32.0, color = { 1.0, 0.55, 0.2 } },
}

-- Builds one impact entry, ready to insert into the screen's own `impacts`
-- list — same shapes/durations/particle counts as match_arena.lua's real
-- spawn_impact(). `target_half_extents` (only used by saber_slash, which
-- draws its flash across the HIT TARGET's own bounding box) defaults to a
-- generic small enemy's size when not given.
function charged_shot.build_impact(position, weapon_id, target_half_extents)
	local style = charged_shot.IMPACT_STYLE_BY_WEAPON[weapon_id] or "spark_ring"
	local impact = { position = position, age = 0.0, style = style }
	if style == "fan_shatter" then
		impact.duration = 0.25
		impact.particles = {}
		for _ = 1, 6 do
			local angle = math.random() * math.pi * 2.0
			local speed = 60.0 + math.random() * 80.0
			table.insert(impact.particles, Vector2.new(math.cos(angle) * speed, math.sin(angle) * speed))
		end
	elseif style == "saber_slash" then
		impact.duration = 0.15
		impact.half_extents = target_half_extents or Vector2.new(16.0, 16.0)
	elseif style == "vortex_split" then
		impact.duration = 0.25
		impact.particles = {}
		for i = 0, 7 do
			local angle = mathx.deg_to_rad(45.0 * i)
			table.insert(impact.particles, Vector2.new(math.cos(angle) * 90.0, math.sin(angle) * 90.0))
		end
	else
		local params = RING_IMPACT_PARAMS[style] or RING_IMPACT_PARAMS.spark_ring
		impact.duration = params.duration
		impact.radius = params.radius
		impact.color = params.color
	end
	return impact
end

-- Draws one impact built by build_impact() — same visual per style as
-- match_arena.lua's real draw loop.
function charged_shot.draw_impact(impact)
	local t = impact.age / impact.duration
	if impact.style == "fan_shatter" then
		for _, vel in ipairs(impact.particles) do
			local p = impact.position + vel * impact.age
			love.graphics.setColor(1.0, 1.0 - 0.5 * t, 0.4 + 0.4 * t, 1.0 - t)
			love.graphics.rectangle("fill", p.x - 2.0, p.y - 2.0, 4.0, 4.0)
		end
	elseif impact.style == "vortex_split" then
		for _, vel in ipairs(impact.particles) do
			local p = impact.position + vel * impact.age
			love.graphics.setColor(0.7, 0.9, 1.0, 1.0 - t)
			love.graphics.circle("fill", p.x, p.y, 3.0)
		end
	elseif impact.style == "saber_slash" then
		love.graphics.setColor(0.6, 0.85, 1.0, 1.0 - t)
		love.graphics.setLineWidth(4.0)
		love.graphics.line(
			impact.position.x - impact.half_extents.x, impact.position.y - impact.half_extents.y,
			impact.position.x + impact.half_extents.x, impact.position.y + impact.half_extents.y
		)
		love.graphics.setLineWidth(1.0)
	else
		local c = impact.color
		love.graphics.setColor(c[1], c[2], c[3], 1.0 - t)
		love.graphics.circle("line", impact.position.x, impact.position.y, impact.radius * t)
	end
end

-- 2026-09-19 (Camil: "il faudrait le meme comportement : quand ca charge le
-- vaisseau ralentit, quand le tir charge est pret, il clignote") — matches
-- match_arena.lua's own real charge-fire feel (SHIP_FEEL's charge tint/
-- CHARGE_READY_BLINK_PERIOD and every weapon's own charge_fire_slow_
-- multiplier, which is 0.3 across every single weapon file, hence a flat
-- shared constant rather than a per-character one here).
local CHARGE_SLOW_MULTIPLIER = 0.3
local CHARGE_READY_BLINK_PERIOD = 0.15

-- The ship's own move-speed multiplier while charging: clamps DOWN to
-- CHARGE_SLOW_MULTIPLIER, same as match_arena.lua's own
-- `math.min(speed_multiplier, weapon.charge_fire_slow_multiplier)` — call
-- with the screen's own base multiplier (1.0, or player.speed_multiplier
-- plus any recoil boost) and whether the ship is actively charging.
function charged_shot.charge_speed_multiplier(base_multiplier, is_charging)
	if is_charging then
		return math.min(base_multiplier, CHARGE_SLOW_MULTIPLIER)
	end
	return base_multiplier
end

-- The ship sprite's tint while charging: builds from white toward
-- orange-red as the charge fills, then blinks between an overbright flash
-- and deep orange-red once fully charged and ready to release — same
-- progression as match_arena.lua's own real charge-fire ship tint. Returns
-- 1.0, 1.0, 1.0 (no tint) outside the charge window.
function charged_shot.charge_tint(fire_held_duration, grace, duration)
	if fire_held_duration <= grace then
		return 1.0, 1.0, 1.0
	end
	local charge_time = fire_held_duration - grace
	if charge_time >= duration then
		local blink_on = math.fmod(fire_held_duration, CHARGE_READY_BLINK_PERIOD) < CHARGE_READY_BLINK_PERIOD / 2.0
		if blink_on then
			return 1.7, 1.7, 1.7
		end
		return 1.0, 0.35, 0.1
	end
	local t = mathx.clampf(charge_time / duration, 0.0, 1.0)
	return 1.0, mathx.lerp(1.0, 0.35, t), mathx.lerp(1.0, 0.1, t)
end

local PLANS = {
	-- "Lourd => envoi 4 scuds de lourd avec intervalle de 1/3s entre chaque scud"
	lourd = {
		kind = "burst",
		bullets = { count = 4, stagger = 1.0 / 3.0, weapon_id = "bazooka", damage = 10.0, homing_strength = 1.8, visual_scale = REAL_BULLET_SCALE.bazooka },
	},
	-- "Mitrailleur => envoie une salve de 10 tirs rapides"
	mitrailleur = {
		kind = "burst",
		bullets = { count = 10, stagger = 0.06, weapon_id = "machine_gun", damage = 2.0 },
	},
	-- "Vif => envoie 5 tourbillons + petite acceleration (comme en versus)"
	-- — the acceleration is vortex.lua's own real recoil kick (fire_recoil_
	-- speed_boost/fire_recoil_boost_decay_time), reused verbatim. 2026-09-20
	-- (Camil, after playtesting: "c'est pas le bon tir [...] il faut que ce
	-- soit exactement le meme qu'ingame en mode charge (taille, mouvement
	-- sinusoidal etc)") — is_sine/sine_amplitude/sine_angular_speed, the
	-- real 2.4 scale, and the wind1/wind3 flipbook (spawn_one's own
	-- weapon_id=="vortex" special case below) are ALL vortex.lua's/
	-- spawn_projectile()'s real values — no charged-only override exists
	-- for any of them in the real weapon data, so normal and charged
	-- Tourbillon bullets are visually and physically identical.
	vif = {
		kind = "burst",
		bullets = { count = 5, stagger = 0.1, weapon_id = "vortex", damage = 3.0, visual_scale = REAL_BULLET_SCALE.vortex, is_sine = true, sine_amplitude = 20.0, sine_angular_speed = 720.0 },
		recoil = { speed_boost = 0.6, decay_time = 0.5 },
	},
	-- "Controleur => pose une tourelle a tir rapide qui dure 5 secondes" —
	-- turret.lua's own real charged-fire numbers (4x fire rate, 5s instead
	-- of its normal ~19s lifetime).
	controleur = {
		kind = "turret",
		turret = { fire_rate = 1.5 * 4.0, lifetime = 5.0, damage = 3.0 },
	},
	-- "Spreader => meme chose que tir charge en versus [...] ne reinventons
	-- pas la roue [...] les eventails tournent et font la meme taille" —
	-- mini_shot.lua's own charged_* fields (a wide ping-pong fan) plus its
	-- real projectile_spin_speed (900 deg/s — WeaponData.projectile_spin_
	-- speed, read by spawn_one's spin_speed field below) and real 1.0 scale.
	mini = {
		kind = "burst",
		bullets = { count = 10, stagger = 0.125, weapon_id = "mini_shot", damage = 3.0, visual_scale = REAL_BULLET_SCALE.mini_shot, spin_speed = 900.0, fan_spread_deg = 60.0, ping_pong = true },
	},
	-- "Zoneur => 1 laser normal (comme son tir normal en versus) [...] doit
	-- etre exactement le meme que le laser simple de zoneur en vs" —
	-- laser.lua's own NORMAL (not charged) beam_duration/damage; see
	-- charged_shot.fire()'s "laser" branch and update_lasers()/draw_lasers()
	-- for the rest of the real BEAM_* fidelity (thickness, tick rate,
	-- following the shooter live, fade in/out).
	zoneur = {
		kind = "laser",
		laser = { duration = 0.5, damage_per_second = 20.0 },
	},
	-- "Perturbateur => envoie une salve de 5 boomerangs (au lieu de 3 en
	-- tir normal en versus)" — stun_boomerang.lua's own normal per-shot
	-- damage/spread/spin/scale, just 5 instead of 3. boomerang_out_duration
	-- is NOT reused verbatim (2.0s at 620px/s, ~1240px, is tuned for a
	-- versus arena noticeably wider than these mini-jeux' own 1200px-wide
	-- ARENA_BOUNDS) — shortened so it reliably turns around before leaving
	-- the arena, but per Camil's 2026-09-20 playtest ("les boomerangs ne
	-- vont pas assez loin") given more reach than the first pass.
	perturbateur = {
		kind = "burst",
		bullets = {
			count = 5, stagger = 0.08, weapon_id = "stun_boomerang", damage = 1.5, visual_scale = REAL_BULLET_SCALE.stun_boomerang,
			fan_spread_deg = 24.0, is_boomerang = true, boomerang_out_duration = 1.3, spin_speed = 720.0,
		},
	},
	-- "Traqueur => meme chose que tir charge en versus" —
	-- homing_missile.lua's own charged_* fields (a 6-missile rafale) and
	-- real 0.8 scale.
	missiles = {
		kind = "burst",
		bullets = { count = 6, stagger = 0.12, weapon_id = "homing_missile", damage = 3.0, visual_scale = REAL_BULLET_SCALE.homing_missile, homing_strength = 1.6, speed_multiplier = 1.15, fan_spread_deg = 50.0 },
	},
}

function charged_shot.plan_for(character_id)
	return PLANS[character_id] or PLANS.mitrailleur
end

-- Evenly spaced angles across [-spread/2, +spread/2], in a ping-pong order
-- (0 -> +spread/2 -> -spread/2, roughly) when requested — mini_shot's own
-- "charged_burst_ping_pong: true" sweep shape — else a plain linear sweep
-- from -spread/2 to +spread/2.
local function fan_angle_deg(spec, i)
	local count = spec.count
	if not spec.fan_spread_deg or count <= 1 then
		return 0.0
	end
	local spread = spec.fan_spread_deg
	if spec.ping_pong then
		local half = (count - 1) / 2.0
		local t = i <= half and (i / half) or ((count - 1 - i) / half)
		return -spread / 2.0 + spread * t
	end
	return -spread / 2.0 + spread * (i / (count - 1))
end

-- ctx = {
--   get_position = function() -> Vector2, the player's CURRENT position —
--     called fresh at the moment each shot actually fires, not once
--     up front, so a staggered burst's later shots track a moving ship
--     instead of freezing at wherever it was on charge-release (Camil:
--     "le tir charge marche, mais part toujours du meme point [...]
--     plutot que de partir du vaisseau"),
--   spawn_bullet = function(fields) -- inserts into the screen's own bullets list,
--   spawn_turret = function(turret_spec) -- inserts into the screen's own turrets list,
--   spawn_laser = function(laser_spec) -- inserts into the screen's own lasers list,
--   apply_recoil = function(speed_boost, decay_time) -- Vif only,
--   still_active = function() -> bool, guards staggered timer callbacks against firing post-resolution,
-- }
function charged_shot.fire(character_id, ctx)
	local plan = charged_shot.plan_for(character_id)

	if plan.kind == "turret" then
		ctx.spawn_turret({
			position = ctx.get_position(),
			half_extents = TURRET_HALF_EXTENTS,
			fire_rate = plan.turret.fire_rate,
			fire_cooldown = 0.0,
			lifetime = plan.turret.lifetime,
			damage = plan.turret.damage,
		})
		return
	end

	if plan.kind == "laser" then
		-- "doit etre exactement le meme que le laser simple de zoneur en vs"
		-- — match_arena.lua's real beam FOLLOWS its shooter every frame
		-- (never a frozen origin), so this stores the same LIVE position
		-- getter rather than a snapshot; see update_lasers()/draw_lasers().
		ctx.spawn_laser({
			get_origin = ctx.get_position,
			timer = plan.laser.duration,
			elapsed = 0.0,
			hit_timer = 0.0,
			damage_per_second = plan.laser.damage_per_second,
		})
		return
	end

	-- "burst"
	local spec = plan.bullets
	if plan.recoil and ctx.apply_recoil then
		ctx.apply_recoil(plan.recoil.speed_boost, plan.recoil.decay_time)
	end
	local speed = BASE_SHOT_SPEED * (spec.speed_multiplier or 1.0)
	local function spawn_one(i)
		local angle_deg = fan_angle_deg(spec, i)
		local velocity = Vector2.new(speed, 0.0):rotated(mathx.deg_to_rad(angle_deg))
		local fields = {
			position = ctx.get_position(),
			velocity = velocity,
			damage = spec.damage,
			weapon_id = spec.weapon_id,
			-- NOT is_homing_toward_player (that flag is enemy-bullets-only,
			-- steering toward the player) — a player shot with a
			-- homing_strength instead homes toward the nearest enemy, see
			-- update_homing_bullet() below (Lourd/Traqueur only).
			homing_strength = spec.homing_strength,
			visual_scale = spec.visual_scale,
			is_boomerang = spec.is_boomerang or false,
			boomerang_out_duration = spec.boomerang_out_duration,
			boomerang_timer = 0.0,
			boomerang_returning = false,
			spin_speed = spec.spin_speed or 0.0,
			rotation = 0.0,
			-- Vif's Tourbillon (see update_sine_bullet()) — the base velocity
			-- IS the captured drift, exactly as match_arena.lua's own
			-- spawn_projectile() does it.
			is_sine = spec.is_sine or false,
			drift_velocity = velocity,
			sine_elapsed = 0.0,
			sine_amplitude = spec.sine_amplitude,
			sine_angular_speed = spec.sine_angular_speed,
		}
		if spec.weapon_id == "vortex" then
			-- match_arena.lua's own spawn_projectile(): every vortex bullet
			-- (normal or charged) gets the wind1/wind3 flipbook, ticked by
			-- each screen's own generic anim_textures mechanism.
			fields.anim_textures = assets.vortex_weapon_frames
			fields.anim_frame_index = 1
			fields.anim_frame_timer = VORTEX_WEAPON_FRAME_DURATION
			fields.anim_frame_duration = VORTEX_WEAPON_FRAME_DURATION
		end
		ctx.spawn_bullet(fields)
	end
	for i = 0, spec.count - 1 do
		if i == 0 then
			spawn_one(i)
		else
			timer.after(i * spec.stagger, function()
				if ctx.still_active() then
					spawn_one(i)
				end
			end)
		end
	end
end

-- Shared per-frame boomerang physics: flies straight out for
-- boomerang_out_duration, then reverses direction (a straight return leg
-- rather than a full curve back to the player, kept intentionally simple)
-- for the same duration again, spinning throughout. Call once per bullet
-- per frame from the screen's own update_bullets loop, BEFORE the normal
-- `bullet.position = bullet.position + bullet.velocity * dt` step.
function charged_shot.update_boomerang_bullet(bullet, dt)
	bullet.boomerang_timer = bullet.boomerang_timer + dt
	if not bullet.boomerang_returning and bullet.boomerang_timer >= bullet.boomerang_out_duration then
		bullet.boomerang_returning = true
		bullet.velocity = -bullet.velocity
	end
end

-- Generic projectile self-spin (WeaponData.projectile_spin_speed —
-- mini_shot/stun_boomerang) — 2026-09-20 (Camil: "tu as oublie la rotation
-- sur les tirs charges de spreader") — match_arena.lua ticks this
-- UNCONDITIONALLY for every bullet with a nonzero spin_speed, not just
-- boomerangs (spin and the boomerang out-and-back physics are two
-- independent things — mini_shot spins but never boomerangs). Call once
-- per bullet per frame for any bullet with a nonzero `spin_speed`.
function charged_shot.update_spin_bullet(bullet, dt)
	bullet.rotation = bullet.rotation + mathx.deg_to_rad(bullet.spin_speed) * dt
end

-- Steers a player shot with a `homing_strength` (Lourd's scuds, Traqueur's
-- missiles) toward a LOCKED target — Camil: "les missiles sont a tete
-- chercheuse : ils doivent prendre une cible... pour cible", i.e. pick one
-- target and pursue THAT one, not whichever obstacle happens to be nearest
-- on any given frame (which reads as erratic, flip-flopping "homing" when
-- several enemies are around). The lock happens lazily on this bullet's
-- first update (nearest living target across `target_lists`, each a list
-- of {position, half_extents, hp} obstacles, e.g. a screen's own
-- `enemies`/`boss.weak_points`/`formation`/`bricks`); if that target dies
-- before impact, the missile goes ballistic on its last heading rather than
-- re-locking onto a new one. Only the vertical speed steers, same
-- convention as every enemy-bullet homing branch in this codebase, so it
-- can never turn fully around. Call once per bullet per frame from the
-- screen's own update_bullets loop, before the normal position-integration
-- step.
function charged_shot.update_homing_bullet(bullet, dt, target_lists)
	if not bullet.homing_strength or bullet.homing_strength <= 0.0 then
		return
	end
	if bullet.homing_target and not (bullet.homing_target.hp and bullet.homing_target.hp > 0.0) then
		return -- locked target died mid-flight — stay on the last heading, don't re-lock
	end
	if not bullet.homing_target then
		local target, best_dist = nil, math.huge
		for _, list in ipairs(target_lists) do
			for _, obstacle in ipairs(list) do
				if obstacle.hp and obstacle.hp > 0.0 then
					local dist = bullet.position:distance_to(obstacle.position)
					if dist < best_dist then
						best_dist = dist
						target = obstacle
					end
				end
			end
		end
		if not target then
			return
		end
		bullet.homing_target = target
	end
	local target = bullet.homing_target
	local desired_vy = mathx.clampf((target.position.y - bullet.position.y) * 2.0, -260.0, 260.0)
	bullet.velocity = Vector2.new(bullet.velocity.x, mathx.lerp(bullet.velocity.y, desired_vy, mathx.clampf(bullet.homing_strength * dt, 0.0, 1.0)))
end

-- Generic sprite flipbook tick (Vif's wind1/wind3 vortex cycle) — same
-- mechanism match_arena.lua's own update_bullets() uses. Call once per
-- bullet per frame for any bullet with `anim_textures` set; the screen's
-- own draw loop then picks `bullet.anim_textures[bullet.anim_frame_index]`
-- instead of its usual static `assets.bullets[weapon_id]` lookup.
function charged_shot.update_anim_bullet(bullet, dt)
	bullet.anim_frame_timer = bullet.anim_frame_timer - dt
	if bullet.anim_frame_timer <= 0.0 then
		bullet.anim_frame_timer = bullet.anim_frame_duration
		bullet.anim_frame_index = (bullet.anim_frame_index % #bullet.anim_textures) + 1
	end
end

-- Shared per-frame sine-wave motion for Vif's Tourbillon (is_sine): a
-- straight-line net drift (the velocity captured at spawn) with a lateral
-- wave riding on top — exactly match_arena.lua's own real-weapon formula,
-- so the charged shot's bullets move identically to the normal ones.
function charged_shot.update_sine_bullet(bullet, dt)
	bullet.sine_elapsed = bullet.sine_elapsed + dt
	local wave_angle = mathx.deg_to_rad(bullet.sine_angular_speed) * bullet.sine_elapsed
	local drift_dir = bullet.drift_velocity:normalized()
	local perp = Vector2.new(-drift_dir.y, drift_dir.x)
	local lateral_speed = bullet.sine_amplitude * mathx.deg_to_rad(bullet.sine_angular_speed) * math.cos(wave_angle)
	bullet.velocity = bullet.drift_velocity + perp * lateral_speed
end

-- Generic placed-turret update: fires straight along +X at `fire_rate`,
-- at the real turret's own TURRET_SHOT_SPEED (480, not the mini-jeu's own
-- faster player shot speed), for `lifetime` seconds, then expires.
-- `spawn_bullet` is the same screen-provided callback used by
-- charged_shot.fire()'s bursts.
function charged_shot.update_turrets(turrets, dt, spawn_bullet)
	local i = 1
	while i <= #turrets do
		local turret = turrets[i]
		turret.lifetime = turret.lifetime - dt
		if turret.lifetime <= 0.0 then
			table.remove(turrets, i)
		else
			turret.fire_cooldown = turret.fire_cooldown - dt
			if turret.fire_cooldown <= 0.0 then
				turret.fire_cooldown = 1.0 / turret.fire_rate
				spawn_bullet({
					position = turret.position,
					velocity = Vector2.new(TURRET_SHOT_SPEED, 0.0),
					damage = turret.damage,
					weapon_id = "turret",
					visual_scale = TURRET_BULLET_SCALE,
					rotation = 0.0,
				})
			end
			i = i + 1
		end
	end
end

-- `get_target_lists()` returns a fresh array of obstacle lists (each entry
-- with .position/.half_extents/.hp) to damage — called each update since a
-- mini-jeu's target lists (e.g. Gradius's boss weak points) can appear or
-- disappear while a laser is still ticking. Matches match_arena.lua's real
-- beam exactly: origin (both x AND y) is read live from `get_origin()`
-- every tick — "never a frozen origin" — damage ticks every
-- BEAM_TICK_INTERVAL (not smoothly every frame), and the y-alignment test
-- is the same `< obstacle.half_extents.y + thickness` formula (not halved).
function charged_shot.update_lasers(lasers, dt, get_target_lists)
	local i = 1
	while i <= #lasers do
		local laser = lasers[i]
		laser.elapsed = laser.elapsed + dt
		if laser.elapsed >= laser.timer then
			table.remove(lasers, i)
		else
			laser.hit_timer = laser.hit_timer - dt
			if laser.hit_timer <= 0.0 then
				laser.hit_timer = BEAM_TICK_INTERVAL
				local origin = laser.get_origin()
				local tick_damage = laser.damage_per_second * BEAM_TICK_INTERVAL
				for _, list in ipairs(get_target_lists()) do
					for _, obstacle in ipairs(list) do
						if obstacle.hp and obstacle.hp > 0.0 and obstacle.position.x > origin.x
							and math.abs(obstacle.position.y - origin.y) < obstacle.half_extents.y + BEAM_BASE_THICKNESS then
							obstacle.hp = obstacle.hp - tick_damage
						end
					end
				end
			end
			i = i + 1
		end
	end
end

function charged_shot.draw_turrets(turrets)
	for _, turret in ipairs(turrets) do
		love.graphics.setColor(1, 1, 1)
		draw_utils.draw_stretched(assets.turret_charged, turret.position.x, turret.position.y, turret.half_extents * 2.0, turret.half_extents * 2.0)
	end
end

-- "Une barre translucide du tireur jusqu'au mur de l'arene, avec un fade in/
-- out rapide aux deux bouts" — match_arena.lua's own real beam draw,
-- including its exact color, following the shooter's LIVE position (both
-- axes) every frame rather than a frozen cast-time snapshot.
function charged_shot.draw_lasers(lasers, arena_bounds)
	for _, laser in ipairs(lasers) do
		local origin = laser.get_origin()
		local far_x = arena_bounds.position.x + arena_bounds.size.x
		local length = far_x - origin.x
		local alpha = 1.0
		if laser.elapsed < BEAM_FADE_DURATION then
			alpha = laser.elapsed / BEAM_FADE_DURATION
		elseif laser.elapsed > laser.timer - BEAM_FADE_DURATION then
			alpha = mathx.clampf((laser.timer - laser.elapsed) / BEAM_FADE_DURATION, 0.0, 1.0)
		end
		love.graphics.setColor(BEAM_COLOR[1], BEAM_COLOR[2], BEAM_COLOR[3], 0.7 * alpha)
		love.graphics.rectangle("fill", origin.x, origin.y - BEAM_BASE_THICKNESS / 2.0, length, BEAM_BASE_THICKNESS)
	end
end

return charged_shot
