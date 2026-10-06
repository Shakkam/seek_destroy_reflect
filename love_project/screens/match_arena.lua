local input = require("input")
local Vector2 = require("simulation.vector2")
local Rect2 = require("simulation.rect2")
local mathx = require("simulation.mathx")
local ball_state = require("simulation.ball_state")
local ship_state = require("simulation.ship_state")
local match_state = require("simulation.match_state")
local weapon_system_state = require("simulation.weapon_system_state")
local mitrailleur = require("data.characters.mitrailleur")
local match_setup = require("match_setup")
local campaign_context = require("campaign.campaign_context")
local campaign_save = require("campaign.campaign_save")
local timer = require("timer")
local assets = require("assets")
local draw_utils = require("draw_utils")
local bullet_fx = require("bullet_fx")
local fonts = require("fonts")
local ULTRA_LA_MEUTE = require("data.weapons.ultra_la_meute")
local ULTRA_PLUIE_DE_BONBONS = require("data.weapons.ultra_pluie_de_bonbons")
local ULTRA_MITRAILLEUSES_SATELLITES = require("data.weapons.ultra_mitrailleuses_satellites")

-- Epic 4 reward system (2026-08-16): the 8 base kit weapons, keyed by
-- WeaponData.id, the exact string CampaignSave.unlocks_for(character_id)
-- stores (RivalEncounterData.unlock_reward is set to the defeated rival's
-- own weapon resource, recorded by its `.id` in _resolve_campaign_result()).
-- Used to resolve an unlocked id back into the real resource (with its
-- passive_interval) when wiring up passive rewards for a ship.
local BASE_WEAPONS_BY_ID = {
	bazooka = require("data.weapons.bazooka"),
	turret = require("data.weapons.turret"),
	machine_gun = require("data.weapons.machine_gun"),
	vortex = require("data.weapons.vortex"),
	laser = require("data.weapons.laser"),
	stun_boomerang = require("data.weapons.stun_boomerang"),
	homing_missile = require("data.weapons.homing_missile"),
	mini_shot = require("data.weapons.mini_shot"),
}

-- Epic boss (2026-09-05, match_arena_node.gd's _setup_boss_ship()/
-- _process_boss_phases()) — every boss-only piece, state AND functions
-- alike, lives on this ONE table's fields/methods rather than as separate
-- top-level locals (the 200-local ceiling, same reason as UT/
-- ultra_helpers). Filled in progressively through this file, same
-- convention as ultra_helpers.
local boss_helpers = {
	-- .phase (1/2/3) and .message/.message_timer are match-orchestration
	-- state, not per-ship — mirrors match_arena_node.gd's own _boss_phase
	-- local (a single int, not a ShipNode field) for the same reason: there
	-- is only ever one boss (ship_2/players[2]) per encounter.
	phase = 1,
	message = "",
	message_timer = 0.0,

	-- Camil: "gros, imposant, qu'il ait toutes les armes" — match_arena_
	-- node.gd's BOSS_FULL_KIT_PATHS, same 8 weapons (every base kit weapon
	-- in the game) replacing the organizer's normal single-character kit
	-- for the whole fight. Order matches Godot's own list.
	FULL_KIT = {
		BASE_WEAPONS_BY_ID.machine_gun, BASE_WEAPONS_BY_ID.bazooka,
		BASE_WEAPONS_BY_ID.laser, BASE_WEAPONS_BY_ID.turret,
		BASE_WEAPONS_BY_ID.vortex, BASE_WEAPONS_BY_ID.mini_shot,
		BASE_WEAPONS_BY_ID.stun_boomerang, BASE_WEAPONS_BY_ID.homing_missile,
	},
}

-- Phases 3-4 of the LÖVE port (see
-- _bmad-output/planning-artifacts/lua-love-port-spec-2026-09-12.md).
-- Phase 3 built the whole weapon/projectile/impact/HUD pipeline end to end
-- against one simple character (Mitrailleur). Phase 4 repeated that
-- pattern for the other 7 — all 8 are ported under data/characters/, each
-- exercising at least one mechanic the previous ones didn't: fan bursts
-- (Spreader), homing + a heavy weapon's vulnerability window + heavy_push
-- knockback (Lourd), the boomerang's fixed-arc-then-live-homing motion
-- (Perturbateur), the timed hitscan beam (Zoneur), the placed/destructible
-- autonomous turret (Controleur), a homing fan burst that needed no new
-- code at all (Traqueur), and the sine-wave trajectory + fire-recoil speed
-- kick (Vif). Phase 6 wired this up to a real character_select screen
-- (see screens/character_select.lua) via match_setup — enter() reads
-- match_setup.p1_character/p2_character, falling back to Mitrailleur vs
-- Mitrailleur only when entered directly (e.g. ad hoc dev testing) without
-- going through that screen first.
--
-- Fixes a Phase-2 shortcut along the way: missing the ball used to end the
-- round outright (plain Pong scoring). That contradicts the GDD ("the ball
-- never deals damage — it is purely a resource-catch mechanic", see
-- ball_state.lua's own header) — the real loop is ball miss/return fills a
-- weapon gauge, and only weapon fire (now that one exists) ends a round by
-- draining hp to 0.

local match_arena = {}

local ARENA_BOUNDS = Rect2.new(40, 60, 1200, 600) -- matches the Godot project's own arena_size — the FULL, un-shrunk reference
local FRONTIER_X = ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x / 2.0
local ARENA_CENTER_Y = ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0
-- 2026-10-05 "tout plus gros" pass: paddles x1.5 (14x28 -> 21x42). See
-- ball_state.lua's own matching doc comment on RADIUS/SPEED_INCREMENT.
local SHIP_HALF_EXTENTS = Vector2.new(14 * 1.5, 28 * 1.5)
local SERVE_DELAY = 1.0 -- seconds the ball sits frozen before each serve

-- Epic 4 twists (Story 4.5), campaign mode only — mirrors
-- match_arena_node.gd's apply_twist()/_process_twist() dispatch. All 8
-- twist_types across all 8 characters' campaigns are ported: gauge_floor,
-- shrinking_arena, hazard_zones, invisible_opponent, drifting_neutral_zone,
-- visual_decoy, multi_ball (see extra_balls further down), and
-- energy_orb_pickup (the organizer's own, boss-escalation included — see
-- boss_helpers further down).
local active_twist -- nil outside campaign mode, or when the encounter has none


-- shrinking_arena: current_arena_bounds/current_frontier_x replace the
-- ARENA_BOUNDS/FRONTIER_X constants at every GAMEPLAY site (movement
-- clamp, ball walls/out-of-bounds, knockback, beam range) — the constants
-- stay the fixed reference shrink amounts are computed from and what a
-- fresh round resets back to.
local current_arena_bounds, current_frontier_x
local shrink_step, shrink_step_timer, shrink_animating, shrink_anim_elapsed, shrink_start_bounds, shrink_target_bounds
local hazards, hazard_spawn_timer
local orbs, orb_spawn_timer

-- drifting_neutral_zone: continuous back-and-forth drift of the shared
-- frontier_x, reusing current_frontier_x (the same value shrinking_arena
-- animates — the two twists never combine, so no conflict).
local drift_direction

-- visual_decoy ("Double moi"): a copy of the AI opponent's appearance that
-- wanders erratically — zero damage, zero hp, no collision with anything,
-- pure confusion about which ship is the real target. Spawned once when
-- the encounter starts (not re-spawned per round, matching apply_twist()
-- being a one-time setup step on the Godot side).
local decoy

-- Every twist's own pure tuning constant, in ONE table (not 7 top-level
-- locals — the 200-local ceiling, same reason as UT/boss_helpers). The
-- mutable per-round STATE each twist owns (hazards/orbs/decoy/shrink_*/
-- drift_direction above) stays as separate locals — only read/written in
-- a handful of places each, unlike these which are pure constants read
-- all over update_twist()/apply_twist()-equivalent setup.
local TWIST_TUNING = {
	MAX_SHRINK_STEPS = 6,
	HAZARD_STUN_DURATION = 0.4, -- short — a tap, not a lockout; it's an environmental hazard, not a weapon
	HAZARD_DEFLECT_COOLDOWN = 0.3, -- avoid re-deflecting the same ball every frame while it lingers inside the radius
	ORB_PICKUP_RADIUS = 16.0,
	ORB_LIFETIME = 12.0, -- despawns if nobody grabs it in time
	DECOY_WANDER_INTERVAL_MIN = 0.6,
	DECOY_WANDER_INTERVAL_MAX = 1.6,
}

-- Every ship-feel tuning constant below (lift/charge, heavy-weapon
-- vulnerability, Lourd's heavy_push, charged-fire grace/blink, the AI's own
-- tracking deadzone, and the two speed multipliers used only in
-- update_player_input()'s stacking chain) in ONE table — not ~10 top-level
-- locals (the 200-local ceiling, same reason as UT/boss_helpers).
-- push_pending stays a separate local: real per-ball mutable STATE, not a
-- tuning constant.
local SHIP_FEEL = {
	-- Lift/charge (Story 1.2/1.7 — ported here alongside Lourd, the first
	-- character whose special_rule needs it): holding the lift key slows
	-- movement to a crawl (MOVE_MULTIPLIER below) and charges a return's
	-- spin; tiers match ship_node.gd's get_lift_charge() exactly.
	LIFT_CHARGE_CAP = 2.0, -- seconds to reach 100%
	LIFT_CHARGE_MOVE_MULTIPLIER = 0.25, -- 2026-08-13: was a full freeze, now "a slowed crawl instead — still a real risk/reward trade, not a full lockdown"
	FIRE_HOLD_SPEED_MULTIPLIER = 0.5, -- -50% while the fire button is held, whether or not a shot actually goes through — applies to EVERY character, not just a specific weapon

	-- Story 1.8 — firing a heavy weapon (WeaponData.is_heavy) briefly slows
	-- the shooter's own movement.
	VULNERABILITY_DURATION = 0.7,
	VULNERABILITY_SPEED_MULTIPLIER = 0.35,

	-- Lourd's "heavy_push" rule (2026-08-09): a fully-charged lift return
	-- shoves whichever ship the ball reaches next, on contact, whether or
	-- not they go on to return it.
	HEAVY_PUSH_DISTANCE = 40.0,

	-- Charged fire (ship_node.gd, 2026-08-09): holding Tir past the grace
	-- window suspends normal fire and starts building a charge; releasing
	-- at or after WeaponData.charge_fire_duration fires the empowered
	-- variant instead of a normal shot, releasing early wastes the
	-- attempt. AI never charges (this port's "basique" AI just holds fire
	-- every frame — see update_player_input()).
	NORMAL_FIRE_GRACE = 1.0, -- seconds of normal fire before a sustained hold starts charging
	CHARGE_READY_BLINK_PERIOD = 0.15, -- seconds per on/off cycle once fully charged
	CONTROL_SCRAMBLE_BLINK_PERIOD = 0.3, -- Perturbateur's Ultra: a fast violet flicker makes the debuff actually readable

}
local push_pending = false -- module-level: the ball itself carries this, not either ship

-- ship_node.gd's real AI (2026-08-16/17 tuning passes — "l'IA n'est pas
-- tres maline. Il faudrait qu'elle cherche vraiment a renvoyer la balle au
-- maximum, c'est sa priorite. Deuxieme priorite: esquiver les tirs. 3eme
-- prio: faire des degats", escalating toward self-preservation as HP
-- drops) — replaces this port's earlier "basique" stand-in (2026-09-14,
-- Camil: "l'IA est vraiment nulle... on avait fait toute une passe pour
-- qu'elle soit bonne, regarde le code godot"). Weapon-switching
-- (_ai_update_weapon_switch/signature_bias) is NOT ported: every real
-- character's kit has exactly one weapon (only the masked boss's kit has
-- more, and it never switches — see boss_helpers), so cycling selection
-- is a pure no-op for every matchup this game actually has. Same reason
-- Vif's "dash_lift" AI branch isn't ported either — special_rule is
-- "none" for every character in the current roster.
local AI_TUNING = {
	MAX_LOOKAHEAD = 1.2, -- seconds, ball-Y intercept prediction cap
	DEADZONE_STOP = 4.0,
	DEADZONE_START = 14.0,
	H_DEADZONE_STOP = 6.0,
	H_DEADZONE_START = 18.0,

	WANDER_INTERVAL_MIN = 1.2,
	WANDER_INTERVAL_MAX = 2.4,

	DEPTH_INTERVAL_MIN = 2.0,
	DEPTH_INTERVAL_MAX = 4.0,
	DEPTH_MIN = 0.1,
	DEPTH_MAX = 0.5,
	APPROACH_DISTANCE = 260.0,

	DODGE_DETECT_RANGE = 260.0, -- px — a threat further than this isn't worth reacting to yet
	DODGE_MARGIN = 50.0, -- px — how close a threat's Y needs to sit to this ship's own Y to count as "lined up to hit me"
	TURRET_HUNT_HP_FLOOR = 0.4, -- above this HP fraction, actively hunting a live enemy turret suppresses dodge entirely

	-- 2026-09-01: mook encounters are warm-ups, not full fights — these
	-- scale a mook's aggressiveness down on top of its character profile.
	MOOK_APPROACH_SCALE = 0.65,
	MOOK_DEPTH_SCALE = 0.65,
	MOOK_LIFT_SCALE = 0.60,

	-- 2026-09-27: charged-fire for the AI. The root problem was that
	-- should_fire() returns false whenever weapon.cooldown > 0, which resets
	-- fire_held_duration back to zero after EVERY normal shot — the charge
	-- window never accumulated. Fix: a dedicated ai_charge_timer holds
	-- firing=true continuously (bypassing the cooldown gate) for the full
	-- NORMAL_FIRE_GRACE + charge_fire_duration window, then releases for one
	-- frame to trigger try_charged_fire() via the normal released_charge_attempt
	-- path. The AI rolls a charge attempt at most every CHARGE_DECIDE_INTERVAL_*
	-- seconds, only when already aligned with the opponent. Camil: adjust
	-- CHARGE_FIRE_CHANCE and CHARGE_DECIDE_INTERVAL_* after playtesting — the
	-- mechanism is proven correct (see the throwaway test in
	-- AI_TUNING_LOG.md), FREQUENCY is the tuning knob.
	CHARGE_FIRE_CHANCE = 0.35,         -- prob. to attempt a charge when the roll fires (0-1)
	CHARGE_DECIDE_INTERVAL_MIN = 4.0,  -- seconds between charge attempt rolls (min)
	CHARGE_DECIDE_INTERVAL_MAX = 8.0,  -- seconds between charge attempt rolls (max)

	-- Per-archetype tuning, keyed by CharacterData.id. signature_bias was
	-- previously omitted as "a pure no-op for every matchup this game
	-- actually has" (every real character's kit has exactly one weapon) —
	-- 2026-09-27 (Camil: "le boss doit utiliser les differentes armes. En
	-- phase 1, je ne le vois utiliser, principalement, que mitrailleur")
	-- proved that wrong: the Epic boss's 8-weapon FULL_KIT (added after that
	-- comment was written) DOES exercise this, and ship_node.gd's own
	-- _ai_update_weapon_switch()/signature_bias was never ported alongside
	-- it — see ai_helpers.update_weapon_switch() below. Values match
	-- ship_node.gd's AI_PROFILES exactly.
	PROFILES = {
		lourd = { depth_min = 0.05, depth_max = 0.25, approach_distance = 200.0, lift_chance = 0.15, signature_bias = 0.85 },
		controleur = { depth_min = 0.1, depth_max = 0.3, approach_distance = 200.0, lift_chance = 0.2, signature_bias = 0.85 },
		mitrailleur = { depth_min = 0.2, depth_max = 0.5, approach_distance = 280.0, lift_chance = 0.3, signature_bias = 0.55 },
		vif = { depth_min = 0.35, depth_max = 0.65, approach_distance = 340.0, lift_chance = 0.45, signature_bias = 0.7 },
		zoneur = { depth_min = 0.3, depth_max = 0.55, approach_distance = 240.0, lift_chance = 0.2, signature_bias = 0.75 },
		perturbateur = { depth_min = 0.25, depth_max = 0.5, approach_distance = 280.0, lift_chance = 0.35, signature_bias = 0.75 },
		missiles = { depth_min = 0.15, depth_max = 0.35, approach_distance = 220.0, lift_chance = 0.2, signature_bias = 0.8 },
		mini = { depth_min = 0.3, depth_max = 0.6, approach_distance = 340.0, lift_chance = 0.4, signature_bias = 0.85 },
	},
	-- ship_node.gd's own randf_range(3.0, 6.0) bounds for _ai_weapon_switch_timer.
	WEAPON_SWITCH_INTERVAL_MIN = 3.0,
	WEAPON_SWITCH_INTERVAL_MAX = 6.0,
}

local function lift_charge_fraction(held_time)
	if held_time < 0.3 then
		return 0.0
	elseif held_time < 0.6 then
		return 0.33
	elseif held_time < SHIP_FEEL.LIFT_CHARGE_CAP then
		return 0.66
	end
	return 1.0
end

-- "Systeme des 5 balles" (weapon_system_state.lua's own ultra_pips/
-- ULTRA_METER_MAX): a dedicated trigger key, separate from fire/lift/
-- weapon-select, matching ship_node.gd's _read_ultra_pressed() exactly —
-- P1 = E, P2 = numpad Enter (distinct from P2's own main-Enter fire key).
-- "Systeme des 5 balles" misc tuning, one table (not 3 top-level locals —
-- 200-local ceiling, same reason as UT/boss_helpers). ULTRA_MISC.FLASH_DURATION
-- is a small complementary HUD cue (the per-player "ULTRA !" weapon-swatch
-- label, draw_player_hud()) distinct from the full slide/hold/slide
-- cinematic (see UI/draw_ultra_intro() further down) — it lingers a beat
-- after the cinematic itself finishes, not a stand-in for it.
local ULTRA_MISC = {
	GENERIC_ULTRA_DAMAGE = 25.0, -- match_arena_node.gd's own fallback for any character without a bespoke Ultra effect (see resolve_ultra_effect())
	DENY_SHAKE_DURATION = 0.25,
	FLASH_DURATION = 0.7,
}

-- Perturbateur's boomerang (projectile_node.gd's _update_boomerang()):
-- outbound leg is a FIXED, deterministic banana arc (never references the
-- target — not homing by construction); return leg re-aims at the
-- shooter's live position each frame, and gives up (coasts straight) if
-- the shooter visibly dodges it mid-return.
-- One table (not 6 top-level locals — the 200-local ceiling, same reason
-- as UT/boss_helpers) for Perturbateur's boomerang tuning.
local BOOMERANG = {
	ARC_ANGLE_DEG = 30.0,
	RETURN_TURN_RATE_DEG = 260.0, -- deg/sec, re-aim speed on the way back
	DEFAULT_OUT_DURATION = 0.45, -- fallback when a weapon doesn't override boomerang_out_duration
	CATCH_DISTANCE = 24.0, -- despawns once this close to the shooter on the return leg
	MISS_ENGAGE_DISTANCE = 100.0, -- must have closed to at least this distance to arm the miss/dodge detection
	MISS_MARGIN = 15.0, -- how far it must drift back away from its closest approach to count as dodged
}

-- Perturbateur's charged Boomerang de Feu (fire_trail_node.gd, 2026-08-17):
-- drops a damaging fire puddle every FIRE_TRAIL.DROP_INTERVAL of flight
-- (both legs), each one lingering and ticking damage while the opponent
-- stands in it. One table, same 200-local reason as BOOMERANG above.
local FIRE_TRAIL = {
	DROP_INTERVAL = 0.06, -- short enough that consecutive puddles overlap into one continuous strip at boomerang speed
	RADIUS = 24.0,
	LIFETIME = 3.0,
	DAMAGE_PER_TICK = 2.0,
	TICK_INTERVAL = 0.4,
	FADE_OUT_DURATION = 0.6, -- last stretch of lifetime — the flame dies down instead of popping out
}

local function wrap_angle(angle)
	local two_pi = math.pi * 2.0
	local wrapped = angle % two_pi
	if wrapped > math.pi then
		wrapped = wrapped - two_pi
	end
	return wrapped
end

-- Zoneur's beam (beam_node.gd): not a projectile — a self-contained timed
-- hitscan ray that follows its shooter's position every frame and ticks
-- damage (weapon.damage reinterpreted as damage PER SECOND) while the
-- opponent sits within range and roughly at the same height.
local BEAM = {
	BASE_THICKNESS = 6.0,
	TICK_INTERVAL = 0.1,
	FADE_DURATION = 0.08, -- "petit effet visuel fade in fade out tres rapide"
}

-- Controleur's turret (turret_node.gd): firing this weapon PLACES a
-- stationary, destructible, autonomously-firing entity at the shooter's
-- current position instead of launching a projectile — a real third kind
-- of "what does firing do" alongside bullets and beams.
local TURRET = {
	HALF_EXTENTS = Vector2.new(15.0, 15.0),
	SHOT_SPEED = 480.0,
	FLASH_DURATION = 0.08,
}

-- Team colors reused from the Godot project's own ship-debris palette
-- (match_arena_node.gd's _spawn_ship_debris_burst), for visual continuity
-- across the port.
local SIDE_COLOR = {
	[0] = { 0.27, 0.85, 1.0 },
	[1] = { 1.0, 0.55, 0.7 },
}

-- Matches ship_node.gd's real bindings exactly (_read_fire_pressed()/
-- _read_lift_held()): player_index==1 (P1) = Space/Shift; everyone else
-- (P2) = Enter/Ctrl. Scancodes name the QWERTY-reference PHYSICAL
-- position, not the label printed on the keycap — "w"/"a" are the correct
-- scancodes for the corner cluster's top/left keys on ANY layout,
-- including AZERTY, where that same physical position happens to be
-- printed "Z"/"Q" (the standard ZQSD convention); do not "translate"
-- these to "z"/"q" (see 2026-09-12 bug). "return" is LÖVE's scancode name
-- for the main Enter key (distinct from "kpenter", the numpad one — same
-- distinction the Godot source itself calls out). Right Ctrl, not the
-- ambiguous generic "Ctrl", since P2 sits at the right side of the
-- keyboard. Used for BOTH Versus (two humans) and campaign mode (P1 human
-- vs P2 AI, which never reads any of this — see update_player_input()).
-- lift is a LIST here (2026-09-14, Camil: "pour J1 ce serait bien de
-- pouvoir utiliser shift droit aussi pour le lift") — either shift key
-- works for P1; see is_binding_down() for the string-or-list dispatch.
-- 2026-09-27 (Camil: "il faut pouvoir jouer avec des manettes") — one
-- physical controller per player, matched by side (P1 = device 1, P2 =
-- device 2 — see input.get_joystick()). *_button fields added alongside
-- the existing keyboard bindings; movement itself isn't listed here since
-- it goes through input.direction_down() (D-pad + left stick) in
-- input_direction() below, same as every other screen. Button layout
-- (2026-09-27, Camil's own Xbox pad, after trying the first pass — "A pour
-- le lift, X pour le tir, B pour l'ultra", pause menu on Start instead of
-- B/back since B is now Ultra — see open_pause_menu()'s own poll below):
-- X = fire, A = lift, B = ultra.
-- 2026-10-06 (Floppy's playtest, relayed by Camil: "puisque tu as encore
-- des boutons qui ne font rien, je rajouterais bien un petit dash") — Q
-- (next to WASD) for P1, "/" (next to the arrow cluster) for P2, Y on
-- both gamepads (the one face button still free). See dash_helpers.effects/
-- update_dash() for the actual per-character behavior.
local P1_CONTROLS = { up = "w", down = "s", left = "a", right = "d", fire = "space", lift = { "lshift", "rshift" }, ultra = "e", dash = "q", fire_button = "x", lift_button = "a", ultra_button = "b", dash_button = "y" }
local P2_CONTROLS = { up = "up", down = "down", left = "left", right = "right", fire = "return", lift = "rctrl", ultra = "kpenter", dash = "/", fire_button = "x", lift_button = "a", ultra_button = "b", dash_button = "y" }

-- A control binding can be a single scancode string, or (P1's lift, above)
-- a list of alternatives — true if ANY of them (or the given gamepad
-- button/list) is currently held.
local function is_binding_down(binding, joystick, button)
	if input.button_down(joystick, button) then
		return true
	end
	if binding == nil then
		return false
	end
	if type(binding) == "table" then
		for _, key in ipairs(binding) do
			if love.keyboard.isScancodeDown(key) then
				return true
			end
		end
		return false
	end
	return love.keyboard.isScancodeDown(binding)
end

local players -- { [1] = player table for side 0, [2] = player table for side 1 }
local ball, match, serving

-- ball_node.gd's own "zoom" (2026-09-14 bug report, Camil: "il manque des
-- effets... l'histoire du zoom quand la balle arrive en jeu"): the ball
-- ALWAYS spins continuously (ROTATION_SPEED, whether flying or frozen),
-- and pops in oversized after a miss (RESPAWN_POP_START_SCALE), shrinking
-- back to normal size over the SAME SERVE_DELAY freeze that already
-- exists — this is purely a rendering concern (Regle absolue n1: never
-- mix into ball_state.lua's own pure simulation data), so it's tracked
-- here, not on the ball itself. serve_freeze_elapsed drives the shrink
-- lerp during that freeze; nil once the ball is live (rotation still
-- ticks either way).
local ROTATION_SPEED = 6.0 -- rad/s
local RESPAWN_POP_START_SCALE = 2.0
local ball_rotation = 0.0
local ball_scale = 1.0
local serve_freeze_elapsed

-- "multi_ball" twist (match_arena_node.gd's _extra_balls/_spawn_extra_balls()):
-- ball_count-1 extra, fully independent balls — same physics/paddle/turret/
-- hazard collision, miss->gauge-fill behavior, AND own trail VFX as the
-- primary `ball` (ball_node.gd's miss handling is symmetric and per-ball;
-- missing NEVER ends a round by itself, see apply_damage_and_check_round's
-- own doc comment). Spawned once per encounter (enter()), not re-spawned
-- per round — re-centered instead, like the primary, in
-- begin_round_ready_gate(). Each entry: { ball_data = <ball_state>,
-- trail_ps = its own persistent ParticleSystem (make_ball_trail_ps()),
-- frozen_timer = seconds left frozen after ITS OWN miss (nil if live),
-- pending_velocity = the launch velocity waiting for frozen_timer to
-- elapse }. Empty list outside the multi_ball twist.
local extra_balls = {}

local bullets, impacts, beams, turrets, fire_trails, missile_strikes, black_holes, laser_meshes, wind_gusts, floating_texts, gauge_fill_effects, heal_fx
local ghost_paddles -- Contrôleur's/Perturbateur's dash: temporary stationary paddle-like hitboxes (see dash_helpers.effects/update_ghost_paddles())

-- Epic 4 reward system: unlike every other entity list above, this is
-- match-persistent, not round-persistent — built once in match_arena.
-- enter() and never touched by start_new_round(), mirroring Godot's own
-- Timer-child-of-the-ship-node lifetime ("spans the whole match, survives
-- round transitions"). Keyed by side (1/2, matching `players`), each entry
-- is { timers = {{weapon, elapsed}, ...}, speed_multiplier }.
local passive_state

-- ultra_intro_node.gd: while this is set, match_arena.update() does NOTHING
-- but advance the intro's own phase timer (see the top of update()) —
-- ships/ball/projectiles/turrets/hazards/twists all freeze for its whole
-- ~1.67s duration, same effect as Godot's get_tree().paused = true (this
-- port has no engine-level pause to reuse, so the freeze is just "skip
-- every other update this frame" instead). nil when no intro is playing.
local ultra_intro

-- pause_controller.gd/match_arena_node.gd's in-game pause menu (2026-09-12,
-- Camil: "quand on fait echap en pleine partie, ca revient au menu. Il
-- faudrait que ca fasse pause, avec un menu in game 'retourner au menu'
-- 'continuer la partie'... il faut que ca freeze completement le jeu,
-- tout"). Same freeze mechanism as ultra_intro (skip every other update
-- this frame) — universal across Versus AND campaign, replacing what used
-- to be campaign-only instant-bail Escape handling. nil when not paused.
local pause_state
local escape_prev = false
-- 2026-10-05 (feedback FX — see feedback_fx's own doc comment further down,
-- same "one table" convention as UT/boss_helpers/ultra_helpers, the
-- 200-local ceiling): forward-declared here so start_new_round()/
-- match_arena.enter(), both defined earlier in this file, can reset its
-- mutable shake_* fields between rounds/matches.
local feedback_fx = {
	-- Perturbateur's dash ("ralentir la balle pendant 1/2 secondes") — not
	-- really a "feedback" value, but start_new_round()/enter() (both defined
	-- textually before dash_helpers exists) need to reset it between rounds,
	-- same reason ship_explosion_helpers below sits where it does rather
	-- than folded into UT; stashed here instead of a new top-level local
	-- (the 200-local ceiling). The mutable timer itself lives as the
	-- ball_slow_timer field below; this is just its initial value.
	ball_slow_timer = 0.0,
	PADDLE_FLASH_DURATION = 0.15,
	-- 2026-10-05 playtest: "les secousses sur un coup recu ne se sentent
	-- pas" — most real weapon hits are small (machine_gun=2, mini_shot=3),
	-- which the original pure damage*0.6 scaling (no floor) made nearly
	-- imperceptible (1.2-1.8px) even before the shake_magnitude reset bug
	-- above. MIN guarantees every hit reads as a hit; MAX still reserves a
	-- noticeably bigger shake for a real haymaker (bazooka splash etc.).
	-- Duration bumped to match the miss-shake's own 0.3s, which the same
	-- playtest called "nickel" — no reason for a hit to feel shorter.
	-- 2026-10-05, next playtest round: "pour le coup c'est un peu trop
	-- violent, faut reduire, /2" — halved straight across (duration stays
	-- the same, only intensity drops). Then "on peut remonter un peu la
	-- secousse du choc (+25%)" — +25% back on top of that halved baseline.
	SHAKE_DAMAGE_DURATION = 0.3,
	SHAKE_DAMAGE_MAGNITUDE_PER_DAMAGE = 0.625, -- 0.5 * 1.25
	SHAKE_DAMAGE_MAGNITUDE_MIN = 3.75, -- 3.0 * 1.25
	SHAKE_DAMAGE_MAGNITUDE_MAX = 10.0, -- 8.0 * 1.25
	SHAKE_MISS_DURATION = 0.3,
	SHAKE_MISS_MAGNITUDE = 10.0,
	shake_timer = 0.0,
	shake_duration = 0.0,
	shake_magnitude = 0.0,
}

-- match_arena_node.gd's dev-only cheat keys (2026-08-13) and F1 AI-toggle
-- (Story 1.12) — K instantly kills P2, U maxes P1's ultra meter, M fills
-- P1's ammo/weapon gauges, F1 flips P2 between human/AI (Versus only — a
-- campaign mook/rival/organizer has no second human to hand control to).
-- One table, not 4 top-level locals (200-local ceiling, same as UT/UI).
local cheat_state = { kill_prev = false, ultra_prev = false, ammo_prev = false, ai_toggle_prev = false }

-- debug_overlay.gd (2026-08-10, Camil: "j'aimerais que tu me mettes les
-- hitbox autour de TOUTES les armes, activables en appuyant sur la touche
-- TAB... cela me permettra de comprendre pourquoi certaines fois je ne
-- touche pas") — toggled in keypressed(), drawn in draw() for every ship/
-- turret (the exact rect projectile collision checks against, NOT the
-- larger ball-catch rect).
local show_hitboxes = false

local PAUSE_MENU_CHOICES = { "Continuer la partie", "Retourner au menu" }

-- match_arena_node.gd's _show_post_match_choice()/_process_post_match_
-- choice() (2026-08-16 UX audit, Sally: "Versus mode ends in a dead
-- screen") — Versus-only (campaign's own win/loss continue-key handles
-- itself); a short beat after the "Match termine" text lands, then the
-- same up/down + confirm menu every other screen in this port uses,
-- offering a rematch or a trip back to character select. nil until
-- match_over (Versus only) and the death explosion have both finished;
-- post_match_choice_timer counts down the beat, post_match_choice is the
-- actual menu state once it's up.
local POST_MATCH_CHOICES = { "Revanche", "Choix des personnages" }
local POST_MATCH_CHOICE_DELAY = 1.2
local post_match_choice_timer
local post_match_choice

-- "Pret ?" round-start gate (match_arena_node.gd's RoundStartPhase):
-- freezes the whole round (same freeze pattern as ultra_intro/pause_state)
-- until a player presses Tir, then plays a two-phase "Ready...... / GO !"
-- flash before actually serving the ball. nil once a round is live.
local round_start_gate
local ROUND_START_GATE = { READY_FLASH_DURATION = 1.5, GO_FLASH_DURATION = 1.0 }

-- Ship explosion (match_arena_node.gd's _resolve_round_end()/
-- _play_ship_explosion(), 2026-09-12 bug report: "quand on perd (0pv) il
-- faudrait une explosion lente du vaisseau avant apparition du 'appuyer
-- pour continuer'") — same freeze pattern as ultra_intro/pause_state/
-- round_start_gate, sitting between a kill landing and the next round (or
-- match-over screen) actually starting. ONE table (not several top-level
-- locals — the 200-local ceiling, same reason as boss_helpers) carrying
-- both the tuning constants and the mutable state/entity list, filled in
-- progressively through this file (functions added further down, same
-- convention as ultra_helpers/boss_helpers); declared here, not folded
-- into UT below, so apply_damage_and_check_round/enter() — textually
-- defined before UT exists — can read it directly.
local ship_explosion_helpers = {
	-- 2026-09-12 playtest follow-ups (Camil: "trop long, tu peux enlever
	-- une seconde... 1 explosion et le vaisseau doit se disloquer" then "le
	-- clignotement avant l'explosion est un peu long, tu peux mettre 1s")
	-- — match_arena_node.gd's SHIP_EXPLOSION_DURATION/_FLICKER_HALF_PERIOD,
	-- plus this port's own debris/disintegration particle-system lifetimes.
	DURATION = 1.0,
	FLICKER_HALF_PERIOD = 0.1,
	DEBRIS_LIFETIME = 0.5,
	DISINTEGRATION_LIFETIME = 0.6,

	-- round = nil once no ship is exploding, else
	-- { loser = <player>, loser_side, phase_timer, flicker_timer, flicker_on }.
	-- bursts = the spawned debris/disintegration ParticleSystems still
	-- aging out — left alone by start_new_round(), same "let it finish
	-- playing out across the round boundary" convention as `impacts`.
	round = nil,
	bursts = {},
}

-- Campaign mode (set in enter(), read by update()/keypressed()): a fight
-- launched from CampaignMap instead of Versus's character_select. P2 is
-- AI-controlled, plays as the encounter's own opponent, and winning/losing
-- resolves the campaign encounter (reward/unlock/progress) instead of
-- offering a rematch.
local campaign_mode, campaign_encounter, campaign_character_id

-- ship_node.gd's _apply_ai_profile(): per-character depth/approach/lift
-- tuning, scaled back further for a mook (a campaign warm-up fight, not a
-- full-strength one). No-op fields (defaults) for a character with no
-- profile entry — never happens in practice (all 8 have one) but matches
-- Godot's own defensive fallback.
local function apply_ai_profile(player)
	local profile = AI_TUNING.PROFILES[player.character.id]
	if not profile then
		player.ai_depth_min = AI_TUNING.DEPTH_MIN
		player.ai_depth_max = AI_TUNING.DEPTH_MAX
		player.ai_approach_distance = AI_TUNING.APPROACH_DISTANCE
		player.ai_lift_chance = 0.3
		player.ai_signature_bias = 0.0
		return
	end
	player.ai_depth_min = profile.depth_min
	player.ai_depth_max = profile.depth_max
	player.ai_approach_distance = profile.approach_distance
	player.ai_lift_chance = profile.lift_chance
	player.ai_signature_bias = profile.signature_bias
	if player.ai_is_mook then
		player.ai_depth_min = player.ai_depth_min * AI_TUNING.MOOK_DEPTH_SCALE
		player.ai_depth_max = player.ai_depth_max * AI_TUNING.MOOK_DEPTH_SCALE
		player.ai_approach_distance = player.ai_approach_distance * AI_TUNING.MOOK_APPROACH_SCALE
		player.ai_lift_chance = player.ai_lift_chance * AI_TUNING.MOOK_LIFT_SCALE
	end
end

local function new_player(side, character, controls, is_ai, max_hp, is_mook)
	local x = side == 0 and (ARENA_BOUNDS.position.x + 40) or (ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x - 40)
	max_hp = max_hp or ship_state.START_HP
	local player = {
		side = side,
		character = character,
		is_ai = is_ai or false,
		max_hp = max_hp,
		ship = ship_state.new(Vector2.new(x, ARENA_CENTER_Y), side, SHIP_HALF_EXTENTS, max_hp),
		weapon = weapon_system_state.new(character.kit),
		controls = controls,
		fire_held_prev = false,
		lift_charge_timer = 0.0,
		paddle_flash_timer = 0.0, -- 2026-10-05 feedback FX: brief white flash on a successful ball return (see ship_tint())
		vulnerability_timer = 0.0,
		fire_recoil_timer = 0.0, -- Vif's Tourbillon recoil speed kick
		last_move_direction = Vector2.ZERO, -- last NON-ZERO input direction (Perturbateur's boomerang throw-arc side)
		last_input_direction = Vector2.ZERO, -- this frame's raw input (human or AI) — reused for the ball-return aim
		stun_timer = 0.0, -- hazard_zones twist
		fire_held_duration = 0.0, -- charged fire: how long Tir has been held past the grace window
		charged_beam_slow_timer = 0.0, -- Zoneur's charged beam: self-slow for the pulse's own lifetime
		charged_beam_slow_multiplier = 1.0,
		double_fire_shots_remaining = 0, -- Mitrailleur's charged-fire buff: N subsequent normal shots fire doubled
		ultra_prev = false, -- edge-detects the Ultra trigger key
		ultra_deny_shake_timer = 0.0, -- HUD feedback: pressed Ultra before the meter was full
		ultra_flash_timer = 0.0, -- this port's simplified Ultra-cast flash (see resolve_ultra_effect())
		controls_scrambled_timer = 0.0, -- Perturbateur's Ultra "Brouillage de commandes"
		controls_scramble_angle = 0.0, -- rolled once per fresh application, held for the whole duration
		satellite_turrets = nil, -- Mitrailleur's Ultra "Mitrailleuses Satellites" — set to a list of turret refs when cast
		external_slow_timer = 0.0, -- Contrôleur's Ultra "Trou noir" (an opponent's effect on this ship — see ship_node.gd's own doc comment distinguishing this from charged_beam_slow, a ship slowing ITSELF)
		external_slow_multiplier = 1.0,
		boss_simultaneous_fire_indices = {}, -- Epic boss: extra kit-slot indices that fire for free alongside the selected weapon's own normal shot, from phase 2/3 onward — see boss_helpers.setup_ship()/update_phases()
		exploded_hidden = false, -- set true once this ship's own death explosion finishes (see ship_explosion_helpers.update_explosion()) — draw_ship() skips it from then on

		-- 2026-10-06 (Floppy's playtest, relayed by Camil: "je rajouterais
		-- bien un petit dash [...] si ce dash est specifique a chaque perso,
		-- c'est le pied") — one button, one cooldown, 8 completely different
		-- effects (see dash_helpers.effects/update_dash()). Fields below are shared
		-- generic-purpose state reused by whichever effect the player's own
		-- character actually has — never more than one is meaningful per
		-- character, so there's no need for 8 separate field sets.
		dash_prev = false, -- edge-detects the dash key/button
		dash_cooldown_timer = 0.0, -- 0 = ready; see dash_helpers.COOLDOWN
		dash_boost_timer = 0.0, -- Lourd (drift) / Spreader (speed): decaying speed_multiplier boost
		dash_boost_peak_multiplier = 1.0,
		dash_boost_decay_time = 0.0,
		dash_slide_direction = Vector2.ZERO, -- Lourd only: the fixed direction his "inertie de derapage" keeps sliding toward while dash_boost_timer counts down
		dash_jump_timer = 0.0, -- Vif: forced movement + visual zoom for the jump's whole duration
		dash_jump_duration = 0.0,
		dash_invuln_timer = 0.0, -- Vif's jump: briefly untouchable by weapon fire
		dash_pull_timer = 0.0, -- Traqueur: pulls the ball toward him for a moment

		-- ship_node.gd's real AI (see AI_TUNING's own doc comment).
		ai_is_mook = is_mook or false,
		ai_vertical_dir = 0.0, -- persists between frames — hysteresis avoids jittery on/off "freeze"
		ai_horizontal_dir = 0.0,
		ai_wander_timer = 0.0,
		ai_wander_target_y = 0.0,
		ai_depth_timer = 0.0,
		ai_preferred_depth = 0.35, -- 0 = back wall, 1 = frontier — re-picked periodically
		ai_lift_timer = 0.0,
		ai_lift_decided = false,
		-- Charged-fire state machine (2026-09-27): see ai_helpers.update_charge_attempt().
		ai_charge_timer = 0.0,     -- >0: AI holds fire continuously, overriding should_fire()'s cooldown gate
		ai_charge_releasing = false, -- one-frame flag: set firing=false to trigger try_charged_fire()
		ai_charge_decide_timer = 0.0, -- inter-attempt cooldown (CHARGE_DECIDE_INTERVAL_*);
		-- ship_node.gd's own _ai_weapon_switch_timer — see
		-- ai_helpers.update_weapon_switch(). A no-op for every real
		-- character (kit.size()==1); only matters for the Epic boss.
		ai_weapon_switch_timer = AI_TUNING.WEAPON_SWITCH_INTERVAL_MIN
			+ math.random() * (AI_TUNING.WEAPON_SWITCH_INTERVAL_MAX - AI_TUNING.WEAPON_SWITCH_INTERVAL_MIN),
	}
	apply_ai_profile(player)
	return player
end

-- Forward-declared: match_arena.enter() (below) needs to call this once per
-- match, but its actual body reads BASE_WEAPONS_BY_ID/UT, both defined
-- further down this file (same forward-declare pattern as
-- resolve_ultra_effect) — assigned once they exist.
local build_passive_state

-- Forward-declared for the same reason: enter()'s own multi_ball extra-ball
-- spawn loop needs this to give each extra its own trail, but the actual
-- particle-system tuning lives further down alongside the primary's own
-- ball_trail_ps (assets.fire_particle et al. all already exist by then;
-- this is purely a textual-ordering forward-reference, not a data one).
local make_ball_trail_ps

local function opponent_of(side)
	return players[side == 0 and 2 or 1]
end

-- match_arena_node.gd's _is_boss_ship(): true only for ship_2/players[2]
-- during the organizer's own "energy_orb_pickup" twist — never for a human
-- P2 in Versus, nor for a normal rival fight with no boss twist active.
-- boss_helpers.setup_ship (used by enter()/start_new_round() to
-- (re-)configure the boss every time players[2] is (re-)built) is assigned
-- later, once UT (boss message text) exists — same forward-reference
-- pattern as resolve_ultra_effect, just via a table field instead of a
-- separately forward-declared local.
function boss_helpers.is_ship(player)
	return player == players[2] and active_twist ~= nil and active_twist.twist_type == "energy_orb_pickup"
end

-- ship_node.gd's apply_control_scramble(): inverts (really, rotates by a
-- random fixed angle) the victim's movement input for `duration`. The angle
-- is rolled once per FRESH application — re-applying while already active
-- just extends the timer (max(), never stacks/re-rolls), matching Godot.
local function apply_control_scramble(player, duration)
	if player.controls_scrambled_timer <= 0.0 then
		player.controls_scramble_angle = math.random() * math.pi * 2.0
	end
	player.controls_scrambled_timer = math.max(player.controls_scrambled_timer, duration)
end

-- ship_node.gd's apply_external_slow(): an OPPONENT's effect on this ship
-- (Contrôleur's Trou noir), refreshed every tick the victim stays inside
-- its radius with a short duration so it fades fast once they escape,
-- rather than lingering. Directly SETS (not max()'s) duration/multiplier —
-- unlike apply_control_scramble, this is meant to be re-armed every tick.
local function apply_external_slow(player, duration, multiplier)
	player.external_slow_timer = duration
	player.external_slow_multiplier = multiplier
end

local function spawn_velocity(toward_side)
	local dir = toward_side == 0 and -1 or 1
	return Vector2.new(dir * ball_state.BASE_SPEED, 0.0)
end

local function serve_ball(toward_side)
	local center = Vector2.new(current_frontier_x, current_arena_bounds.position.y + current_arena_bounds.size.y / 2.0)
	ball = ball_state.new(center, Vector2.ZERO)
	local frozen_position = ball.position
	serving = true
	serve_freeze_elapsed = 0.0
	ball_scale = RESPAWN_POP_START_SCALE -- pops in oversized, shrinks back over the freeze (see match_arena.update())
	timer.after(SERVE_DELAY, function()
		ball = ball_state.new(frozen_position, spawn_velocity(toward_side))
		serving = false
		ball_scale = 1.0 -- land exactly on full size, no float-lerp shortfall
	end)
end

-- "Pret ?" gate (match_arena_node.gd's _begin_round_ready_gate()): freezes
-- the whole round — nothing serves yet — until a player presses Tir, then
-- the two-phase flash plays before update_round_start_gate() finally calls
-- serve_ball() itself. `pending_serve_side` is remembered from whichever
-- caller (enter()'s own random pick, or start_new_round()'s loser) would
-- otherwise have served immediately.
local function begin_round_ready_gate(pending_serve_side)
	-- Ball still needs to exist (frozen, centered on the frontier) for the
	-- whole gate — it's visibly sitting there "Pret ?", just not moving
	-- yet; the real launch velocity only arrives once serve_ball() actually
	-- runs at the end of the gate.
	ball = ball_state.new(Vector2.new(current_frontier_x, current_arena_bounds.position.y + current_arena_bounds.size.y / 2.0), Vector2.ZERO)
	-- 2026-09-01 Godot bug fix carried over (Camil: "j'ai perdu la balle...
	-- mais la balle est restee grosse... il bougeait mais ne rapetissait/
	-- disparaissait jamais") — a round can end (HP hits 0) WHILE the ball's
	-- post-miss pop-in-and-shrink zoom is still playing; without this reset
	-- the next round's ball would inherit whatever oversized ball_scale
	-- that in-flight animation was stranded at.
	ball_scale = 1.0
	serve_freeze_elapsed = nil
	-- multi_ball twist: extras persist across rounds within the same
	-- encounter (never destroyed/re-spawned) — just re-centered like the
	-- primary, matching match_arena_node.gd's _resolve_round_end(). Unlike
	-- the primary, extras get a REAL velocity immediately rather than a
	-- literal freeze — harmless, since nothing ticks their physics until
	-- this whole gate finishes anyway (same reasoning as ball_node.gd's
	-- own reset_to_center() default args at round boundaries).
	for _, extra in ipairs(extra_balls) do
		extra.ball_data = ball_state.new(
			Vector2.new(current_frontier_x, current_arena_bounds.position.y + current_arena_bounds.size.y / 2.0),
			spawn_velocity(math.random(0, 1))
		)
		extra.frozen_timer = nil
		extra.pending_velocity = nil
		extra.scale = 1.0
	end
	local round_number = match_state.rounds_for(match, 0) + match_state.rounds_for(match, 1) + 1
	round_start_gate = {
		phase = "waiting_for_input",
		phase_timer = 0.0,
		pending_serve_side = pending_serve_side,
		round_number = round_number,
	}
end

-- "deuxieme game contre mon rival, la zone est toujours retrecie, elle
-- devrait revenir a l'origine" (2026-08-22) — shrinking_arena resets to
-- full size every round, not just once at match start.
local function reset_arena_shrink()
	current_arena_bounds = ARENA_BOUNDS
	current_frontier_x = FRONTIER_X
	shrink_step = 0
	shrink_step_timer = 0.0
	shrink_animating = false
	shrink_anim_elapsed = 0.0
end

local function reset_round_twist_state()
	reset_arena_shrink()
	hazards = {}
	orbs = {}
	hazard_spawn_timer = active_twist and active_twist.hazard_spawn_interval or 0.0
	orb_spawn_timer = active_twist and active_twist.orb_spawn_interval or 0.0
	drift_direction = 1.0
end

local function pick_decoy_wander_target()
	local half_extents = Vector2.new(14.0, 28.0)
	local min_x = current_arena_bounds.position.x + half_extents.x
	local max_x = current_arena_bounds.position.x + current_arena_bounds.size.x - half_extents.x
	local min_y = current_arena_bounds.position.y + half_extents.y
	local max_y = current_arena_bounds.position.y + current_arena_bounds.size.y - half_extents.y
	decoy.wander_target = Vector2.new(min_x + math.random() * (max_x - min_x), min_y + math.random() * (max_y - min_y))
	decoy.wander_timer = TWIST_TUNING.DECOY_WANDER_INTERVAL_MIN + math.random() * (TWIST_TUNING.DECOY_WANDER_INTERVAL_MAX - TWIST_TUNING.DECOY_WANDER_INTERVAL_MIN)
end

-- Resets both ships/weapons to a clean state and re-serves toward whoever
-- just lost the round (2026-08-15 convention on the Godot side: the ball
-- serves toward the player who needs the catch-up chance).
local function start_new_round(loser_side)
	players[1] = new_player(0, players[1].character, players[1].controls, players[1].is_ai, players[1].max_hp, players[1].ai_is_mook)
	players[2] = new_player(1, players[2].character, players[2].controls, players[2].is_ai, players[2].max_hp, players[2].ai_is_mook)
	if boss_helpers.is_ship(players[2]) then
		boss_helpers.setup_ship(players[2]) -- reapplies size/hp/kit AND resets boss_helpers.phase to 1 every round (2026-09-12 bug fix: "le boss est toujours en mode dechaine")
	end
	bullets = {} -- `impacts` is left alone so the round-ending hit's own flash still plays out
	beams = {} -- a beam's `player` reference would otherwise go stale (new_player() swaps in a fresh table)
	turrets = {} -- turrets/projectiles/beams don't survive a round boundary (match_arena_node.gd's _clear_round_entities())
	ghost_paddles = {} -- Contrôleur's/Perturbateur's dash
	fire_trails = {} -- Perturbateur's charged Boomerang de Feu puddles
	missile_strikes = {} -- Lourd's Ultra "Pluie de Scuds"
	black_holes = {} -- Contrôleur's Ultra "Trou noir"
	laser_meshes = {} -- Zoneur's Ultra "Grille Laser"
	wind_gusts = {} -- Vif's Ultra "Bourrasque"
	floating_texts = {} -- Epic 4 reward system's "+X" heal popup
	gauge_fill_effects = {} -- ball-miss travel effect (gauge_fill_effect_node.gd)
	heal_fx = {} -- Spreader's cosmetic orbiting-bonbon flourish (passive_heal_fx_node.gd)
	push_pending = false
	feedback_fx.ball_slow_timer = 0.0
	reset_round_twist_state()
	feedback_fx.shake_timer, feedback_fx.shake_duration, feedback_fx.shake_magnitude = 0.0, 0.0, 0.0
	begin_round_ready_gate(loser_side)
end

function match_arena.enter()
	players = {}
	ultra_intro = nil
	pause_state = nil
	post_match_choice_timer = nil
	post_match_choice = nil
	escape_prev = false
	cheat_state.kill_prev, cheat_state.ultra_prev, cheat_state.ammo_prev, cheat_state.ai_toggle_prev = false, false, false, false
	feedback_fx.shake_timer, feedback_fx.shake_duration, feedback_fx.shake_magnitude = 0.0, 0.0, 0.0

	campaign_mode = campaign_context.has_pending_encounter()
	if campaign_mode then
		campaign_encounter = campaign_context.current_encounter()
		campaign_character_id = campaign_context.campaign.character.id
		active_twist = campaign_encounter.twist
		local p2_max_hp = campaign_encounter.is_mook and (ship_state.START_HP * campaign_encounter.mook_hp_multiplier) or ship_state.START_HP
		players[1] = new_player(0, campaign_context.campaign.character, P1_CONTROLS, false)
		players[2] = new_player(1, campaign_encounter.opponent, P2_CONTROLS, true, p2_max_hp, campaign_encounter.is_mook)
		if boss_helpers.is_ship(players[2]) then
			boss_helpers.setup_ship(players[2])
		end
	else
		campaign_encounter = nil
		campaign_character_id = nil
		active_twist = nil
		local p1_character = match_setup.p1_character or mitrailleur
		local p2_character = match_setup.p2_character or mitrailleur
		players[1] = new_player(0, p1_character, P1_CONTROLS, false)
		players[2] = new_player(1, p2_character, P2_CONTROLS, false)
	end

	-- Epic 4 reward system: built ONCE per match (unlike everything else
	-- reset below, which is per-ROUND) — see passive_state's own doc
	-- comment for why.
	passive_state = { build_passive_state(players[1].character), build_passive_state(players[2].character) }

	match = match_state.new()
	bullets = {}
	impacts = {}
	ship_explosion_helpers.bursts = {}
	ship_explosion_helpers.round = nil
	beams = {}
	turrets = {}
	ghost_paddles = {}
	fire_trails = {}
	missile_strikes = {}
	black_holes = {}
	laser_meshes = {}
	wind_gusts = {}
	floating_texts = {}
	gauge_fill_effects = {}
	heal_fx = {}
	push_pending = false
	feedback_fx.ball_slow_timer = 0.0
	reset_round_twist_state()

	decoy = nil
	if active_twist and active_twist.twist_type == "visual_decoy" then
		-- Mimics the AI opponent (always player[2] in campaign mode).
		decoy = { position = players[2].ship.position, color = SIDE_COLOR[1], character_id = players[2].character.id }
		pick_decoy_wander_target()
	end

	-- multi_ball twist (match_arena_node.gd's apply_twist()): spawned once
	-- per encounter, not re-spawned per round (begin_round_ready_gate(),
	-- called below, re-centers these same entries on every round instead —
	-- see its own doc comment). Placeholder position/velocity here; that
	-- same call immediately gives them their real ones.
	extra_balls = {}
	if active_twist and active_twist.twist_type == "multi_ball" then
		for _ = 1, active_twist.ball_count - 1 do
			table.insert(extra_balls, {
				ball_data = ball_state.new(Vector2.new(current_frontier_x, ARENA_CENTER_Y), Vector2.ZERO),
				trail_ps = make_ball_trail_ps(),
			})
		end
	end

	begin_round_ready_gate(math.random(0, 1))
end

local function input_direction(controls, joystick)
	-- Scancode-based (physical key position), not isDown()/KeyConstant
	-- (produced character) — on AZERTY, "z/q" ARE the physical W/A keys, so
	-- this Just Works regardless of the player's keyboard layout. D-pad/
	-- left-stick on `joystick` (this player's own device) OR'd in alongside.
	local x, y = 0.0, 0.0
	if love.keyboard.isScancodeDown(controls.left) or input.direction_down(joystick, "left") then
		x = x - 1.0
	end
	if love.keyboard.isScancodeDown(controls.right) or input.direction_down(joystick, "right") then
		x = x + 1.0
	end
	if love.keyboard.isScancodeDown(controls.up) or input.direction_down(joystick, "up") then
		y = y - 1.0
	end
	if love.keyboard.isScancodeDown(controls.down) or input.direction_down(joystick, "down") then
		y = y + 1.0
	end
	return Vector2.new(x, y)
end

local function ship_rect(ship)
	return ship.position.x - ship.half_extents.x,
		ship.position.y - ship.half_extents.y,
		ship.half_extents.x * 2.0,
		ship.half_extents.y * 2.0
end

-- ball_position defaults to the primary ball's own (every pre-multi_ball
-- call site relied on that implicitly) — pass one explicitly to test an
-- extra ball instead.
local function ball_overlaps_ship(ship, ball_position)
	local bx, by = (ball_position or ball.position).x, (ball_position or ball.position).y
	local left = ship.position.x - ship.half_extents.x - ball_state.RADIUS
	local right = ship.position.x + ship.half_extents.x + ball_state.RADIUS
	local top = ship.position.y - ship.half_extents.y - ball_state.RADIUS
	local bottom = ship.position.y + ship.half_extents.y + ball_state.RADIUS
	return bx >= left and bx <= right and by >= top and by <= bottom
end

local function point_in_ship(ship, point)
	local left = ship.position.x - ship.half_extents.x
	local right = ship.position.x + ship.half_extents.x
	local top = ship.position.y - ship.half_extents.y
	local bottom = ship.position.y + ship.half_extents.y
	return point.x >= left and point.x <= right and point.y >= top and point.y <= bottom
end

-- Per-weapon impact VFX style (see godot_project/nodes/projectile_node.gd's
-- _spawn_weapon_impact_effect() dispatch, ported partially here — only the
-- weapons this port has so far, more styles land as more characters do).
-- Anything unlisted falls back to "spark_ring".
local IMPACT_STYLE_BY_WEAPON = {
	machine_gun = "spark_ring",
	mini_shot = "fan_shatter", -- "l'eventail se decompose... comme un petit feu d'artifice"
	bazooka = "big_explosion", -- "explosion plus grosse, comme sur sa pluie de scud"
	stun_boomerang = "saber_slash", -- "une ligne tres rapide et courte... comme un coup de sabre"
	laser = "laser_spark", -- "juste des mini particules blanches qui popent comme des petits eclairs"
	turret = "spark_ring", -- Camil's own instruction: same impact/code as Mitrailleur
	homing_missile = "spark_ring", -- ditto
	vortex = "vortex_split", -- "le tourbillon se divise en huit et s'eclate dans les 8 directions en fadant"
	ultra_la_meute = "spark_ring", -- same art/impact as the base homing_missile, just bigger/more aggressive
	ultra_pluie_de_bonbons = "fan_shatter", -- same art/impact as the base mini_shot
	-- 2026-09-27 (Camil: "il faudrait un indicateur visuel leger quand le
	-- feu de l'arme chargee touche le vaisseau [ou] une tourelle ennemie")
	-- — Perturbateur's charged Boomerang de Feu puddle never flashed
	-- anything on its own damage ticks; reuses the same small ring as a
	-- normal machine_gun hit, deliberately NOT the boomerang's own bigger
	-- saber_slash (that's reserved for a direct boomerang hit).
	fire_trail_tick = "spark_ring",
	-- 2026-10-05 (playtest: "on voit rien pour le flash [de retour de
	-- balle]") — the generic small spark_ring (shared with every machine_
	-- gun hit) wasn't bold enough on its own; this is its own dedicated,
	-- much bigger/bolder style (see spawn_impact()/the draw loop's own
	-- "bounce_flash" branch).
	paddle_bounce = "bounce_flash",
}

-- Params for the ring-style impacts (everything except fan_shatter/
-- saber_slash/big_explosion, which need their own shape — see
-- spawn_impact()).
local RING_IMPACT_PARAMS = {
	spark_ring = { duration = 0.15, radius = 14.0, color = { 1.0, 0.9, 0.5 } },
}

-- 2026-09-27 (Camil: "remplacer les explosions des scuds de lourd par une
-- explosion avec particules" — then, after playtesting the Y-based
-- version below misfired right next to the SHOOTER's own ship whenever
-- both ships happened to share a similar height, and just as often flew
-- clean past the target without ever exploding — "le missile doit
-- exploser quand il arrive a la meme position verticale [horizontale,
-- illustre par une capture d'ecran montrant une colonne vertale de points
-- de declenchement, tous a la MEME position X que la cible, sur toute la
-- hauteur] du vaisseau ennemi (uniquement)") — the missile now detonates
-- the instant it reaches the ENEMY'S OWN DEPTH (its X), at whatever
-- height it currently is, instead of waiting for its own Y to happen to
-- match the target's Y. Radius bumped to x2 (was x1.5), duration to 0.5s,
-- and applies to BOTH Lourd's normal shot and his charged burst now.
local BIG_EXPLOSION_RADIUS = 32.0 * 2.0
local BIG_EXPLOSION_DURATION = 0.5

-- Same "tight tolerance + same-frame crossing" idea as the earlier Y-based
-- attempt, just on the X axis: a bullet's X moves (near-)monotonically
-- toward the opponent's side, so this reliably fires exactly once, right
-- as the missile reaches the target's own depth, regardless of the
-- missile's current height — see update_bullets()'s bazooka branch.
local BAZOOKA_X_ALIGNMENT_TOLERANCE = 5.0
local function x_aligned(before_x, after_x, target_x)
	if math.abs(after_x - target_x) <= BAZOOKA_X_ALIGNMENT_TOLERANCE then
		return true
	end
	return (before_x - target_x >= 0.0) ~= (after_x - target_x >= 0.0)
end

-- projectile_factory.gd's own weapon_tint() — used for the campaign
-- reward-reveal icon swatch (see the match_over draw block), not the
-- bullets themselves (BULLET_VISUALS below has its own, different colors
-- for those). Anything unlisted defaults to white, matching Godot's own
-- fallback.
local WEAPON_TINT = {
	stun_boomerang = { 0.6, 0.8, 1.0 },
	homing_missile = { 1.0, 0.6, 0.2 },
	ultra_la_meute = { 1.0, 0.6, 0.2 },
	laser = { 0.4, 1.0, 0.5 },
	mini_shot = { 1.0, 1.0, 0.4 },
	ultra_pluie_de_bonbons = { 1.0, 1.0, 0.4 },
}

-- Per-weapon bullet visuals. `radius` still drives nothing but the old
-- placeholder fallback (kept for any weapon id missing real art); the real
-- draw uses assets.bullets + `scale`, matching ProjectileNode's own
-- per-weapon visual_scale (projectile_factory.gd) — an engine-side size
-- knob independent of the hit-test geometry.
-- 2026-10-05 "tout plus gros" pass: every `.scale` x1.5 (the actual visual
-- size driver — see the doc comment above; `.radius`, the unused
-- placeholder fallback, is left alone).
local BULLET_VISUALS = {
	machine_gun = { radius = 3.0, color = { 1.0, 1.0, 0.6 }, scale = 1.4 * 1.5 },
	mini_shot = { radius = 4.0, color = { 1.0, 1.0, 0.4 }, scale = 1.0 * 1.5 },
	bazooka = { radius = 7.0, color = { 1.0, 0.6, 0.2 }, scale = 1.4 * 1.5 },
	stun_boomerang = { radius = 6.0, color = { 0.6, 0.85, 1.0 }, scale = 1.4 * 1.5 },
	turret = { radius = 3.5, color = { 0.6, 0.95, 0.6 }, scale = 1.0 * 1.5 },
	homing_missile = { radius = 5.0, color = { 1.0, 0.6, 0.2 }, scale = 0.8 * 1.5 },
	vortex = { radius = 5.0, color = { 0.7, 0.9, 1.0 }, scale = 2.4 * 1.5 },
	-- Ultra weapons: base weapon's own scale * WeaponData.visual_scale_
	-- multiplier (homing_missile 0.8*2.0, mini_shot 1.0*1.4) — the one place
	-- this port reads that field, since every base weapon's own multiplier
	-- is already baked into its hand-picked scale above.
	ultra_la_meute = { radius = 5.0, color = { 1.0, 0.6, 0.2 }, scale = 1.6 * 1.5 },
	ultra_pluie_de_bonbons = { radius = 4.0, color = { 1.0, 1.0, 0.4 }, scale = 1.4 * 1.5 },
}

-- Weapon ids whose art is side-specific (assets.bullets[id][0 or 1])
-- rather than a single shared image.
local SIDE_SPLIT_BULLET_WEAPONS = { machine_gun = true, turret = true }

-- `owner_side`/`damage` are only used by the "big_explosion" style (Lourd's
-- normal AND charged bazooka shots, see update_bullets()): they let the
-- explosion's own flying fragments deal damage to whichever ship touches
-- one, over the explosion's whole lifetime (see update_impacts()). Every
-- other caller (every other weapon, plus Lourd's Ultra "Pluie de Scuds"
-- impact flash, which already deals its own damage through a separate,
-- unrelated mechanic) omits them, leaving the explosion purely cosmetic.
local function spawn_impact(position, weapon_id, owner_side, damage)
	local style = IMPACT_STYLE_BY_WEAPON[weapon_id] or "spark_ring"
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
		-- saber_slash_node.gd: a FIXED corner-to-corner diagonal across the
		-- target's own bounding box (2026-09-14 fix — this used to draw a
		-- random angle every hit, which Godot's own version never does).
		impact.duration = 0.15
	elseif style == "laser_spark" then
		impact.duration = 0.15
		impact.particles = {}
		for _ = 1, 5 do
			local angle = math.random() * math.pi * 2.0
			local speed = 40.0 + math.random() * 50.0
			table.insert(impact.particles, Vector2.new(math.cos(angle) * speed, math.sin(angle) * speed))
		end
	elseif style == "vortex_split" then
		-- "le tourbillon se divise en huit et s'eclate dans les 8
		-- directions en fadant, tres rapide (1/4 de s)" — FIXED 45deg
		-- increments, not random like fan_shatter/laser_spark.
		impact.duration = 0.25
		impact.particles = {}
		for i = 0, 7 do
			local angle = mathx.deg_to_rad(45.0 * i)
			table.insert(impact.particles, Vector2.new(math.cos(angle) * 90.0, math.sin(angle) * 90.0))
		end
	elseif style == "big_explosion" then
		impact.duration = BIG_EXPLOSION_DURATION
		impact.radius = BIG_EXPLOSION_RADIUS
		impact.owner_side = owner_side
		impact.damage = damage
		impact.hit_sides = {} -- which player side(s) this explosion has already damaged (once each, not once per fragment)
		impact.particles = {}
		for _ = 1, 14 do
			local angle = math.random() * math.pi * 2.0
			local speed = (impact.radius / impact.duration) * (0.5 + math.random() * 0.6)
			table.insert(impact.particles, Vector2.new(math.cos(angle) * speed, math.sin(angle) * speed))
		end
	elseif style == "bounce_flash" then
		-- A big bold filled white pop — deliberately crude/unmissable, not a
		-- thin fading outline like spark_ring (that one read as invisible
		-- against a busy paddle-edge of the arena).
		impact.duration = 0.2
		impact.radius = 36.0
	else
		local params = RING_IMPACT_PARAMS[style] or RING_IMPACT_PARAMS.spark_ring
		impact.duration = params.duration
		impact.radius = params.radius
		impact.color = params.color
	end
	table.insert(impacts, impact)
end

-- Perturbateur's charged Boomerang de Feu puddle (fire_trail_node.gd): a
-- stationary damage-over-time hazard using a real love.graphics.
-- ParticleSystem (LÖVE's native equivalent of Godot's CPUParticles2D) for
-- the flame look — a small rising, warm-to-ember color ramp, continuously
-- emitting until the puddle enters its own fade-out window.
local function make_fire_particle_system()
	local ps = love.graphics.newParticleSystem(assets.fire_particle, 32)
	ps:setParticleLifetime(0.35, 0.55)
	ps:setEmissionRate(14.0 / 0.55) -- ~= CPUParticles2D's amount=14 over lifetime=0.55, continuous
	ps:setEmissionArea("ellipse", FIRE_TRAIL.RADIUS * 0.7, FIRE_TRAIL.RADIUS * 0.7)
	ps:setDirection(-math.pi / 2.0) -- up
	ps:setSpread(mathx.deg_to_rad(45.0))
	ps:setSpeed(20.0, 55.0)
	ps:setLinearAcceleration(0.0, -50.0, 0.0, -50.0) -- flames rise
	ps:setSizes(2.4, 1.1) -- shrinks as each particle rises and fades
	ps:setSizeVariation(0.4)
	ps:setColors(
		1.0, 0.98, 0.75, 1.0, -- near-white-hot core
		1.0, 0.7, 0.15, 1.0, -- yellow-orange body
		1.0, 0.35, 0.05, 0.85, -- deep orange-red
		0.6, 0.05, 0.0, 0.0 -- dies to transparent ember-red
	)
	ps:start()
	return ps
end

-- Ball's own "etoile filante" trail (ball_node.gd, 2026-09-06, Camil: "on
-- pourrait avoir quelques petites particules derriere la balle pour bien
-- la distinguer, qui ferait un peu 'etoile filante'"). Built once — unlike
-- fire_trails (one puddle per boomerang tick), there's only ever one ball,
-- so one persistent ParticleSystem repositioned every frame is simpler
-- than spawning/despawning one per round. setPosition() (not drawing at
-- the ball's own x/y) is what makes already-emitted particles stay put in
-- world space while the emitter itself keeps moving — Godot's
-- `local_coords = false` on a moving CPUParticles2D emitter.
local BALL_TRAIL_EMISSION_RATE = 40.0 / 0.35

-- Factored out so the multi_ball twist's extra balls (extra_balls' own doc
-- comment) can each get their own real trail instead of going without —
-- 2026-09-14, Camil: "Go" on that simplification once it was flagged.
make_ball_trail_ps = function()
	local ps = love.graphics.newParticleSystem(assets.fire_particle, 40)
	ps:setParticleLifetime(0.35)
	ps:setSpread(mathx.deg_to_rad(10.0))
	ps:setSpeed(35.0, 70.0)
	-- ball_node.gd's own taper Curve keyframes are (0.0->1.0, 0.5->1.0,
	-- 1.0->0.4) applied on TOP OF a random per-particle base scale
	-- (scale_amount_min/max = 0.7/1.6, center ~1.15) — LÖVE's setSizes()
	-- (a curve) + setSizeVariation() (a random per-particle multiplier on
	-- that whole curve) is structurally the same two-part model, just
	-- centered on 1.15 instead of 1.3 to land on that same midpoint.
	ps:setSizes(1.15, 1.15, 0.46) -- stays big for the first half of its life, only narrows for the back half (0.46/1.15 ~= Godot's own 0.4/1.0 taper ratio)
	ps:setSizeVariation(0.39) -- matches (1.6-0.7)/(2*1.15) — half-spread of Godot's own 0.7-1.6 random base range around its 1.15 center
	ps:setColors(
		1.0, 1.0, 0.9, 1.0, -- white-hot spark
		0.6, 0.54, 0.24, 0.9, -- yellow, dimmed
		0.6, 0.51, 0.18, 0.0 -- fades to transparent gold
	)
	ps:setEmissionRate(0.0) -- armed live each frame in match_arena.update() — see there for why (no trail while frozen/serving)
	ps:start()
	return ps
end

local ball_trail_ps = make_ball_trail_ps()

-- Ship explosion (match_arena_node.gd's _spawn_ship_debris_burst()/
-- _spawn_ship_disintegration_chunks(), 2026-09-12): a fire/spark burst plus
-- squarish tumbling hull chunks in the loser's own team color, both a
-- one-shot ParticleSystem emitted all at once (LÖVE's equivalent of
-- CPUParticles2D's one_shot=true/explosiveness=1.0) then left to age out.
-- (ship_explosion_helpers itself — constants + .round/.bursts state — is
-- declared further up, before apply_damage_and_check_round/enter() need
-- it; these are just its remaining functions.)

function ship_explosion_helpers.spawn_debris_burst(position, intensity)
	local ps = love.graphics.newParticleSystem(assets.fire_particle, 32)
	ps:setParticleLifetime(ship_explosion_helpers.DEBRIS_LIFETIME)
	ps:setDirection(0.0)
	ps:setSpread(math.pi * 2.0) -- 360° — Godot's spread=180 either side of Vector2.RIGHT is the same full circle
	ps:setSpeed(40.0 * intensity, 120.0 * intensity)
	ps:setSizes(2.2 * intensity)
	ps:setSizeVariation(0.4)
	ps:setColors(
		1.0, 0.7, 0.2, 1.0,
		0.5, 0.1, 0.05, 0.0
	)
	ps:setPosition(position.x, position.y)
	ps:emit(math.floor(14 * intensity))
	table.insert(ship_explosion_helpers.bursts, { particle_system = ps, age = 0.0, duration = ship_explosion_helpers.DEBRIS_LIFETIME })
end

function ship_explosion_helpers.spawn_disintegration_chunks(position, side)
	local ps = love.graphics.newParticleSystem(assets.fire_particle, 10)
	ps:setParticleLifetime(ship_explosion_helpers.DISINTEGRATION_LIFETIME)
	ps:setDirection(0.0)
	ps:setSpread(math.pi * 2.0)
	ps:setSpeed(60.0, 150.0)
	ps:setLinearAcceleration(0.0, 40.0, 0.0, 80.0) -- gravity, mirrors Godot's Vector2(0.0, 60.0)
	ps:setSpin(mathx.deg_to_rad(-540.0), mathx.deg_to_rad(540.0)) -- tumbling, matches angular_velocity_min/max
	ps:setSizes(2.4)
	ps:setSizeVariation(0.4)
	local color = SIDE_COLOR[side]
	ps:setColors(
		color[1], color[2], color[3], 1.0,
		color[1] * 0.4, color[2] * 0.4, color[3] * 0.4, 0.0
	)
	ps:setPosition(position.x, position.y)
	ps:emit(10)
	table.insert(ship_explosion_helpers.bursts, { particle_system = ps, age = 0.0, duration = ship_explosion_helpers.DISINTEGRATION_LIFETIME })
end

function ship_explosion_helpers.update_bursts(dt)
	local i = 1
	while i <= #ship_explosion_helpers.bursts do
		local burst = ship_explosion_helpers.bursts[i]
		burst.particle_system:update(dt)
		burst.age = burst.age + dt
		if burst.age >= burst.duration then
			table.remove(ship_explosion_helpers.bursts, i)
		else
			i = i + 1
		end
	end
end

local function spawn_fire_trail(position, victim_player, owner_side)
	table.insert(fire_trails, {
		position = position,
		victim = victim_player,
		owner_side = owner_side,
		lifetime = FIRE_TRAIL.LIFETIME,
		tick_cooldown = 0.0,
		fading = false,
		particle_system = make_fire_particle_system(),
	})
end

local VORTEX_WEAPON_FRAME_DURATION = 0.12 -- matches Bourrasque's own UT.BOURRASQUE_VORTEX_FRAME_DURATION

-- Straight toward the opponent's side. Mirrors match_arena_node.gd's
-- _on_weapon_fired(): projectile_count > 1 fans a burst evenly across
-- burst_spread_deg (optionally staggered by burst_stagger); count <= 1
-- fires a single shot with a small random jitter (spread_deg) instead —
-- weapon fire in this game is never player-aimed, only the ball-return is.
-- The extra params (all optional, mirroring _spawn_projectile()'s own)
-- exist for charged fire and Mitrailleur's double-fire buff: speed_
-- multiplier/position_offset/damage_multiplier/size_multiplier scale the
-- shot, boomerang_out_duration_override picks a different outbound arc
-- length (Perturbateur's charged throw) than the weapon's normal one.
local function spawn_projectile(player, weapon, angle_offset_deg, speed_multiplier, position_offset, boomerang_out_duration_override, damage_multiplier, size_multiplier)
	speed_multiplier = speed_multiplier or 1.0
	position_offset = position_offset or Vector2.ZERO
	boomerang_out_duration_override = boomerang_out_duration_override or 0.0
	damage_multiplier = damage_multiplier or 1.0
	size_multiplier = size_multiplier or 1.0

	local direction = player.side == 0 and 1.0 or -1.0
	local velocity = Vector2.new(direction * weapon.projectile_speed * speed_multiplier, 0.0):rotated(mathx.deg_to_rad(angle_offset_deg))
	local base_scale = (BULLET_VISUALS[weapon.id] or BULLET_VISUALS.machine_gun).scale
	local bullet = {
		position = player.ship.position + position_offset,
		velocity = velocity,
		owner_side = player.side,
		damage = weapon.damage * damage_multiplier,
		weapon_id = weapon.id,
		homing_strength = weapon.homing_strength,
		visual_scale = base_scale * size_multiplier,
		-- Perturbateur's charged Boomerang de Feu (projectile_factory.gd,
		-- 2026-08-17): the CHARGED stun_boomerang release specifically
		-- (identified the same way Godot does — a real
		-- boomerang_out_duration_override, only ever passed by the charged
		-- dispatch) also drags a damaging fire trail behind it.
		leaves_fire_trail = weapon.id == "stun_boomerang" and boomerang_out_duration_override > 0.0,
		fire_trail_timer = FIRE_TRAIL.DROP_INTERVAL,
		-- Traqueur's Ultra "La Meute" (projectile_factory.gd, same hardcoded
		-- weapon-id check): true 2D pursuit — the WHOLE velocity vector turns
		-- toward the target, not just vertical steering.
		homing_full_turn = weapon.id == "ultra_la_meute",
		-- 2026-09-16 (Camil: "les eventails de spreaders devraient tourner")
		-- — WeaponData.projectile_spin_speed (mini_shot/ultra_pluie_de_bonbons
		-- = 900, stun_boomerang = 720) was never read anywhere in this port;
		-- see update_bullets()'s own rotation tick and the draw loop's
		-- `bullet.rotation` use below.
		spin_speed = weapon.projectile_spin_speed,
		rotation = 0.0,
	}
	if weapon.id == "vortex" then
		-- Camil: "les tourbillons de vif devraient faire 1 - 2 avec le
		-- sprite wind1 et wind3" — reuses the exact same generic flipbook
		-- mechanism Bourrasque's 3-frame swarm already has (see
		-- update_bullets()'s `if bullet.anim_textures` tick and the draw
		-- loop's own check), just with vortex_weapon_frames' 2 frames.
		bullet.anim_textures = assets.vortex_weapon_frames
		bullet.anim_frame_index = 1
		bullet.anim_frame_timer = VORTEX_WEAPON_FRAME_DURATION
		bullet.anim_frame_duration = VORTEX_WEAPON_FRAME_DURATION
	end
	if weapon.is_boomerang then
		bullet.is_boomerang = true
		bullet.shooter_player = player
		bullet.boomerang_base_velocity = velocity
		-- "Si je descends, ca part du bas (-30 -> 30). Si je monte [ou neutre],
		-- ca part du haut (30 -> -30)" — the shooter's own last held movement
		-- direction picks which end of the arc it starts from.
		if player.last_move_direction.y > 0.01 then
			bullet.boomerang_start_deg = BOOMERANG.ARC_ANGLE_DEG
			bullet.boomerang_end_deg = -BOOMERANG.ARC_ANGLE_DEG
		else
			bullet.boomerang_start_deg = -BOOMERANG.ARC_ANGLE_DEG
			bullet.boomerang_end_deg = BOOMERANG.ARC_ANGLE_DEG
		end
		-- Layered fallback mirrors WeaponData's own doc comment: an explicit
		-- override (the charged throw's own duration) wins, else the
		-- weapon's normal boomerang_out_duration, else the hardcoded default.
		if boomerang_out_duration_override > 0.0 then
			bullet.boomerang_out_duration = boomerang_out_duration_override
		elseif weapon.boomerang_out_duration > 0.0 then
			bullet.boomerang_out_duration = weapon.boomerang_out_duration
		else
			bullet.boomerang_out_duration = BOOMERANG.DEFAULT_OUT_DURATION
		end
		bullet.boomerang_timer = 0.0
		bullet.boomerang_returning = false
		bullet.boomerang_return_closest_dist = math.huge
		bullet.boomerang_missed_catch = false
		bullet.boomerang_hit_outbound = false
		bullet.boomerang_hit_return = false
		-- 2026-09-27 (Camil: "j'ai l'impression que l'arme de Perturbateur
		-- ne touche pas les tourelles") — separate per-leg gate from the
		-- ship's own, so a boomerang passing over BOTH an enemy turret and
		-- the enemy ship on the same leg can land both hits (see
		-- update_bullets()'s is_boomerang branch).
		bullet.boomerang_turret_hit_outbound = false
		bullet.boomerang_turret_hit_return = false
	end
	if weapon.is_sine then
		-- Vif's Tourbillon: a straight-line net trajectory (the base
		-- velocity captured right here at spawn, exactly as thrown) with a
		-- lateral wave riding on top — see update_bullets() for the actual
		-- per-frame velocity recompute.
		bullet.is_sine = true
		bullet.drift_velocity = velocity
		bullet.sine_elapsed = 0.0
		bullet.sine_amplitude = weapon.sine_amplitude
		bullet.sine_angular_speed = weapon.sine_angular_speed
	end
	table.insert(bullets, bullet)
end

local function fire_weapon_shots(player, weapon)
	-- Mitrailleur's charged-fire buff (2026-08-09): "les 10 missiles suivants
	-- seront doubles (paralleles, separes de 10px verticalement)" — consumed
	-- one at a time, bypasses the normal single/burst path entirely.
	if player.double_fire_shots_remaining > 0 then
		player.double_fire_shots_remaining = player.double_fire_shots_remaining - 1
		local half_offset = weapon.charged_double_fire_offset / 2.0
		spawn_projectile(player, weapon, 0.0, 1.0, Vector2.new(0.0, -half_offset))
		spawn_projectile(player, weapon, 0.0, 1.0, Vector2.new(0.0, half_offset))
		return
	end
	if weapon.projectile_count <= 1 then
		local jitter = weapon.is_heavy and 0.0 or (math.random() * 2.0 - 1.0) * weapon.spread_deg
		spawn_projectile(player, weapon, jitter)
		return
	end
	for i = 0, weapon.projectile_count - 1 do
		local t = i / math.max(weapon.projectile_count - 1, 1)
		local angle_offset = -weapon.burst_spread_deg / 2.0 + weapon.burst_spread_deg * t
		if weapon.burst_stagger > 0.0 and i > 0 then
			-- Captures `side`, not `player`, and re-resolves it from `players`
			-- when the callback actually fires — a round reset replaces the
			-- player table (new_player()) with a fresh one, so a still-pending
			-- staggered shot must spawn from whoever occupies that side NOW,
			-- not a stale pre-reset table.
			local side = player.side
			timer.after(i * weapon.burst_stagger, function()
				spawn_projectile(players[side + 1], weapon, angle_offset)
			end)
		else
			spawn_projectile(player, weapon, angle_offset)
		end
	end
end

-- Zoneur's beam: a self-contained timed hitscan ray, not a projectile —
-- see BEAM_* constants and update_beams()/draw() for the rest of it.
-- duration/thickness_multiplier default to the weapon's own normal-fire
-- fields; the charged release passes its own charged_beam_* values instead.
local function spawn_beam(player, weapon, duration, thickness_multiplier)
	duration = duration or weapon.beam_duration
	thickness_multiplier = thickness_multiplier or weapon.beam_thickness_multiplier
	table.insert(beams, {
		player = player,
		weapon_id = weapon.id,
		elapsed = 0.0,
		lifetime = duration,
		thickness = BEAM.BASE_THICKNESS * thickness_multiplier,
		range = weapon.beam_range,
		damage_per_second = weapon.damage,
		hit_timer = 0.0,
	})
end

-- Controleur's turret: placed at the shooter's CURRENT position (not
-- following them afterward — that's only the Mitrailleur-Ultra satellite
-- variant, not ported here), fires autonomously at the opponent on its own
-- cooldown until its lifetime runs out or it's shot down. is_charged
-- (2026-08-10): "pose une tourelle ephemere, qui tire 4x plus vite, mais ne
-- dure que 5 secondes" — faster fire rate, shorter (overridable) lifetime,
-- the gold turret_charged.png sprite instead of the normal one.
local function spawn_turret(player, weapon, is_charged, lifetime_override)
	local fire_rate = weapon.fire_rate * (is_charged and weapon.charged_turret_fire_rate_multiplier or 1.0)
	local lifetime = weapon.turret_lifetime
	if is_charged and weapon.charged_turret_lifetime > 0.0 then
		lifetime = weapon.charged_turret_lifetime
	elseif lifetime_override and lifetime_override > 0.0 then
		-- Epic 4 reward system: Contrôleur's own turret unlock ("dure 6s",
		-- distinct from the normal 25s and the charged 5s).
		lifetime = lifetime_override
	end
	table.insert(turrets, {
		position = player.ship.position,
		half_extents = TURRET.HALF_EXTENTS,
		owner_side = player.side,
		weapon_id = weapon.id,
		damage = weapon.damage,
		hp = weapon.turret_hp,
		lifetime_left = lifetime,
		fire_cooldown_period = 1.0 / fire_rate,
		fire_cooldown = 1.0 / fire_rate,
		bounce_cooldown = 0.0, -- ball-deflection re-entry guard, mirrors ship_state's own dedup via velocity-direction gating
		flash_timer = 0.0,
		is_charged = is_charged or false,
		autofire = true, -- Mitrailleur's Ultra satellites are the only turrets that override this to false
	})
end

-- Charged fire's own dispatch (ship_node.gd's _on_charged_weapon_fired()):
-- mirrors fire_weapon_shots()'s burst shape but reads the charged_* fields
-- instead, so any weapon's charged release can be a different pattern
-- purely via data — a wider fan, a single empowered shot, a self-buff with
-- no projectile at all, ...
local function fire_charged_weapon_shots(player, weapon)
	if weapon.effect_type == "turret" then
		-- Controleur (2026-08-10): "pose une tourelle ephemere, qui tire 4x
		-- plus vite, mais ne dure que 5 secondes".
		spawn_turret(player, weapon, true)
		return
	end
	if weapon.effect_type == "beam" then
		local duration = weapon.charged_beam_duration > 0.0 and weapon.charged_beam_duration or weapon.beam_duration
		spawn_beam(player, weapon, duration, weapon.charged_beam_thickness_multiplier)
		-- 2026-08-10: "le gros laser est TRES puissant... reduire la vitesse
		-- a 60% le temps du gros laser" — shooter self-slow for the beam's
		-- whole lifetime, so it can't keep perfectly tracking a dodger.
		if weapon.charged_beam_shooter_slow_multiplier < 1.0 then
			player.charged_beam_slow_timer = duration
			player.charged_beam_slow_multiplier = weapon.charged_beam_shooter_slow_multiplier
		end
		return
	end
	if weapon.charged_double_fire_shots > 0 then
		-- Mitrailleur: a pure self-buff, no projectile at all — consumed by
		-- fire_weapon_shots() on subsequent NORMAL shots.
		player.double_fire_shots_remaining = weapon.charged_double_fire_shots
		return
	end
	if weapon.charged_projectile_count <= 1 then
		-- Perturbateur (2026-08-10): "plus on charge, plus le boomerang va
		-- loin". "Tir charge: un enorme boomerang (5 fois la taille, 5x
		-- degats)" — charged_damage_multiplier/charged_visual_scale_multiplier
		-- default to 1.0 for every other weapon, so this only changes
		-- anything for the boomerang.
		spawn_projectile(player, weapon, 0.0, weapon.charged_speed_multiplier, Vector2.ZERO, weapon.charged_boomerang_out_duration, weapon.charged_damage_multiplier, weapon.charged_visual_scale_multiplier)
		return
	end
	for i = 0, weapon.charged_projectile_count - 1 do
		local p = i / math.max(weapon.charged_projectile_count - 1, 1)
		-- Spreader (2026-08-09): "balayer de haut en bas puis remonter de bas
		-- en haut" — a triangle wave instead of the usual one-way sweep.
		local t = weapon.charged_burst_ping_pong and (1.0 - math.abs(2.0 * p - 1.0)) or p
		local angle_offset = mathx.lerp(-weapon.charged_burst_spread_deg / 2.0, weapon.charged_burst_spread_deg / 2.0, t)
		if weapon.charged_stagger > 0.0 and i > 0 then
			local side = player.side
			timer.after(i * weapon.charged_stagger, function()
				spawn_projectile(players[side + 1], weapon, angle_offset, weapon.charged_speed_multiplier, Vector2.ZERO, 0.0, weapon.charged_damage_multiplier, weapon.charged_visual_scale_multiplier)
			end)
		else
			spawn_projectile(player, weapon, angle_offset, weapon.charged_speed_multiplier, Vector2.ZERO, 0.0, weapon.charged_damage_multiplier, weapon.charged_visual_scale_multiplier)
		end
	end
end

-- Mitrailleur's Ultra "Mitrailleuses Satellites": echoes a real normal-
-- looking shot (his own machine_gun sprite/damage, via the same
-- spawn_projectile() every normal press uses) from each LIVE satellite's
-- current position, on both a normal AND a charged fire (ship_node.gd:
-- "si on est en ultra + tir charge, il faut bien les tirs sur les modules
-- + les 2 tirs classiques du tir chargee"). A no-op for anyone who hasn't
-- cast the Ultra (satellite_turrets stays nil) or whose satellites have
-- since expired.
local function echo_to_satellites(player, weapon)
	if not player.satellite_turrets then
		return
	end
	local any_alive = false
	for _, satellite in ipairs(player.satellite_turrets) do
		for _, live in ipairs(turrets) do
			if live == satellite then
				any_alive = true
				break
			end
		end
		if any_alive then
			break
		end
	end
	if not any_alive then
		return
	end
	for _, satellite in ipairs(player.satellite_turrets) do
		spawn_projectile(player, weapon, 0.0, 1.0, satellite.follow_offset)
	end
end

local function try_fire(player)
	local result = weapon_system_state.fired(player.weapon)
	player.weapon = result.state
	if not result.fired then
		return
	end
	local weapon = result.weapon
	if weapon.is_heavy then
		player.vulnerability_timer = SHIP_FEEL.VULNERABILITY_DURATION -- Story 1.8
	end
	if weapon.fire_recoil_speed_boost > 0.0 then
		player.fire_recoil_timer = weapon.fire_recoil_boost_decay_time -- resets the window rather than stacking
	end
	if weapon.effect_type == "turret" then
		spawn_turret(player, weapon)
	elseif weapon.effect_type == "beam" then
		spawn_beam(player, weapon)
	else
		fire_weapon_shots(player, weapon)
	end
	echo_to_satellites(player, weapon)

	-- Epic boss "plusieurs armes en meme temps" (match_arena_node.gd's
	-- ship_node.gd _process_fire()): from phase 2/3 onward, extra kit slots
	-- fire for free riding this SAME successful-fire edge — the whole
	-- barrage still obeys the selected weapon's own cooldown pace, just not
	-- each extra gun's individual gauge/cooldown. Turret/beam dispatch same
	-- as the selected weapon's own; no vulnerability/recoil/satellite-echo
	-- side effects (those are tied to the ship's own single fire event).
	for _, extra_index in ipairs(player.boss_simultaneous_fire_indices) do
		if extra_index ~= player.weapon.selected_index then
			local extra_weapon = player.weapon.kit[extra_index + 1]
			if extra_weapon then
				if extra_weapon.effect_type == "turret" then
					spawn_turret(player, extra_weapon)
				elseif extra_weapon.effect_type == "beam" then
					spawn_beam(player, extra_weapon)
				else
					fire_weapon_shots(player, extra_weapon)
				end
			end
		end
	end
end

-- Charged fire's release: goes through the exact same weapon_state.fired()
-- gate as a normal shot (same cooldown/gauge cost — holding only changes
-- WHEN it fires, not what it costs), then dispatches the empowered variant.
local function try_charged_fire(player)
	local result = weapon_system_state.fired(player.weapon)
	player.weapon = result.state
	if not result.fired then
		return
	end
	if result.weapon.fire_recoil_speed_boost > 0.0 then
		player.fire_recoil_timer = result.weapon.fire_recoil_boost_decay_time
	end
	fire_charged_weapon_shots(player, result.weapon)
	echo_to_satellites(player, result.weapon)
end

-- Speed multiplier stacking order copied exactly from ship_node.gd's own
-- _process_movement() (the slows apply via min(), the recoil boost wins
-- over all of them via max() — see its own inline comment on why):
-- lift charge -> charge-fire slow -> vulnerability -> charged-beam slow ->
-- fire-held slow -> fire-recoil boost. (SHIP_FEEL.LIFT_CHARGE_MOVE_MULTIPLIER/
-- SHIP_FEEL.FIRE_HOLD_SPEED_MULTIPLIER/SHIP_FEEL.AI_TRACKING_DEADZONE now live on SHIP_FEEL,
-- declared near the top of the file alongside the rest of that group.)

-- Forward-declared: update_player_input() (below) needs to call this on an
-- Ultra trigger, but its actual body reads apply_damage_and_check_round()
-- and opponent_of(), both defined further down this file — assigned once
-- they exist, right after apply_damage_and_check_round().
local resolve_ultra_effect

-- Forward-declared for the same reason: update_player_input() arms the
-- Ultra intro on a successful trigger (ultra_intro_node.gd's slide-in/hold/
-- slide-out beat), but the actual effect only resolves once that intro
-- finishes — see update_ultra_intro()'s own assignment further down.
local start_ultra_intro

-- Every real-AI function below, grouped into one table (not 8 top-level
-- locals — the 200-local ceiling, same reason as boss_helpers/ultra_helpers).
local ai_helpers = {}

-- ship_node.gd's _ai_find_enemy_turret(): the first live turret NOT owned
-- by `side` (normally at most one enemy turret exists at a time).
function ai_helpers.find_enemy_turret(side)
	for _, turret in ipairs(turrets) do
		if turret.owner_side ~= side then
			return turret
		end
	end
	return nil
end

-- ship_node.gd's _ai_dodge_direction() — Priority 2 ("esquiver les tirs"):
-- scans every live bullet aimed at this player (owner_side ~= player.side
-- — every projectile in a real 2-ship match targets the opponent, same as
-- ProjectileNode.target always being the opponent ship) and, if the
-- closest one is both near and roughly Y-aligned, returns a vertical nudge
-- away from it. Widens as `defensiveness` rises ("moins elle a de PV, plus
-- elle va essayer de securiser"). Returns 0.0 when nothing's worth
-- reacting to (the common case, most frames).
function ai_helpers.dodge_direction(player, defensiveness)
	local detect_range = AI_TUNING.DODGE_DETECT_RANGE * mathx.lerp(1.0, 1.6, defensiveness)
	local margin = AI_TUNING.DODGE_MARGIN * mathx.lerp(1.0, 1.8, defensiveness)
	local closest, closest_dist = nil, math.huge
	for _, bullet in ipairs(bullets) do
		if bullet.owner_side ~= player.side then
			local dist = bullet.position:distance_to(player.ship.position)
			if dist < detect_range and dist < closest_dist then
				closest, closest_dist = bullet, dist
			end
		end
	end
	if not closest then
		return 0.0
	end
	-- A homing projectile actively re-aims at wherever this ship moves, so
	-- the flat margin a straight shot uses isn't enough warning — react
	-- earlier/wider, or the AI only starts dodging once already too close
	-- to shake something that curves right back onto it.
	local effective_margin = (closest.homing_strength and closest.homing_strength > 0.0) and margin * 1.6 or margin
	if math.abs(closest.position.y - player.ship.position.y) > effective_margin then
		return 0.0 -- not actually lined up with me — no need to react
	end
	return closest.position.y < player.ship.position.y and 1.0 or -1.0
end

-- ship_node.gd's _ai_ball_time_to_arrival(): a real intercept estimate
-- (distance / closing speed) for the ball-Y prediction below, instead of a
-- flat fixed nudge — only meaningful while the ball is actually heading
-- toward this ship's own wall; falls back to a short base nudge otherwise
-- (moving away, or barely moving horizontally at all).
function ai_helpers.ball_time_to_arrival(player)
	local velocity_x = ball.velocity.x
	local moving_toward_my_wall = player.side == 1 and velocity_x > 0.0 or (player.side == 0 and velocity_x < 0.0)
	if not moving_toward_my_wall or math.abs(velocity_x) < 10.0 then
		return 0.15
	end
	local dx = math.abs(ball.position.x - player.ship.position.x)
	return mathx.clampf(dx / math.abs(velocity_x), 0.0, AI_TUNING.MAX_LOOKAHEAD)
end

-- ship_node.gd's _ai_update_wander(): periodically picks a new "idle" y
-- target, so the AI keeps some independent motion instead of purely
-- mirroring the ball.
function ai_helpers.update_wander(player, dt)
	player.ai_wander_timer = player.ai_wander_timer - dt
	if player.ai_wander_timer > 0.0 then
		return
	end
	player.ai_wander_timer = AI_TUNING.WANDER_INTERVAL_MIN + math.random() * (AI_TUNING.WANDER_INTERVAL_MAX - AI_TUNING.WANDER_INTERVAL_MIN)
	local min_y = current_arena_bounds.position.y + player.ship.half_extents.y
	local max_y = current_arena_bounds.position.y + current_arena_bounds.size.y - player.ship.half_extents.y
	player.ai_wander_target_y = min_y + math.random() * (max_y - min_y)
end

-- ship_node.gd's _ai_update_depth(): periodically re-picks how deep in its
-- half the AI prefers to sit (0 = back wall, 1 = frontier).
function ai_helpers.update_depth(player, dt)
	player.ai_depth_timer = player.ai_depth_timer - dt
	if player.ai_depth_timer > 0.0 then
		return
	end
	player.ai_depth_timer = AI_TUNING.DEPTH_INTERVAL_MIN + math.random() * (AI_TUNING.DEPTH_INTERVAL_MAX - AI_TUNING.DEPTH_INTERVAL_MIN)
	player.ai_preferred_depth = player.ai_depth_min + math.random() * (player.ai_depth_max - player.ai_depth_min)
end

-- ship_node.gd's _ai_update_weapon_switch(): every WEAPON_SWITCH_INTERVAL_*
-- seconds, advances the AI's selected weapon by one kit slot (wrapping) —
-- a pure no-op for every real character (kit.size()==1, so "+1 wrapped" is
-- always the same single slot), but the ONLY thing that makes the Epic
-- boss's 8-weapon FULL_KIT actually cycle through its arsenal instead of
-- sitting on kit[1] (machine_gun) forever. Rather than blindly cycling,
-- rolls whether it "wants" its signature weapon (kit index 0) and only
-- pulses when that doesn't match its current selection — e.g. a Controleur
-- AI mostly stays on its turret rather than wandering off it every few
-- seconds (ship_node.gd's own doc comment, reused verbatim: the boss's
-- kit[0] is always machine_gun regardless of which character it's playing,
-- so this reads as "prefers machine_gun a bit more than a flat cycle
-- would", not literally "prefers its own real weapon").
function ai_helpers.update_weapon_switch(player, dt)
	player.ai_weapon_switch_timer = player.ai_weapon_switch_timer - dt
	if player.ai_weapon_switch_timer > 0.0 then
		return
	end
	player.ai_weapon_switch_timer = AI_TUNING.WEAPON_SWITCH_INTERVAL_MIN
		+ math.random() * (AI_TUNING.WEAPON_SWITCH_INTERVAL_MAX - AI_TUNING.WEAPON_SWITCH_INTERVAL_MIN)
	local kit_size = #player.weapon.kit
	if player.ai_signature_bias <= 0.0 or kit_size < 2 then
		player.weapon = weapon_system_state.with_selection(player.weapon, player.weapon.selected_index + 1)
		return
	end
	local wants_signature = math.random() < player.ai_signature_bias
	local has_signature = player.weapon.selected_index == 0
	if wants_signature ~= has_signature then
		player.weapon = weapon_system_state.with_selection(player.weapon, player.weapon.selected_index + 1)
	end
end

-- ship_node.gd's _ai_update_lift_attempt(): rolls a chance to attempt a
-- lift whenever the ball is closing in on this ship's own side — sets
-- ai_lift_timer, which update_player_input() reuses as "lift held" through
-- the same charge machinery the human controls use.
function ai_helpers.update_lift_attempt(player, dt)
	if player.ai_lift_timer > 0.0 then
		player.ai_lift_timer = math.max(player.ai_lift_timer - dt, 0.0)
		return
	end
	local approaching = player.side == 0 and ball.position.x < current_frontier_x or (player.side == 1 and ball.position.x > current_frontier_x)
	if not approaching then
		player.ai_lift_decided = false
		return
	end
	local edge_x = player.side == 0 and current_arena_bounds.position.x or (current_arena_bounds.position.x + current_arena_bounds.size.x)
	if math.abs(ball.position.x - edge_x) < 260.0 and not player.ai_lift_decided then
		player.ai_lift_decided = true
		if math.random() < player.ai_lift_chance then
			player.ai_lift_timer = math.random() < 0.5 and 0.35 or 0.75
		end
	end
end

-- 2026-09-27 — charged fire for the AI. Root cause of "AI never charges":
-- should_fire() returns false whenever weapon.cooldown > 0, so fire_held_
-- duration resets to 0 after EVERY normal shot and the charge never
-- accumulates (see AI_TUNING_LOG.md 2026-09-27 for the full analysis).
-- Fix: when ai_charge_timer > 0, update_player_input() forces firing=true
-- regardless of should_fire(), letting fire_held_duration build past the
-- NORMAL_FIRE_GRACE window into the real charge zone. ai_charge_releasing
-- then flips firing=false for exactly one frame, triggering the normal
-- released_charge_attempt → try_charged_fire() path without any special-case.
-- The AI rolls a charge decision at most every CHARGE_DECIDE_INTERVAL_*
-- seconds, ONLY while already aligned (should_fire() true at roll time) AND
-- the current weapon is charge-capable. CHARGE_FIRE_CHANCE is the main knob
-- Camil adjusts after testing; mechanism correctness is proven by
-- test_ai_charge.lua (see AI_TUNING_LOG.md 2026-09-27).
function ai_helpers.update_charge_attempt(player, dt)
	-- Tick an active charge hold
	if player.ai_charge_timer > 0.0 then
		player.ai_charge_timer = player.ai_charge_timer - dt
		if player.ai_charge_timer <= 0.0 then
			player.ai_charge_timer = 0.0
			player.ai_charge_releasing = true -- consumed on the very next firing read
		end
		return
	end
	-- Tick inter-attempt cooldown
	if player.ai_charge_decide_timer > 0.0 then
		player.ai_charge_decide_timer = player.ai_charge_decide_timer - dt
		return
	end
	-- Gate: only charge-capable weapons
	local selected = weapon_system_state.selected_weapon(player.weapon)
	if selected.charge_fire_duration <= 0.0 then
		return
	end
	-- Gate: only when already lined up (same predicate as normal fire).
	-- Calling should_fire() here is safe — it is declared pure/read-only.
	if not ai_helpers.should_fire(player) then
		return
	end
	-- Always reset the inter-attempt cooldown (roll or not — avoids hammering
	-- every frame when aligned).
	player.ai_charge_decide_timer = AI_TUNING.CHARGE_DECIDE_INTERVAL_MIN
		+ math.random() * (AI_TUNING.CHARGE_DECIDE_INTERVAL_MAX - AI_TUNING.CHARGE_DECIDE_INTERVAL_MIN)
	if math.random() < AI_TUNING.CHARGE_FIRE_CHANCE then
		-- Hold fire for the full grace window + charge window + small buffer to
		-- guarantee the charge is fully built before the release frame.
		player.ai_charge_timer = SHIP_FEEL.NORMAL_FIRE_GRACE + selected.charge_fire_duration + 0.05
	end
end

-- ship_node.gd's _ai_should_fire(): fires only when roughly Y-aligned with
-- the opponent (or a live enemy turret blocking the lane) — tolerance
-- widens as HP drops (Priority 3, "faire des degats", rising in urgency).
-- Pure/side-effect-free (read-only), safe to call speculatively from
-- ai_helpers.read_input() too.
function ai_helpers.should_fire(player)
	local opponent = opponent_of(player.side)
	if not opponent then
		return false
	end
	-- Non-full-auto weapons only "fire" on a real cooldown-driven edge — a
	-- human naturally releases the button between presses; gating on
	-- cooldown<=0 forces a real false frame while on cooldown, restoring a
	-- fresh edge every cycle so the AI "taps" like a human would (harmless
	-- no-op for Mitrailleur's full-auto path, which never depended on the
	-- edge to begin with).
	if player.weapon.cooldown > 0.0 then
		return false
	end
	local selected = weapon_system_state.selected_weapon(player.weapon)
	if player.weapon.gauges[player.weapon.selected_index + 1] < selected.gauge_cost_per_shot then
		return false -- don't hold the trigger when there's not even enough gauge for a shot to land
	end
	if selected.heat_max > 0.0 and player.weapon.heats[player.weapon.selected_index + 1] >= selected.heat_max then
		return false -- release the instant heat maxes out so it can actually start draining
	end
	local hp_fraction = mathx.clampf(player.ship.hp / player.max_hp, 0.0, 1.0)
	local tolerance = mathx.lerp(90.0, 170.0, 1.0 - hp_fraction)
	if selected.is_boomerang then
		-- The boomerang's outbound leg is a fixed banana arc, not a
		-- straight line like every other weapon — the AI can't reliably
		-- aim precisely at it, so don't demand precision it structurally
		-- can't deliver.
		tolerance = tolerance * 1.8
	end
	if math.abs(opponent.ship.position.y - player.ship.position.y) < tolerance then
		return true
	end
	local enemy_turret = ai_helpers.find_enemy_turret(player.side)
	return enemy_turret ~= nil and math.abs(enemy_turret.position.y - player.ship.position.y) < tolerance
end

-- ship_node.gd's _ai_read_input() — the full priority order (2026-08-16,
-- Camil: "elle cherche vraiment a renvoyer la balle au maximum, c'est sa
-- priorite. Deuxieme priorite: esquiver les tirs. 3eme prio: faire des
-- degats. Moins elle a de PV, plus elle va essayer de securiser"): an
-- imminent hit always wins the frame it matters; otherwise the ball-
-- return-vs-aggression balance shifts continuously with hp_fraction.
function ai_helpers.read_input(player)
	local hp_fraction = mathx.clampf(player.ship.hp / player.max_hp, 0.0, 1.0)
	local defensiveness = 1.0 - hp_fraction -- 0 at full HP, 1 near death
	local dodge_dir = ai_helpers.dodge_direction(player, defensiveness)

	local ball_on_my_side = player.side == 0 and ball.position.x < current_frontier_x or (player.side == 1 and ball.position.x > current_frontier_x)
	local enemy_turret = ai_helpers.find_enemy_turret(player.side)

	-- 2026-08-17 "tolerance au risque": a live turret shoots back, and
	-- every incoming shot re-triggers dodge, which unconditionally
	-- overrides everything else — the AI would flinch away before it could
	-- ever close enough to line up a return shot. While healthy and
	-- actually hunting a turret (one alive, ball not urgently on my own
	-- side), accept the risk and keep pressing instead of flinching.
	-- Self-preservation still wins outright once HP drops below the floor.
	local hunting_turret = enemy_turret ~= nil and not ball_on_my_side
	if hunting_turret and hp_fraction > AI_TUNING.TURRET_HUNT_HP_FLOOR then
		dodge_dir = 0.0
	end

	local opponent = opponent_of(player.side)

	if dodge_dir ~= 0.0 then
		-- Priority 2 overriding priority 1 for exactly the frame it
		-- applies — a dodge that arrives late is worthless, so this
		-- bypasses the hysteresis deadzone below entirely.
		player.ai_vertical_dir = dodge_dir
	else
		-- Priority 1: predicted ball Y, blended against priority 3's
		-- aggression target (the opponent's own Y, for lining up damage)
		-- and a little idle wander so the AI doesn't read as glued to the
		-- ball. ball_weight/aggression_weight always sum to 1.0: healthy
		-- leans hard on the ball, low HP leans hard on the opponent
		-- instead ("moins regardante sur le renvoi").
		local ball_target_y = ball.position.y + ball.velocity.y * ai_helpers.ball_time_to_arrival(player)
		-- A placed turret is FIXED at wherever it was cast, so chasing the
		-- owner ship's CURRENT Y rarely lines a shot up with it anymore
		-- once the owner has moved on — an enemy turret, while alive,
		-- replaces the opponent as this priority's target.
		local aggression_target_y = enemy_turret and enemy_turret.position.y or (opponent and opponent.ship.position.y or ball_target_y)
		local ball_weight = mathx.lerp(0.97, 0.4, defensiveness)
		local combat_target_y = mathx.lerp(aggression_target_y, ball_target_y, ball_weight)
		-- A live enemy turret isn't ambient "aggression", it's a standing
		-- threat that will keep dealing damage completely unopposed for
		-- the rest of its lifetime if never destroyed — worth a much
		-- harder pull, but ONLY while the ball isn't demanding an
		-- immediate return (priority 1 still wins outright the instant it does).
		if enemy_turret and not ball_on_my_side then
			combat_target_y = mathx.lerp(combat_target_y, enemy_turret.position.y, 0.85)
		end
		local wander_weight
		if ball_on_my_side then
			wander_weight = mathx.lerp(0.03, 0.1, defensiveness)
		else
			wander_weight = mathx.lerp(0.2, 0.4, defensiveness)
		end
		local target_y = mathx.lerp(combat_target_y, player.ai_wander_target_y, wander_weight)

		local diff_y = target_y - player.ship.position.y
		if math.abs(diff_y) < AI_TUNING.DEADZONE_STOP then
			player.ai_vertical_dir = 0.0
		elseif math.abs(diff_y) > AI_TUNING.DEADZONE_START then
			player.ai_vertical_dir = mathx.signf(diff_y)
		end
		-- else: within the hysteresis band — keep the previous direction
		-- rather than flip-flopping every frame, which reads as a "freeze".

		-- Perturbateur's boomerang throws along a fixed banana arc whose
		-- initial direction is set by this ship's own last movement
		-- direction at the exact moment it fires. Ball-tracking above
		-- points movement at the BALL, not the opponent, so right when a
		-- throw is actually about to happen, override movement for just
		-- this frame to face the opponent's real offset so the arc curves
		-- the right way — dodging (handled above) still wins outright.
		if opponent and weapon_system_state.selected_weapon(player.weapon).is_boomerang and ai_helpers.should_fire(player) then
			player.ai_vertical_dir = mathx.signf(opponent.ship.position.y - player.ship.position.y)
		end
	end

	-- Horizontal: default to a wandering point in the mid/BACK of the half
	-- (ai_preferred_depth), only committing to the frontier when the ball
	-- has genuinely closed the distance — approaching the net is a
	-- deliberate choice for a better angle, not a reflex. Flat behavior,
	-- no HP scaling (distance from the ball IS reaction time in a Pong
	-- derivative — camping the net trades away exactly what priority 1 needs).
	local forward_sign = player.side == 0 and 1.0 or -1.0
	local back_x = player.side == 0 and (current_arena_bounds.position.x + player.ship.half_extents.x) or (current_arena_bounds.position.x + current_arena_bounds.size.x - player.ship.half_extents.x)
	local frontier_reach_x = player.side == 0
		and (current_frontier_x - ship_state.NEUTRAL_ZONE_HALF_WIDTH - player.ship.half_extents.x)
		or (current_frontier_x + ship_state.NEUTRAL_ZONE_HALF_WIDTH + player.ship.half_extents.x)
	local span = math.abs(frontier_reach_x - back_x)
	local default_target_x = back_x + forward_sign * span * player.ai_preferred_depth

	local ball_close = ball_on_my_side and math.abs(ball.position.x - player.ship.position.x) < player.ai_approach_distance
	local target_x = ball_close and frontier_reach_x or default_target_x

	local diff_x = target_x - player.ship.position.x
	if math.abs(diff_x) < AI_TUNING.H_DEADZONE_STOP then
		player.ai_horizontal_dir = 0.0
	elseif math.abs(diff_x) > AI_TUNING.H_DEADZONE_START then
		player.ai_horizontal_dir = mathx.signf(diff_x)
	end

	return Vector2.new(player.ai_horizontal_dir, player.ai_vertical_dir)
end

-- 2026-10-06 (Floppy's playtest, relayed by Camil: "je rajouterais bien un
-- petit dash [...] si ce dash est specifique a chaque perso, c'est le
-- pied") — one shared cooldown-gated button, 8 completely different
-- effects, one per character (dash_helpers.effects below), picked with Camil one
-- character at a time. AI doesn't use it (a human-only "new button" ask;
-- can be revisited if AI dash usage is ever requested).
-- 2026-10-06 dash feature — one table (not several top-level locals), same
-- 200-local-ceiling convention as UT/boss_helpers/ai_helpers/feedback_fx.
local dash_helpers = {
	COOLDOWN = 2.0, -- "on part sur 2 secondes pour l'instant, a ajuster"
	LOURD_BOOST_MULTIPLIER = 2.2,
	LOURD_BOOST_DECAY_TIME = 0.5, -- also the full hard-lock duration — "verrouiler la direction de LOURD" (Camil: 1.0s felt too long, settled on 0.5s)
	SPREADER_CLONE_LIFETIME = 0.25,
	SPREADER_CLONE_SPEED_MULTIPLIER = 2.5, -- 2.0 * 1.25 — "rallonge legerement la distance parcourue par les clones"
	DIAGONALS = {
		Vector2.new(0.70710678, -0.70710678),
		Vector2.new(0.70710678, 0.70710678),
		Vector2.new(-0.70710678, -0.70710678),
		Vector2.new(-0.70710678, 0.70710678),
	},
	MITRAILLEUR_CLONE_LIFETIME = 0.5,
	MITRAILLEUR_CLONE_SPEED_MULTIPLIER = 2.0, -- "le clone va 2 fois plus vite"
	VIF_JUMP_DURATION = 0.3,
	VIF_JUMP_SPEED_MULTIPLIER = 2.0, -- "une acceleration de sa vitesse"
	VIF_JUMP_SCALE_PEAK = 0.8, -- draw_ship()'s own zoom-in/zoom-out amount at the jump's midpoint ("le saut doit etre un peu plus haut")
	ZONEUR_TELEPORT_DISTANCE = 180.0,
	PERTURBATEUR_BALL_SLOW_DURATION = 0.5, -- "ralentir la balle pendant 1/2 secondes"
	PERTURBATEUR_BALL_SLOW_FACTOR = 0.3, -- the ball advances at 30% of its real speed while this is active
	TRAQUEUR_PULL_DURATION = 0.8,
	TRAQUEUR_PULL_TURN_RATE = 5.0, -- fraction-per-second the ball's HEADING turns toward the player (speed untouched) — redesigned from a velocity-add after Camil found that always changed speed too; "et plus franchement ! (*1.25 encore)" on top of the redesign's own base rate
	GHOST_PADDLE_LIFETIME = 3.0,
}

-- Which way a position-based dash (hop/teleport/mirror-dash) should go:
-- whatever direction is currently held, else the last real direction moved,
-- else a sane default (up) rather than never moving at all on the very
-- first frame of a match.
function dash_helpers.facing_direction(player)
	if player.last_input_direction:length() > 0.01 then
		return player.last_input_direction:normalized()
	end
	if player.last_move_direction:length() > 0.01 then
		return player.last_move_direction:normalized()
	end
	return Vector2.new(0.0, -1.0)
end

-- Contrôleur's phantom paddle AND Perturbateur's mirror decoy are the same
-- underlying entity (see update_ghost_paddles()/the ball-bounce check in
-- update_ball_and_twist()) — a non-damaging hitbox that can return the ball
-- exactly once before it expires, then vanishes. `velocity` (nil for a
-- stationary paddle) lets Mitrailleur's own clone (below) actually travel —
-- see update_ghost_paddles()'s own position update.
function dash_helpers.spawn_ghost_paddle(player, position, velocity, lifetime)
	lifetime = lifetime or dash_helpers.GHOST_PADDLE_LIFETIME
	table.insert(ghost_paddles, {
		position = position,
		half_extents = SHIP_HALF_EXTENTS,
		owner_side = player.side,
		character_id = player.character.id, -- drawn as a translucent copy of the real ship art, see match_arena.draw()
		lifetime = lifetime,
		initial_lifetime = lifetime, -- draw()'s own fade window is relative to THIS, not a flat 0.5s — Spreader's 0.25s clones were barely visible otherwise ("on ne voit pas assez les clones")
		velocity = velocity,
	})
end

dash_helpers.effects = {
	-- "Super dash avec inertie de derapage" — a sharp burst of speed that
	-- decays back to normal, same decaying-boost pattern as his own
	-- Tourbillon recoil kick (see fire_recoil_timer's own use below) — PLUS
	-- a real slide: the ship keeps sliding toward dash_slide_direction
	-- (locked in at the moment of the dash, below) fighting whatever new
	-- input the player gives, same idea as skidding on ice — see the
	-- speed_multiplier block's own "lourd" branch for the actual blend.
	lourd = function(player, opponent)
		player.dash_boost_timer = dash_helpers.LOURD_BOOST_DECAY_TIME
		player.dash_boost_peak_multiplier = dash_helpers.LOURD_BOOST_MULTIPLIER
		player.dash_boost_decay_time = dash_helpers.LOURD_BOOST_DECAY_TIME
		player.dash_slide_direction = dash_helpers.facing_direction(player)
	end,
	-- "Invoque une raquette virtuelle en avance" — a stationary phantom
	-- paddle dropped at his exact current position (Camil, 2026-10-06: "le
	-- clone se place a l'endroit exact ou est controleur") — he can then
	-- move on and have two coverage points active at once.
	controleur = function(player, opponent)
		dash_helpers.spawn_ghost_paddle(player, Vector2.new(player.ship.position.x, player.ship.position.y))
	end,
	-- "Ultra dash incontrolable ou la raquette rebondit contre les murs" —
	-- forced movement in one direction, ignoring player input, bouncing off
	-- the arena's own bounds (and the frontier) for its whole duration —
	-- see the wall-bounce check right after ship_state.update() below.
	-- 2026-10-06, Camil (after disliking the original uncontrollable-ship
	-- version): "fais lui lancer un clone de lui-meme qui part dans la
	-- direction souhaitee et fade au bout d'1/2 seconde. le clone va 2 fois
	-- plus vite et n'est pas controlable." The real ship stays under full
	-- player control the whole time — only the thrown clone is the
	-- uncontrollable part, reusing the ghost_paddle entity (a real
	-- paddle-style ball bounce) but given a velocity instead of sitting
	-- still, see update_ghost_paddles()'s own position update.
	mitrailleur = function(player, opponent)
		local dir = dash_helpers.facing_direction(player)
		local velocity = dir * (ship_state.SPEED * dash_helpers.MITRAILLEUR_CLONE_SPEED_MULTIPLIER)
		dash_helpers.spawn_ghost_paddle(player, player.ship.position, velocity, dash_helpers.MITRAILLEUR_CLONE_LIFETIME)
	end,
	-- "Saut" — Camil, after the first version read as "une teleportation
	-- ratee": "on devrait faire vraiment un saut, avec le vaisseau qui zoome
	-- et dezoome, comme s'il sautait vraiment (et une acceleration de sa
	-- vitesse)". Now a real timed forced-movement burst (like Lourd's own
	-- direction lock) instead of an instant position snap, paired with a
	-- visual scale pulse in draw_ship() and invulnerability for exactly the
	-- jump's duration — "attaques surprises ou rattrapages in extremis".
	vif = function(player, opponent)
		player.dash_jump_timer = dash_helpers.VIF_JUMP_DURATION
		player.dash_jump_duration = dash_helpers.VIF_JUMP_DURATION
		player.dash_slide_direction = dash_helpers.facing_direction(player)
		player.dash_invuln_timer = dash_helpers.VIF_JUMP_DURATION
	end,
	-- "Teleportation" — an instant blink, no slide, no animation arc.
	zoneur = function(player, opponent)
		local dir = dash_helpers.facing_direction(player)
		player.ship = ship_state.knocked_back(player.ship, dir * dash_helpers.ZONEUR_TELEPORT_DISTANCE, current_arena_bounds, current_frontier_x)
	end,
	-- 2026-10-06, Camil (after disliking the mirror-dash-plus-leurre
	-- version, which read as unclear): "on pourrait le faire ralentir la
	-- balle pendant 1/2 secondes" — a global slow-motion window on the ball
	-- itself (see ball_slow_timer/resolve_ball_physics()), matching his own
	-- "perturbateur" theme (messing with the match's own rules, same spirit
	-- as his Ultra "Brouillage de commandes").
	perturbateur = function(player, opponent)
		feedback_fx.ball_slow_timer = dash_helpers.PERTURBATEUR_BALL_SLOW_DURATION
	end,
	-- "Aimant a balle" — the ball (if it's a real ball match, not a mini-jeu)
	-- gets nudged toward him for a short while — see the pull applied in
	-- update_ball_and_twist()'s resolve_ball_physics().
	missiles = function(player, opponent)
		player.dash_pull_timer = dash_helpers.TRAQUEUR_PULL_DURATION
	end,
	-- 2026-10-06, Camil (after disliking the plain speed-buff version):
	-- "spreader c'est pas dingue. On va rester dans le mood de spreader. Je
	-- pensais lancer des mini clones de lui dans 4 directions (les
	-- diagonales) sur 1/4 de secondes" — matches his own fan-shot weapon's
	-- spread pattern. Four short-lived, fast clones (same thrown-ghost_paddle
	-- mechanism as Mitrailleur's own single clone), one per diagonal.
	mini = function(player, opponent)
		local speed = ship_state.SPEED * dash_helpers.SPREADER_CLONE_SPEED_MULTIPLIER
		for _, dir in ipairs(dash_helpers.DIAGONALS) do
			dash_helpers.spawn_ghost_paddle(player, player.ship.position, dir * speed, dash_helpers.SPREADER_CLONE_LIFETIME)
		end
	end,
}

local function update_player_input(player, dt)
	local lift_held = false
	local firing
	local move_direction
	if player.is_ai then
		-- ship_node.gd's own _physics_process() order: the periodic AI
		-- timers tick BEFORE input is read this frame.
		ai_helpers.update_wander(player, dt)
		ai_helpers.update_depth(player, dt)
		ai_helpers.update_weapon_switch(player, dt)
		ai_helpers.update_lift_attempt(player, dt)
		lift_held = player.ai_lift_timer > 0.0
		-- 2026-09-27: charge-fire state machine. update_charge_attempt() runs
		-- BEFORE reading firing so its timer changes take effect this frame.
		ai_helpers.update_charge_attempt(player, dt)
		if player.ai_charge_releasing then
			-- Release frame: fire=false triggers released_charge_attempt below.
			firing = false
			player.ai_charge_releasing = false
		elseif player.ai_charge_timer > 0.0 then
			-- Charge hold: keep fire=true continuously, bypassing the cooldown
			-- gate in should_fire() that would otherwise reset fire_held_duration.
			firing = true
		else
			firing = ai_helpers.should_fire(player)
		end
		move_direction = ai_helpers.read_input(player)
	else
		-- Lift/charge: holding it slows movement to a crawl and charges the
		-- return's spin; releasing (or never holding) resets it — there's
		-- no "bank" of charge between attempts.
		local joystick = input.get_joystick(player.side + 1)
		lift_held = is_binding_down(player.controls.lift, joystick, player.controls.lift_button)
		firing = love.keyboard.isScancodeDown(player.controls.fire) or input.button_down(joystick, player.controls.fire_button)
		move_direction = input_direction(player.controls, joystick)

		-- Dash: edge-triggered, gated by its own cooldown — human-only (no
		-- AI usage yet). player.controls.dash is nil for a boss/mook's own
		-- CONTROLS table reuse quirk? No — both P1_CONTROLS/P2_CONTROLS
		-- always define it, so this is just the ordinary cooldown gate.
		local dash_pressed = love.keyboard.isScancodeDown(player.controls.dash) or input.button_down(joystick, player.controls.dash_button)
		if dash_pressed and not player.dash_prev and player.dash_cooldown_timer <= 0.0 then
			local effect = dash_helpers.effects[player.character.id]
			if effect then
				effect(player, opponent_of(player.side))
				player.dash_cooldown_timer = dash_helpers.COOLDOWN
			end
		end
		player.dash_prev = dash_pressed
	end
	-- ship_node.gd, 2026-08-13 bug report: "si j'appuie a la fois sur charge
	-- tir + charge lift, ca fait... du caca. on va donner la priorite au
	-- lift." Lift wins outright — fire reads as not pressed at all this
	-- frame (no normal fire, no charge-fire tracking) while lift is held.
	if lift_held then
		firing = false
	end
	if lift_held then
		player.lift_charge_timer = math.min(player.lift_charge_timer + dt, SHIP_FEEL.LIFT_CHARGE_CAP)
	else
		player.lift_charge_timer = 0.0
	end

	-- Charged fire (ship_node.gd) — the same state machine for AI and humans
	-- alike. For the AI, fire_held_duration is fed by the ai_charge_timer path
	-- above (not should_fire() directly), because should_fire() returns false
	-- during any weapon cooldown and would otherwise reset the accumulator
	-- after every shot (see AI_TUNING_LOG.md 2026-09-27). For a human,
	-- holding the fire key does the same job. In both cases: holding fires
	-- normally for the first SHIP_FEEL.NORMAL_FIRE_GRACE seconds; only past
	-- that does normal fire suspend and the charge gauge start building.
	-- Releasing before charge_fire_duration wastes the attempt; releasing
	-- at/after it fires the empowered variant instead of a normal shot.
	local selected_weapon = weapon_system_state.selected_weapon(player.weapon)
	local charge_capable = selected_weapon.charge_fire_duration > 0.0
	local released_charge_attempt = false
	local charge_duration_at_release = 0.0
	if charge_capable then
		if firing then
			player.fire_held_duration = player.fire_held_duration + dt
		elseif player.fire_held_duration > SHIP_FEEL.NORMAL_FIRE_GRACE then
			released_charge_attempt = true
			charge_duration_at_release = player.fire_held_duration
			player.fire_held_duration = 0.0
		else
			player.fire_held_duration = 0.0
		end
	else
		player.fire_held_duration = 0.0
	end
	local is_charging = charge_capable and player.fire_held_duration > SHIP_FEEL.NORMAL_FIRE_GRACE

	-- "Systeme des 5 balles" — a dedicated trigger key, edge-triggered like
	-- weapon select; consuming the meter here (not in the effect resolver)
	-- means a held/repeated press can never fire it twice off one fill.
	-- ship_node.gd's _ai_should_use_ultra() (2026-08-16, Camil: "l'IA
	-- n'utilise pas les ultra => il faut qu'elle le fasse"): fires the
	-- instant the meter is full — no edge-guard needed there either,
	-- since consuming the meter this same frame makes ultra_ready() false
	-- again immediately, so it can never re-fire off one fill.
	if player.is_ai then
		if weapon_system_state.ultra_ready(player.weapon) then
			player.weapon = weapon_system_state.with_ultra_consumed(player.weapon)
			start_ultra_intro(player, opponent_of(player.side))
		end
	else
		local ultra_pressed = player.controls.ultra ~= nil and love.keyboard.isScancodeDown(player.controls.ultra)
			or input.button_down(input.get_joystick(player.side + 1), player.controls.ultra_button)
		if ultra_pressed and not player.ultra_prev then
			if weapon_system_state.ultra_ready(player.weapon) then
				player.weapon = weapon_system_state.with_ultra_consumed(player.weapon)
				start_ultra_intro(player, opponent_of(player.side))
			else
				player.ultra_deny_shake_timer = ULTRA_MISC.DENY_SHAKE_DURATION
			end
		end
		player.ultra_prev = ultra_pressed
	end
	player.ultra_deny_shake_timer = math.max(player.ultra_deny_shake_timer - dt, 0.0)
	player.ultra_flash_timer = math.max(player.ultra_flash_timer - dt, 0.0)

	-- ship_node.gd ticks cooldown/heat here — BEFORE the fire dispatch below
	-- — not after. That ordering matters for charged fire specifically: on
	-- the exact release frame `firing` already reads false, so heat gets one
	-- frame's worth of decay right before fired()'s own heat-gate check runs,
	-- which is what lets a charged release actually fire the instant an
	-- overheated weapon's hold is released (ticking heat AFTER dispatch
	-- would gate the charged shot out on its own overheat).
	player.weapon = weapon_system_state.with_cooldown_ticked(player.weapon, dt)
	player.weapon = weapon_system_state.with_heat_ticked(player.weapon, dt, firing)

	-- hazard_zones twist: a stunned ship reads no movement input at all
	-- this frame (firing is untouched — same split ship_node.gd's own
	-- stun handling uses).
	if player.stun_timer > 0.0 then
		move_direction = Vector2.ZERO
	end
	player.stun_timer = math.max(player.stun_timer - dt, 0.0)

	-- Perturbateur's Ultra "Brouillage de commandes": movement input rotated
	-- by a fixed (per-application) random angle for the whole duration —
	-- rotating a zero vector (stunned) is a harmless no-op either way.
	if player.controls_scrambled_timer > 0.0 then
		move_direction = move_direction:rotated(player.controls_scramble_angle)
	end
	player.controls_scrambled_timer = math.max(player.controls_scrambled_timer - dt, 0.0)

	-- gauge_floor twist: self-fill-on-return is locked elsewhere (see the
	-- ball-bounce block in match_arena.update()), so a passive trickle
	-- guarantees the fight can never fully stall out.
	if active_twist and active_twist.twist_type == "gauge_floor" then
		local weapon = weapon_system_state.selected_weapon(player.weapon)
		local trickle = weapon.gauge_max * active_twist.passive_trickle_rate / 100.0 * dt
		player.weapon = weapon_system_state.with_gauge_added(player.weapon, trickle)
	end

	local speed_multiplier = 1.0
	if lift_held then
		speed_multiplier = math.min(speed_multiplier, SHIP_FEEL.LIFT_CHARGE_MOVE_MULTIPLIER)
	end
	if is_charging then
		speed_multiplier = math.min(speed_multiplier, selected_weapon.charge_fire_slow_multiplier)
	end
	if player.vulnerability_timer > 0.0 then
		speed_multiplier = math.min(speed_multiplier, SHIP_FEEL.VULNERABILITY_SPEED_MULTIPLIER)
	end
	if player.charged_beam_slow_timer > 0.0 then
		speed_multiplier = math.min(speed_multiplier, player.charged_beam_slow_multiplier)
	end
	if player.external_slow_timer > 0.0 then
		-- Contrôleur's Ultra "Trou noir" (an opponent's effect on this ship).
		speed_multiplier = math.min(speed_multiplier, player.external_slow_multiplier)
	end
	if firing and not is_charging then
		-- normal firing (including a charge-capable weapon's own grace
		-- window) always carries this slow; charge_fire_slow_multiplier
		-- takes over once actually charging.
		speed_multiplier = math.min(speed_multiplier, SHIP_FEEL.FIRE_HOLD_SPEED_MULTIPLIER)
	end
	if player.fire_recoil_timer > 0.0 and selected_weapon.fire_recoil_boost_decay_time > 0.0 then
		-- Vif's Tourbillon recoil kick: starts at +fire_recoil_speed_boost
		-- (0.6 = +60%) and decays linearly to +0% over the weapon's decay
		-- time — a BOOST, so it wins over any slow above via max(), never
		-- multiplies/stacks with them.
		local recoil_fraction = player.fire_recoil_timer / selected_weapon.fire_recoil_boost_decay_time
		speed_multiplier = math.max(speed_multiplier, 1.0 + selected_weapon.fire_recoil_speed_boost * recoil_fraction)
	end
	if player.dash_boost_timer > 0.0 and player.dash_boost_decay_time > 0.0 then
		-- Lourd's/Spreader's dash: same decaying-boost shape as the recoil
		-- kick just above (a BOOST, wins via max(), never stacks/multiplies).
		local dash_fraction = player.dash_boost_timer / player.dash_boost_decay_time
		speed_multiplier = math.max(speed_multiplier, mathx.lerp(1.0, player.dash_boost_peak_multiplier, dash_fraction))
		if player.character.id == "lourd" then
			-- "Inertie de derapage" (Camil, 2026-10-06 — first a blend, then
			-- after testing: "non pour lourd ca marche pas. Il faut vraiment
			-- verrouiler la direction de LOURD, le temps du dash (1 petite
			-- seconde)") — a real hard lock, same idea as Mitrailleur's own
			-- forced-movement override just below, but one straight direction
			-- for the whole LOURD_BOOST_DECAY_TIME window instead of a wall-
			-- bouncing one: whatever the player/AI asks for this frame is
			-- ignored outright, not blended, until the dash itself ends.
			move_direction = player.dash_slide_direction
		end
	end
	player.vulnerability_timer = math.max(player.vulnerability_timer - dt, 0.0)
	player.paddle_flash_timer = math.max(player.paddle_flash_timer - dt, 0.0)
	player.fire_recoil_timer = math.max(player.fire_recoil_timer - dt, 0.0)
	player.charged_beam_slow_timer = math.max(player.charged_beam_slow_timer - dt, 0.0)
	player.external_slow_timer = math.max(player.external_slow_timer - dt, 0.0)
	player.dash_cooldown_timer = math.max(player.dash_cooldown_timer - dt, 0.0)
	player.dash_boost_timer = math.max(player.dash_boost_timer - dt, 0.0)
	player.dash_invuln_timer = math.max(player.dash_invuln_timer - dt, 0.0)
	player.dash_pull_timer = math.max(player.dash_pull_timer - dt, 0.0)
	-- Epic 4 reward system: Vif's unlocked passive is a PERMANENT speed
	-- multiplier, stacked multiplicatively on top of everything else above
	-- (ship_node.gd: `speed_multiplier *= _passive_speed_multiplier`).
	speed_multiplier = speed_multiplier * passive_state[player.side + 1].speed_multiplier

	-- Vif's "saut": forced movement in the locked direction for the jump's
	-- whole duration, same hard-override idea as Lourd's own dash — see
	-- draw_ship() for the paired zoom-in/zoom-out visual.
	if player.dash_jump_timer > 0.0 then
		move_direction = player.dash_slide_direction
		speed_multiplier = math.max(speed_multiplier, dash_helpers.VIF_JUMP_SPEED_MULTIPLIER)
	end
	player.dash_jump_timer = math.max(player.dash_jump_timer - dt, 0.0)

	player.last_input_direction = move_direction -- reused for the ball-return aim, see match_arena.update()
	if move_direction:length() > 0.01 then
		player.last_move_direction = move_direction -- Perturbateur's boomerang throw-arc side
	end
	player.ship = ship_state.update(player.ship, move_direction, dt, current_arena_bounds, current_frontier_x, speed_multiplier)

	if charge_capable and is_charging then
		-- normal fire suspended while actively charging (past the grace window)
	elseif firing and (player.character.full_auto or not player.fire_held_prev) then
		-- Either a non-charge-capable weapon, or a charge-capable one still
		-- within its SHIP_FEEL.NORMAL_FIRE_GRACE window — fires exactly like
		-- normal. No AI special-case: ai_helpers.should_fire() already cycles
		-- true/false on its own real cooldown-driven edge, same as a human
		-- tapping the button — ship_node.gd's own dispatch doesn't special-
		-- case ai_controlled here either.
		try_fire(player)
	end

	if charge_capable and released_charge_attempt then
		if charge_duration_at_release >= selected_weapon.charge_fire_duration then
			try_charged_fire(player)
		end
		-- else: released mid-charge (past the grace window, before full) —
		-- the attempt is lost, nothing fires.
	end
	player.fire_held_prev = firing
end

-- Perturbateur's boomerang (mirrors projectile_node.gd's _update_boomerang()
-- exactly). Outbound leg: velocity is recomputed every frame straight from
-- the base velocity captured at spawn, rotated by an angle swept linearly
-- from boomerang_start_deg to boomerang_end_deg — no reference to `target`
-- at all, so it can never be "guided". Return leg: re-aims at the
-- shooter's LIVE position each frame (read fresh — the shooter's player
-- table persists across a round, only its .ship field is replaced), then
-- despawns once close enough to be "caught" — unless it detects a dodge
-- (drifted away from its closest approach after actually closing in),
-- in which case it gives up homing and just coasts straight.
-- Returns true once it should be removed (caught).
local function update_boomerang(bullet, dt)
	bullet.boomerang_timer = bullet.boomerang_timer + dt
	if not bullet.boomerang_returning then
		local t = mathx.clampf(bullet.boomerang_timer / bullet.boomerang_out_duration, 0.0, 1.0)
		local current_deg = mathx.lerp(bullet.boomerang_start_deg, bullet.boomerang_end_deg, t)
		bullet.velocity = bullet.boomerang_base_velocity:rotated(mathx.deg_to_rad(current_deg))
		bullet.position = bullet.position + bullet.velocity * dt
		if bullet.boomerang_timer >= bullet.boomerang_out_duration then
			bullet.boomerang_returning = true
		end
		return false
	end

	local shooter_position = bullet.shooter_player.ship.position
	bullet.position = bullet.position + bullet.velocity * dt
	local current_dist = bullet.position:distance_to(shooter_position)
	if current_dist < BOOMERANG.CATCH_DISTANCE then
		return true -- caught, regardless of missed_catch — a lucky drift back into range still counts
	end
	if not bullet.boomerang_missed_catch then
		if current_dist < bullet.boomerang_return_closest_dist then
			bullet.boomerang_return_closest_dist = current_dist
		elseif bullet.boomerang_return_closest_dist <= BOOMERANG.MISS_ENGAGE_DISTANCE
			and current_dist > bullet.boomerang_return_closest_dist + BOOMERANG.MISS_MARGIN then
			bullet.boomerang_missed_catch = true -- dodged — give up homing, coast straight from here
		end
		if not bullet.boomerang_missed_catch then
			local to_shooter = shooter_position - bullet.position
			if to_shooter:length() > 1.0 then
				local angle_diff = wrap_angle(to_shooter:angle() - bullet.velocity:angle())
				local max_turn = mathx.deg_to_rad(BOOMERANG.RETURN_TURN_RATE_DEG) * dt
				bullet.velocity = bullet.velocity:rotated(mathx.clampf(angle_diff, -max_turn, max_turn))
			end
		end
	end
	return false
end

-- 2026-10-05 (a friend's playtest, relayed by Camil: "il manque des
-- feedbacks sur les rebonds de raquettes, des shakes de camera quand on se
-- fait toucher ou quand la balle passe") — two independent additions:
-- a brief white flash on a ship that just returned the ball (see
-- ship_tint()/the paddle-bounce call sites), and a camera shake whenever a
-- ship takes damage or either side misses the ball (see
-- apply_damage_and_check_round()/the missed-ball branch in
-- update_ball_and_twist()). The shake itself is a random per-frame offset
-- that decays linearly to zero over shake_duration — see feedback_fx's own
-- trigger_shake()/update_shake() and match_arena.draw()'s own push/
-- translate/pop around just the gameplay world (never the HUD, which must
-- stay readable). Methods hang off feedback_fx (declared with the module's
-- other state, earlier in this file) rather than being separate top-level
-- locals/functions — the 200-local ceiling, same reason as UT/boss_helpers.
function feedback_fx.trigger_shake(magnitude, duration)
	-- A stronger/longer shake already in progress always wins — a small
	-- miss-shake landing right after a big hit-shake shouldn't cut it short.
	if magnitude >= feedback_fx.shake_magnitude then
		feedback_fx.shake_timer = duration
		feedback_fx.shake_duration = duration
		feedback_fx.shake_magnitude = magnitude
	end
end

function feedback_fx.update_shake(dt)
	feedback_fx.shake_timer = math.max(feedback_fx.shake_timer - dt, 0.0)
	if feedback_fx.shake_timer <= 0.0 then
		-- 2026-10-05 bug fix (Camil's friend's playtest: "les secousses sur
		-- un coup recu ne se sentent pas du tout") — shake_magnitude was
		-- never reset once a shake finished, only shake_timer was. Since
		-- trigger_shake() only accepts a NEW shake when it's >= the current
		-- magnitude, that stale peak value (e.g. 10 from a miss-shake) stuck
		-- around forever and silently blocked every smaller damage-shake
		-- (typically 1-6, well under 10) for the rest of the match.
		feedback_fx.shake_magnitude = 0.0
	end
end

-- A random offset, scaled down linearly as the shake winds down (an abrupt
-- stop reads worse than a fade-out) — fresh random direction every frame so
-- it reads as a jitter, not a single decaying oscillation.
function feedback_fx.shake_offset()
	if feedback_fx.shake_timer <= 0.0 then
		return 0.0, 0.0
	end
	local t = feedback_fx.shake_timer / feedback_fx.shake_duration
	local magnitude = feedback_fx.shake_magnitude * t
	local angle = math.random() * math.pi * 2.0
	return math.cos(angle) * magnitude, math.sin(angle) * magnitude
end

-- Applies damage to `target` and, if that brings it to 0 hp, ends the
-- round (win goes to `winner_side`, and a fresh round starts immediately
-- unless the match itself just ended). Shared by every damage source
-- (bullets, beams, ...) so the round-end plumbing lives in exactly one
-- place. Returns true when the round ended — the caller must bail out of
-- its own update loop that same frame, since `bullets`/`beams` may have
-- just been replaced out from under it.
local function apply_damage_and_check_round(target, winner_side, damage)
	if target.dash_invuln_timer and target.dash_invuln_timer > 0.0 then
		-- Vif's "Saut" dash: briefly untouchable by weapon fire — "attaques
		-- surprises ou rattrapages in extremis". No shake/flash either;
		-- nothing actually landed.
		return false
	end
	target.ship = ship_state.damaged(target.ship, damage)
	feedback_fx.trigger_shake(
		mathx.clampf(damage * feedback_fx.SHAKE_DAMAGE_MAGNITUDE_PER_DAMAGE, feedback_fx.SHAKE_DAMAGE_MAGNITUDE_MIN, feedback_fx.SHAKE_DAMAGE_MAGNITUDE_MAX),
		feedback_fx.SHAKE_DAMAGE_DURATION
	)
	if target.ship.hp <= 0.0 then
		local loser_side = target.side
		match = match_state.round_won_by(match, winner_side)
		-- leave `impacts` alone so the killing blow's own flash still plays out
		bullets = {}
		beams = {}
		turrets = {}
		ghost_paddles = {}
		fire_trails = {}
		missile_strikes = {}
		black_holes = {}
		laser_meshes = {}
		wind_gusts = {}
		-- 2026-09-12 (Camil: "quand on perd (0pv) il faudrait une explosion
		-- lente du vaisseau... avant apparition du 'appuyer pour continuer'")
		-- — freezes the whole round (same freeze pattern as ultra_intro/
		-- pause_state/round_start_gate) for a red/white flicker telegraph
		-- before the actual debris/disintegration burst lands; only THEN
		-- does start_new_round()/the match-over reveal actually happen — see
		-- ship_explosion_helpers.update_explosion().
		ship_explosion_helpers.round = {
			loser = target,
			loser_side = loser_side,
			phase_timer = ship_explosion_helpers.DURATION,
			flicker_timer = ship_explosion_helpers.FLICKER_HALF_PERIOD,
			flicker_on = true,
		}
		return true
	end
	return false
end

-- match_arena_node.gd's own award: the flicker telegraph runs for
-- ship_explosion_helpers.DURATION, then the debris/disintegration burst lands and
-- ONLY THEN does the deferred round/match resolution actually happen
-- (start_new_round(), or nothing further here — draw()'s own match.
-- match_over branch and keypressed()'s continue-key handler take over from
-- there, both gated on ship_explosion_helpers.round being nil, same as Godot
-- awaiting the whole explosion before touching match_state.match_over's
-- consequences at all).
function ship_explosion_helpers.update_explosion(dt)
	ship_explosion_helpers.round.phase_timer = ship_explosion_helpers.round.phase_timer - dt
	ship_explosion_helpers.round.flicker_timer = ship_explosion_helpers.round.flicker_timer - dt
	if ship_explosion_helpers.round.flicker_timer <= 0.0 then
		ship_explosion_helpers.round.flicker_on = not ship_explosion_helpers.round.flicker_on
		ship_explosion_helpers.round.flicker_timer = ship_explosion_helpers.FLICKER_HALF_PERIOD
	end
	if ship_explosion_helpers.round.phase_timer <= 0.0 then
		local loser = ship_explosion_helpers.round.loser
		local loser_side = ship_explosion_helpers.round.loser_side
		ship_explosion_helpers.spawn_debris_burst(loser.ship.position, 3.5) -- the one explosion
		ship_explosion_helpers.spawn_disintegration_chunks(loser.ship.position, loser.side) -- the ship itself breaking apart
		loser.exploded_hidden = true -- draw_ship() skips it from here on; a fresh round's new_player() clears this along with everything else
		ship_explosion_helpers.round = nil
		if not match.match_over then
			start_new_round(loser_side)
		end
	end
end

-- "Systeme des 5 balles" Ultra dispatch (match_arena_node.gd's
-- _resolve_ultra_effect()). Each of the 8 characters (plus the masked boss,
-- via boss_helpers) has its own bespoke effect below — ULTRA_MISC.
-- GENERIC_ULTRA_DAMAGE is only ever reached as Godot's own fallback for a
-- character with literally no Ultra defined, which doesn't happen among
-- the 8 real ones.
-- start_ultra_intro()/draw_ultra_intro() (further down) port Godot's real
-- full slide/hold/slide UltraIntroNode cinematic — ultra_flash_timer here
-- is a smaller COMPLEMENTARY HUD cue (see ULTRA_MISC's own doc comment),
-- not a stand-in for it.
-- All per-Ultra tuning numbers in ONE table (rather than ~60 separate
-- top-level locals) — Lua's main chunk has a hard 200-local ceiling, and
-- this file is long enough already that scattering every constant
-- individually risks tripping it. Grouped by character for readability;
-- referenced as UT.SOME_NAME everywhere below.
local UT = {
	LA_MEUTE_GUARANTEED_DAMAGE = 8.0,

	PLUIE_DE_BONBONS_GUARANTEED_DAMAGE = 8.0,
	PLUIE_DE_BONBONS_COUNT = 40,
	PLUIE_DE_BONBONS_SPAWN_WINDOW = 1.5,
	PLUIE_DE_BONBONS_FALL_SPEED = 546.0,
	PLUIE_DE_BONBONS_MARGIN = 30.0,
	PLUIE_DE_BONBONS_LIFETIME = 3.0,

	MITRAILLEUSES_SATELLITES_GUARANTEED_DAMAGE = 8.0,
	-- 2026-10-05 "tout plus gros" pass: the ship itself grew (half_extents.y
	-- 28->42), so these escort turrets needed pushing further out too, or
	-- they'd now sit almost inside the bigger ship sprite.
	MITRAILLEUSES_SATELLITES_OFFSET_Y = 50.0 * 1.5,

	BROUILLAGE_GUARANTEED_DAMAGE = 8.0,
	BROUILLAGE_DURATION = 12.5,

	-- Lourd's "Pluie de Scuds": MISSILE_COUNT reticles land across the
	-- opponent's ENTIRE half, each telegraphed for FALL_DURATION by a
	-- closing ring + falling shell, staggered so they keep raining down.
	PLUIE_DE_SCUDS_GUARANTEED_DAMAGE = 8.0,
	PLUIE_DE_SCUDS_MISSILE_COUNT = 50,
	PLUIE_DE_SCUDS_STAGGER = 0.1,
	PLUIE_DE_SCUDS_FALL_DURATION = 1.0 / 3.0,
	PLUIE_DE_SCUDS_IMPACT_RADIUS = 82.5,
	PLUIE_DE_SCUDS_IMPACT_DAMAGE = 6.0,
	PLUIE_DE_SCUDS_IMPACT_PUSH = 30.0,
	PLUIE_DE_SCUDS_TARGET_MARGIN = 40.0,
	MISSILE_STRIKE_START_SCALE = 4.0,
	MISSILE_STRIKE_SPAWN_Y_OFFSET = 24.0,

	-- Contrôleur's "Trou noir": opens in the middle of the OPPONENT's own
	-- half, pulling+slowing them while inside RADIUS (a fainter outer halo
	-- slows only), creeping slowly toward their live position.
	TROU_NOIR_GUARANTEED_DAMAGE = 8.0,
	TROU_NOIR_RADIUS = 165.0,
	TROU_NOIR_PULL_SPEED = 140.0,
	TROU_NOIR_SLOW_MULTIPLIER = 0.5,
	TROU_NOIR_DURATION = 6.0,
	TROU_NOIR_OUTER_RADIUS = 260.0,
	TROU_NOIR_OUTER_SLOW_MULTIPLIER = 0.6,
	TROU_NOIR_DRIFT_SPEED = 25.0,
	TROU_NOIR_SLOW_REFRESH_DURATION = 0.2,
	BLACK_HOLE_FRAME_DURATION = 0.12,

	-- Zoneur's "Grille Laser": COUNT diagonal segments, each a random angle
	-- through a random point clipped to the OPPONENT's half only,
	-- staggered so the web visibly builds up.
	GRILLE_LASER_GUARANTEED_DAMAGE = 8.0,
	GRILLE_LASER_COUNT = 14,
	GRILLE_LASER_SPAWN_WINDOW = 1.0,
	GRILLE_LASER_LIFETIME = 1.5,
	GRILLE_LASER_DAMAGE_PER_TICK = 1.0,
	GRILLE_LASER_THICKNESS = 5.0,
	GRILLE_LASER_TICK_INTERVAL = 0.1,
	GRILLE_LASER_FADE_DURATION = 0.15,
	GRILLE_LASER_SWEEP_DURATION = 0.18, -- time for a laser's head to race from one end of its line to the other
	GRILLE_LASER_COLOR = { 0.4, 1.0, 0.5, 0.85 },

	-- Vif's "Bourrasque": 25 vortices race in from OFF-SCREEN behind the
	-- caster's own outer wall, at fixed (not random) vertical slots
	-- speeding up the whole way, alongside a continuous gust shoving the
	-- opponent toward THEIR OWN outer wall for the whole attack. Y/depth
	-- fractions read off Camil's own reference image, NOT randomized.
	BOURRASQUE_GUARANTEED_DAMAGE = 8.0,
	-- 2026-10-05 (Camil: "trop lent": +25% au depart, +50% a l'arrivee,
	-- et 2-3 tourbillons de plus): 200 -> 250 start speed, and acceleration
	-- 220 -> 345 so the ~4 s end speed goes 1080 -> ~1630 (x1.5). The last
	-- 3 slots of each list are the added vortices, filling the vertical gaps.
	BOURRASQUE_VORTEX_Y_FRACTIONS = { 0.21, 0.17, 0.12, 0.38, 0.50, 0.67, 0.63, 0.79, 0.91, 0.91, 0.29, 0.57, 0.85, 0.07, 0.44, 0.73, 0.25, 0.95, 0.10, 0.24, 0.35, 0.52, 0.62, 0.77, 0.88 },
	BOURRASQUE_VORTEX_DEPTH_FRACTIONS = { 0.24, 0.63, 0.93, 0.87, 0.40, 0.26, 0.73, 0.90, 0.55, 0.17, 0.50, 0.08, 0.33, 0.70, 0.15, 0.47, 0.82, 0.30, 0.05, 0.45, 0.78, 0.20, 0.95, 0.60, 0.38 },
	-- Per-vortex size (70%-130%). Bigger = proportionally faster (start speed
	-- and acceleration both x size) for a parallax feel.
	BOURRASQUE_VORTEX_SIZE_FACTORS = { 1.0, 0.8, 1.3, 0.7, 1.15, 0.9, 1.25, 0.75, 1.1, 1.3, 0.85, 1.2, 0.7, 1.0, 1.3, 0.8, 1.15, 0.7, 0.7, 0.75, 0.8, 0.7, 0.85, 0.75, 0.8 },
	BOURRASQUE_VORTEX_MIN_SPAWN_OFFSET = 40.0,
	BOURRASQUE_VORTEX_MAX_SPAWN_OFFSET = 600.0,
	BOURRASQUE_VORTEX_START_SPEED = 250.0,
	BOURRASQUE_VORTEX_ACCELERATION = 345.0,
	BOURRASQUE_VORTEX_VISUAL_SCALE = 3.2,
	BOURRASQUE_VORTEX_DAMAGE = 4.0,
	BOURRASQUE_VORTEX_LIFETIME = 4.0,
	BOURRASQUE_VORTEX_FRAME_DURATION = 0.12,
	BOURRASQUE_GUST_DURATION = 3.0,
	BOURRASQUE_GUST_PUSH_SCALE = 0.55,

	-- Epic 4 reward system (2026-08-16, "on va mettre des trucs en face des
	-- recompenses. pour chaque rival vaincu."): beating a rival anywhere
	-- unlocks a passive effect for that character, forever, campaign AND
	-- Versus — each tied to that character's own established identity
	-- (2026-08-16 same-day rework, "il faut etre plus creatif").
	PASSIVE_TURRET_LIFETIME = 6.0, -- Contrôleur's own turret unlock — shorter-lived than a normal cast
	PASSIVE_MITRAILLEUR_BURST_COUNT = 4,
	PASSIVE_PERTURBATEUR_ULTRA_SCRAMBLE_DURATION = 5.0, -- "lors de l'ultra du joueur, applique aussi le brouillage, mais uniquement 5 sec"
	PASSIVE_VIF_SPEED_MULTIPLIER = 1.2, -- "une acceleration de +20%, tout le temps" — PERMANENT
	PASSIVE_SPREADER_HEAL_FRACTION = 0.15, -- "lui redonne 15% de PV" of max_hp, not a flat number
	PASSIVE_HEAL_POPUP_COLOR = { 0.35, 0.9, 0.35, 1.0 }, -- green, distinct from the gold gauge-fill "+X" popup — this one's HP, not weapon charge
	-- passive_heal_fx_node.gd's own cosmetic flourish: Spreader's bonbon
	-- sprite orbits the healed ship twice over this duration, fading out.
	PASSIVE_SPREADER_FAN_DURATION = 2.0,
	-- 2026-10-05 "tout plus gros" pass: the ship grew (half_extents 14x28 ->
	-- 21x42), so this orbit radius needed the same bump or the bonbon would
	-- now clip through the bigger ship sprite along some part of its orbit.
	PASSIVE_SPREADER_FAN_RADIUS = 26.0 * 1.5,

	-- Epic boss (2026-09-05, Camil: "gros, imposant, qu'il ait toutes les
	-- armes... faut que ce soit epique") — match_arena_node.gd's
	-- _setup_boss_ship()/_process_boss_phases(), same numbers as
	-- twist_data.gd's own defaults for these fields (boss_permanent_buff_
	-- percent/boss_phase2_orb_interval_multiplier are declared there too but
	-- unused by the current Godot code — not ported, matching that).
	BOSS_PHASE2_MESSAGE = "L'Organisateur se dechaine !",
	BOSS_PHASE3_MESSAGE = "DERNIERE CHANCE !",
	BOSS_PHASE_MESSAGE_DURATION = 2.2,
}

-- Epic boss (2026-09-05) — match_arena_node.gd's _setup_boss_ship(): called
-- once per round, right after players[2] is (re-)built (both enter() and
-- start_new_round() rebuild the whole player table from scratch via
-- new_player(), so the boss's size/hp/kit overrides need reapplying every
-- round too — matches the 2026-09-12 bug fix "le boss est toujours en mode
-- dechaine" that made _begin_round_ready_gate() reset _boss_phase/
-- boss_simultaneous_fire_indices every round rather than just once).
function boss_helpers.setup_ship(player)
	boss_helpers.phase = 1
	boss_helpers.message, boss_helpers.message_timer = "", 0.0
	local twist = active_twist
	local new_half_extents = Vector2.new(SHIP_HALF_EXTENTS.x * twist.boss_size_multiplier, SHIP_HALF_EXTENTS.y * twist.boss_size_multiplier)
	player.max_hp = ship_state.START_HP * twist.boss_hp_multiplier
	player.ship = ship_state.new(player.ship.position, player.side, new_half_extents, player.max_hp)
	player.weapon = weapon_system_state.new(boss_helpers.FULL_KIT)
	player.boss_simultaneous_fire_indices = {}
end

-- match_arena_node.gd's _flash_boss_phase_message(): non-blocking (gameplay
-- keeps running under it) — see match_arena.draw()'s own fade-out.
function boss_helpers.flash_message(text)
	boss_helpers.message = text
	boss_helpers.message_timer = UT.BOSS_PHASE_MESSAGE_DURATION
end

-- match_arena_node.gd's _process_boss_phases(): escalates as the boss's HP
-- crosses each phase threshold (falling only — never re-triggers if HP
-- climbs back up, e.g. from a stray heal quirk). Phase 2 adds a second
-- weapon to fire alongside the selected one; phase 3 adds a third.
function boss_helpers.update_phases()
	local boss = players[2]
	if boss.max_hp <= 0.0 then
		return
	end
	local hp_fraction = boss.ship.hp / boss.max_hp
	if boss_helpers.phase == 1 and hp_fraction <= active_twist.boss_phase2_hp_fraction then
		boss_helpers.phase = 2
		-- 0-based, matching weapon_system_state's own selected_index
		-- convention (see try_fire()'s own extra-weapon loop reading these).
		boss.boss_simultaneous_fire_indices = { math.random(0, #boss.weapon.kit - 1) }
		boss_helpers.flash_message(UT.BOSS_PHASE2_MESSAGE)
	elseif boss_helpers.phase == 2 and hp_fraction <= active_twist.boss_phase3_hp_fraction then
		boss_helpers.phase = 3
		local extra2 = math.random(0, #boss.weapon.kit - 1)
		local already_has = false
		for _, i in ipairs(boss.boss_simultaneous_fire_indices) do
			if i == extra2 then
				already_has = true
				break
			end
		end
		if not already_has then
			table.insert(boss.boss_simultaneous_fire_indices, extra2)
		end
		-- 2026-09-27 fix (Camil: "les phases de l'organisateur ne
		-- correspondent pas a celles qu'on avait faites dans Godot") — this
		-- while loop (match_arena_node.gd's own `while not ship_2.weapon_
		-- state.ultra_ready(): ship_2.add_ultra_pip()`) had never been
		-- ported: phase 3 refills the boss's own Ultra meter to full for a
		-- genuine "it's not over yet" beat, same as Godot.
		while not weapon_system_state.ultra_ready(boss.weapon) do
			boss.weapon = weapon_system_state.with_ultra_pip_added(boss.weapon)
		end
		boss_helpers.flash_message(UT.BOSS_PHASE3_MESSAGE)
	end
end

-- Small Ultra-only helpers, also grouped into one table for the same
-- local-count reason as UT above.
local ultra_helpers = {}

-- Center of the given side's own playable half (Trou noir/Bourrasque both
-- want to threaten where the OPPONENT actually spends their time, not the
-- frontier — 2026-08-15 playtest: a push effect at the frontier is self-
-- limiting since the target leaves the radius the instant they're pushed).
function ultra_helpers.half_center(side)
	local x
	if side == 0 then
		x = (ARENA_BOUNDS.position.x + current_frontier_x) / 2.0
	else
		x = (current_frontier_x + ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x) / 2.0
	end
	return Vector2.new(x, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0)
end

-- Picks a random point inside the given bounds and a random angle, then
-- clips the resulting infinite line to those bounds (slab method) so the
-- segment always spans edge-to-edge across the confined area
-- (laser_mesh_node.gd's own random_clipped_to()).
function ultra_helpers.random_line_clipped_to(min_x, min_y, max_x, max_y)
	local anchor_x = min_x + math.random() * (max_x - min_x)
	local anchor_y = min_y + math.random() * (max_y - min_y)
	local angle = math.random() * math.pi
	local dir_x, dir_y = math.cos(angle), math.sin(angle)
	local t_min, t_max = -math.huge, math.huge
	if math.abs(dir_x) > 0.0001 then
		local t1, t2 = (min_x - anchor_x) / dir_x, (max_x - anchor_x) / dir_x
		t_min = math.max(t_min, math.min(t1, t2))
		t_max = math.min(t_max, math.max(t1, t2))
	end
	if math.abs(dir_y) > 0.0001 then
		local t1, t2 = (min_y - anchor_y) / dir_y, (max_y - anchor_y) / dir_y
		t_min = math.max(t_min, math.min(t1, t2))
		t_max = math.min(t_max, math.max(t1, t2))
	end
	return Vector2.new(anchor_x + dir_x * t_min, anchor_y + dir_y * t_min), Vector2.new(anchor_x + dir_x * t_max, anchor_y + dir_y * t_max)
end

function ultra_helpers.spawn_missile_strike(target_position, opponent_player, owner_side)
	table.insert(missile_strikes, {
		position = target_position,
		elapsed = 0.0,
		fall_duration = UT.PLUIE_DE_SCUDS_FALL_DURATION,
		impact_radius = UT.PLUIE_DE_SCUDS_IMPACT_RADIUS,
		impact_damage = UT.PLUIE_DE_SCUDS_IMPACT_DAMAGE,
		impact_push = UT.PLUIE_DE_SCUDS_IMPACT_PUSH,
		opponent = opponent_player,
		owner_side = owner_side,
	})
end

function ultra_helpers.spawn_laser_mesh_segment(min_x, min_y, max_x, max_y, opponent_player, owner_side)
	local start_point, end_point = ultra_helpers.random_line_clipped_to(min_x, min_y, max_x, max_y)
	table.insert(laser_meshes, {
		start_point = start_point,
		end_point = end_point,
		elapsed = 0.0,
		lifetime = UT.GRILLE_LASER_LIFETIME,
		damage_per_tick = UT.GRILLE_LASER_DAMAGE_PER_TICK,
		hit_timer = 0.0,
		target = opponent_player,
		owner_side = owner_side,
		thickness = UT.GRILLE_LASER_THICKNESS,
		-- 2026-10-05 (Camil: "chaque laser traverse hyper vite l'ecran
		-- pour s'installer"): the line is drawn (and hits) only from its
		-- start up to a "head" racing toward end_point over this long.
		sweep_duration = UT.GRILLE_LASER_SWEEP_DURATION,
	})
end

-- The 8 bespoke Ultra effects, keyed by caster character id — built
-- directly as table values (rather than 8 more named top-level locals,
-- again to stay well clear of the 200-local ceiling).
local ULTRA_EFFECTS = {
	-- Traqueur's Ultra — "La Meute": a guaranteed-floor hit plus a bigger,
	-- more aggressively-homing missile burst than her base kit (true 2D
	-- pursuit — see homing_full_turn in update_bullets()).
	missiles = function(caster, opponent)
		if apply_damage_and_check_round(opponent, caster.side, UT.LA_MEUTE_GUARANTEED_DAMAGE) then
			return
		end
		for i = 0, ULTRA_LA_MEUTE.projectile_count - 1 do
			local p = i / math.max(ULTRA_LA_MEUTE.projectile_count - 1, 1)
			local angle_offset = mathx.lerp(-ULTRA_LA_MEUTE.burst_spread_deg / 2.0, ULTRA_LA_MEUTE.burst_spread_deg / 2.0, p)
			if ULTRA_LA_MEUTE.burst_stagger > 0.0 and i > 0 then
				local side = caster.side
				timer.after(i * ULTRA_LA_MEUTE.burst_stagger, function()
					spawn_projectile(players[side + 1], ULTRA_LA_MEUTE, angle_offset)
				end)
			else
				spawn_projectile(caster, ULTRA_LA_MEUTE, angle_offset)
			end
		end
	end,

	-- Spreader's Ultra — "Pluie de Bonbons": COUNT candies dropped from
	-- above the OPPONENT's own half, each at a random X and a random (not
	-- evenly staggered — "un petit decalage" reads more like rain than a
	-- metronome) spawn delay, falling straight down regardless of side.
	mini = function(caster, opponent)
		if apply_damage_and_check_round(opponent, caster.side, UT.PLUIE_DE_BONBONS_GUARANTEED_DAMAGE) then
			return
		end
		local min_x = opponent.side == 0 and (ARENA_BOUNDS.position.x + UT.PLUIE_DE_BONBONS_MARGIN) or current_frontier_x
		local max_x = opponent.side == 0 and current_frontier_x or (ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x - UT.PLUIE_DE_BONBONS_MARGIN)
		local function spawn_drop(x)
			table.insert(bullets, {
				position = Vector2.new(x, current_arena_bounds.position.y - 20.0),
				velocity = Vector2.new(0.0, UT.PLUIE_DE_BONBONS_FALL_SPEED),
				owner_side = caster.side,
				damage = ULTRA_PLUIE_DE_BONBONS.damage,
				weapon_id = ULTRA_PLUIE_DE_BONBONS.id,
				homing_strength = 0.0,
				visual_scale = BULLET_VISUALS.ultra_pluie_de_bonbons.scale,
				lifetime = UT.PLUIE_DE_BONBONS_LIFETIME,
				-- 2026-10-05 (Camil: "les eventails tournent sur eux meme
				-- tres vite"): ~2x the base mini_shot's 900 deg/s spin, with
				-- a random start angle so the whole rain isn't in lockstep.
				spin_speed = 1900.0,
				rotation = math.random() * math.pi * 2.0,
			})
		end
		for _ = 1, UT.PLUIE_DE_BONBONS_COUNT do
			local x = min_x + math.random() * (max_x - min_x)
			local delay = math.random() * UT.PLUIE_DE_BONBONS_SPAWN_WINDOW
			if delay > 0.0 then
				timer.after(delay, function()
					spawn_drop(x)
				end)
			else
				spawn_drop(x)
			end
		end
	end,

	-- Mitrailleur's Ultra — "Mitrailleuses Satellites": a guaranteed-floor
	-- hit plus two escort turrets that follow him and echo his own normal
	-- machine-gun shots (real projectiles, his own sprite/damage — see
	-- echo_to_satellites()) rather than firing on their own.
	mitrailleur = function(caster, opponent)
		if apply_damage_and_check_round(opponent, caster.side, UT.MITRAILLEUSES_SATELLITES_GUARANTEED_DAMAGE) then
			return
		end
		local satellite_list = {}
		for _, offset_y in ipairs({ -UT.MITRAILLEUSES_SATELLITES_OFFSET_Y, UT.MITRAILLEUSES_SATELLITES_OFFSET_Y }) do
			local turret = {
				position = caster.ship.position + Vector2.new(0.0, offset_y),
				half_extents = TURRET.HALF_EXTENTS,
				owner_side = caster.side,
				weapon_id = ULTRA_MITRAILLEUSES_SATELLITES.id,
				damage = ULTRA_MITRAILLEUSES_SATELLITES.damage,
				hp = ULTRA_MITRAILLEUSES_SATELLITES.turret_hp,
				lifetime_left = ULTRA_MITRAILLEUSES_SATELLITES.turret_lifetime,
				fire_cooldown_period = 1.0 / ULTRA_MITRAILLEUSES_SATELLITES.fire_rate,
				fire_cooldown = 1.0 / ULTRA_MITRAILLEUSES_SATELLITES.fire_rate,
				bounce_cooldown = 0.0,
				flash_timer = 0.0,
				is_charged = false,
				autofire = false, -- never fires on its own — see echo_to_satellites()
				follow_player = caster,
				follow_offset = Vector2.new(0.0, offset_y),
			}
			table.insert(turrets, turret)
			table.insert(satellite_list, turret)
		end
		caster.satellite_turrets = satellite_list
	end,

	-- Perturbateur's Ultra — "Brouillage de commandes": a guaranteed-floor
	-- hit plus a long control-scramble, reducible by skill (a player who
	-- notices can consciously counter-invert their own inputs) even with
	-- no projectile burst at all.
	perturbateur = function(caster, opponent)
		if apply_damage_and_check_round(opponent, caster.side, UT.BROUILLAGE_GUARANTEED_DAMAGE) then
			return
		end
		apply_control_scramble(opponent, UT.BROUILLAGE_DURATION)
	end,

	lourd = function(caster, opponent)
		if apply_damage_and_check_round(opponent, caster.side, UT.PLUIE_DE_SCUDS_GUARANTEED_DAMAGE) then
			return
		end
		local min_x = opponent.side == 0 and (ARENA_BOUNDS.position.x + UT.PLUIE_DE_SCUDS_TARGET_MARGIN) or current_frontier_x
		local max_x = opponent.side == 0 and current_frontier_x or (ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x - UT.PLUIE_DE_SCUDS_TARGET_MARGIN)
		local min_y = ARENA_BOUNDS.position.y + UT.PLUIE_DE_SCUDS_TARGET_MARGIN
		local max_y = ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y - UT.PLUIE_DE_SCUDS_TARGET_MARGIN
		local side = caster.side
		for i = 0, UT.PLUIE_DE_SCUDS_MISSILE_COUNT - 1 do
			local target_position = Vector2.new(min_x + math.random() * (max_x - min_x), min_y + math.random() * (max_y - min_y))
			if i > 0 then
				timer.after(i * UT.PLUIE_DE_SCUDS_STAGGER, function()
					ultra_helpers.spawn_missile_strike(target_position, opponent_of(side), side)
				end)
			else
				ultra_helpers.spawn_missile_strike(target_position, opponent, side)
			end
		end
	end,

	controleur = function(caster, opponent)
		if apply_damage_and_check_round(opponent, caster.side, UT.TROU_NOIR_GUARANTEED_DAMAGE) then
			return
		end
		table.insert(black_holes, {
			position = ultra_helpers.half_center(opponent.side),
			radius = UT.TROU_NOIR_RADIUS,
			pull_speed = UT.TROU_NOIR_PULL_SPEED,
			slow_multiplier = UT.TROU_NOIR_SLOW_MULTIPLIER,
			outer_radius = UT.TROU_NOIR_OUTER_RADIUS,
			outer_slow_multiplier = UT.TROU_NOIR_OUTER_SLOW_MULTIPLIER,
			duration = UT.TROU_NOIR_DURATION,
			target = opponent,
			pulse_time = 0.0,
			frame_index = 1,
			frame_timer = UT.BLACK_HOLE_FRAME_DURATION,
		})
	end,

	zoneur = function(caster, opponent)
		if apply_damage_and_check_round(opponent, caster.side, UT.GRILLE_LASER_GUARANTEED_DAMAGE) then
			return
		end
		local min_x, max_x
		if opponent.side == 0 then
			min_x, max_x = ARENA_BOUNDS.position.x, current_frontier_x
		else
			min_x, max_x = current_frontier_x, ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x
		end
		local min_y, max_y = ARENA_BOUNDS.position.y, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y
		local stagger = UT.GRILLE_LASER_SPAWN_WINDOW / (UT.GRILLE_LASER_COUNT - 1)
		local side = caster.side
		for i = 0, UT.GRILLE_LASER_COUNT - 1 do
			if i > 0 then
				timer.after(i * stagger, function()
					ultra_helpers.spawn_laser_mesh_segment(min_x, min_y, max_x, max_y, opponent_of(side), side)
				end)
			else
				ultra_helpers.spawn_laser_mesh_segment(min_x, min_y, max_x, max_y, opponent, side)
			end
		end
	end,

	vif = function(caster, opponent)
		if apply_damage_and_check_round(opponent, caster.side, UT.BOURRASQUE_GUARANTEED_DAMAGE) then
			return
		end
		local direction = caster.side == 0 and 1.0 or -1.0
		for i = 1, #UT.BOURRASQUE_VORTEX_Y_FRACTIONS do
			local y_fraction = UT.BOURRASQUE_VORTEX_Y_FRACTIONS[i]
			local depth_offset = mathx.lerp(UT.BOURRASQUE_VORTEX_MIN_SPAWN_OFFSET, UT.BOURRASQUE_VORTEX_MAX_SPAWN_OFFSET, UT.BOURRASQUE_VORTEX_DEPTH_FRACTIONS[i])
			local spawn_x = caster.side == 0 and (ARENA_BOUNDS.position.x - depth_offset) or (ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x + depth_offset)
			local size_factor = UT.BOURRASQUE_VORTEX_SIZE_FACTORS[i]
			local vortex_velocity = Vector2.new(direction * UT.BOURRASQUE_VORTEX_START_SPEED * size_factor, 0.0)
			table.insert(bullets, {
				position = Vector2.new(spawn_x, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y * y_fraction),
				velocity = vortex_velocity,
				acceleration = UT.BOURRASQUE_VORTEX_ACCELERATION * size_factor,
				owner_side = caster.side,
				damage = UT.BOURRASQUE_VORTEX_DAMAGE,
				weapon_id = "ultra_bourrasque",
				homing_strength = 0.0,
				visual_scale = UT.BOURRASQUE_VORTEX_VISUAL_SCALE * size_factor,
				lifetime = UT.BOURRASQUE_VORTEX_LIFETIME,
				anim_textures = assets.bourrasque_vortex_frames,
				anim_frame_index = 1,
				anim_frame_timer = UT.BOURRASQUE_VORTEX_FRAME_DURATION,
				anim_frame_duration = UT.BOURRASQUE_VORTEX_FRAME_DURATION,
				-- 2026-10-05 (Camil: "il faudrait que les tourbillons
				-- avancent en sinusoide comme le tir normal") — same wave
				-- shape as the real Tourbillon shot (BASE_WEAPONS_BY_ID.
				-- vortex's own sine_amplitude/sine_angular_speed, so a
				-- retune of the normal shot's wave stays in sync), on top
				-- of Bourrasque's own speed-up-over-time (see the is_sine
				-- branch's `bullet.acceleration` handling in update_bullets()).
				is_sine = true,
				drift_velocity = vortex_velocity,
				sine_elapsed = 0.0,
				sine_amplitude = BASE_WEAPONS_BY_ID.vortex.sine_amplitude,
				sine_angular_speed = BASE_WEAPONS_BY_ID.vortex.sine_angular_speed,
			})
		end
		table.insert(wind_gusts, {
			target = opponent,
			duration = UT.BOURRASQUE_GUST_DURATION,
			total_duration = UT.BOURRASQUE_GUST_DURATION,
			push_speed_start = UT.BOURRASQUE_VORTEX_START_SPEED * UT.BOURRASQUE_GUST_PUSH_SCALE,
			push_speed_end = (UT.BOURRASQUE_VORTEX_START_SPEED + UT.BOURRASQUE_VORTEX_ACCELERATION * UT.BOURRASQUE_GUST_DURATION) * UT.BOURRASQUE_GUST_PUSH_SCALE,
		})
	end,
}

-- ultra_intro_node.gd's own timing/layout constants — a self-contained
-- presentation beat, kept separate from UT (that table is Ultra ABILITY
-- tuning; this is Ultra INTRO tuning). One table, not several top-level
-- locals — see UT's own doc comment on the 200-local ceiling.
local UI = {
	SLIDE_DURATION = 1.0 / 3.0,
	HOLD_DURATION = 1.0,
	BAR_Y = 250.0,
	BAR_HEIGHT = 180.0,
	IMAGE_W = 280.0, IMAGE_H = 420.0, -- ~2:3, matches the GDD's "grande image" ratio
	IMAGE_REST_X = 300.0, IMAGE_REST_Y = 340.0, -- left-of-center, vertically inside the bar's band
}

-- "quand un ultra se declenche, le jeu se met en pause. une barre blanche
-- et le mot 'ultra' arrivent de la droite, le perso en -image arrive de la
-- gauche. animation 1/3 seconde, reste statique 1 seconde, puis la barre
-- blanche et le 'ULTRA' sortent vers la gauche et le perso vers la droite
-- (1/3 seconde), le jeu se de-freeze et l'ULTRA se lance." The intro isn't
-- just decoration playing over the attack — it GATES it: resolve_ultra_
-- effect() only actually runs once slide-out finishes (see
-- update_ultra_intro() below), matching Godot's `await intro.finished`.
start_ultra_intro = function(caster, opponent)
	ultra_intro = {
		caster = caster,
		opponent = opponent,
		phase = "slide_in",
		phase_timer = UI.SLIDE_DURATION,
	}
end

local function update_ultra_intro(dt)
	ultra_intro.phase_timer = ultra_intro.phase_timer - dt
	if ultra_intro.phase_timer > 0.0 then
		return
	end
	if ultra_intro.phase == "slide_in" then
		ultra_intro.phase = "hold"
		ultra_intro.phase_timer = UI.HOLD_DURATION
	elseif ultra_intro.phase == "hold" then
		ultra_intro.phase = "slide_out"
		ultra_intro.phase_timer = UI.SLIDE_DURATION
	else -- slide_out finished
		local caster, opponent = ultra_intro.caster, ultra_intro.opponent
		ultra_intro = nil
		resolve_ultra_effect(caster, opponent)
	end
end

-- Geometry helpers scoped INSIDE draw_ultra_intro (not top-level locals —
-- again the 200-local ceiling) since nothing outside this one function
-- needs them.
local function draw_ultra_intro()
	local function slide_t()
		return 1.0 - mathx.clampf(ultra_intro.phase_timer / UI.SLIDE_DURATION, 0.0, 1.0)
	end
	local function bar_left_x()
		if ultra_intro.phase == "slide_in" then
			return mathx.lerp(1280.0, 0.0, slide_t()) -- arrives from the right
		elseif ultra_intro.phase == "slide_out" then
			return mathx.lerp(0.0, -1280.0, slide_t()) -- exits to the left
		end
		return 0.0 -- hold
	end
	local function character_left_x()
		local rest_x = UI.IMAGE_REST_X - UI.IMAGE_W / 2.0
		if ultra_intro.phase == "slide_in" then
			return mathx.lerp(-UI.IMAGE_W, rest_x, slide_t()) -- arrives from the left
		elseif ultra_intro.phase == "slide_out" then
			return mathx.lerp(rest_x, 1280.0, slide_t()) -- exits to the right
		end
		return rest_x -- hold
	end

	local bar_x = bar_left_x()
	love.graphics.setColor(1, 1, 1)
	love.graphics.rectangle("fill", bar_x, UI.BAR_Y, 1280.0, UI.BAR_HEIGHT)
	love.graphics.setColor(0.05, 0.05, 0.08)
	love.graphics.setLineWidth(5.0)
	love.graphics.rectangle("line", bar_x, UI.BAR_Y, 1280.0, UI.BAR_HEIGHT)
	love.graphics.setLineWidth(1.0)

	-- Real sized Font (fonts.lua), not the default font scaled up — see
	-- that module's own doc comment on why (2026-09-13 blurry-text bug).
	local ultra_font = fonts.get(72)
	love.graphics.setFont(ultra_font)
	love.graphics.setColor(0.08, 0.08, 0.1)
	love.graphics.print("ULTRA", bar_x + 1280.0 / 2.0, UI.BAR_Y + UI.BAR_HEIGHT / 2.0, 0, 1, 1, ultra_font:getWidth("ULTRA") / 2.0, ultra_font:getHeight() / 2.0)
	love.graphics.setFont(fonts.default)

	-- Boss masked identity (ship_node.gd's BOSS_INTRO_TEXTURE_CANDIDATES):
	-- prefers a full-body pose, falls back to the portrait — organisateur
	-- has no full.png, same "art drops in as it's ready" convention as
	-- draw_ship()'s own fallback chain.
	local art = boss_helpers.is_ship(ultra_intro.caster) and assets.organisateur or assets.characters[ultra_intro.caster.character.id]
	local intro_image = art and (art.full or art.portrait)
	if intro_image then
		love.graphics.setColor(1, 1, 1)
		local char_x = character_left_x()
		draw_utils.draw_stretched(intro_image, char_x + UI.IMAGE_W / 2.0, UI.IMAGE_REST_Y, UI.IMAGE_W, UI.IMAGE_H)
	end
end

resolve_ultra_effect = function(caster, opponent)
	caster.ultra_flash_timer = ULTRA_MISC.FLASH_DURATION
	local effect = ULTRA_EFFECTS[caster.character.id]
	if effect then
		effect(caster, opponent)
	else
		apply_damage_and_check_round(opponent, caster.side, ULTRA_MISC.GENERIC_ULTRA_DAMAGE)
	end
	-- Epic 4 reward system: Perturbateur's passive, unlike every other
	-- reward, isn't tied to a timer or weapon id at all — reactive,
	-- re-checked live every time THIS ship triggers ITS OWN Ultra (any
	-- character's), stacking a short control-scramble onto whatever that
	-- Ultra already did. Re-fetches the opponent fresh (not the possibly-
	-- now-stale `opponent` param) in case `effect` just ended the round.
	for _, unlock_id in ipairs(campaign_save.unlocks_for(caster.character.id)) do
		if unlock_id == "stun_boomerang" then
			apply_control_scramble(opponent_of(caster.side), UT.PASSIVE_PERTURBATEUR_ULTRA_SCRAMBLE_DURATION)
			break
		end
	end
end

-- Epic 4 reward system: built once per match by match_arena.enter() (see
-- passive_state's own doc comment). Vif's speed bonus is permanent (no
-- timer); Perturbateur's is reactive (handled above in resolve_ultra_
-- effect() instead); everything else gets a periodic Timer-equivalent.
build_passive_state = function(character)
	local state = { timers = {}, speed_multiplier = 1.0 }
	for _, unlock_id in ipairs(campaign_save.unlocks_for(character.id)) do
		if unlock_id == "vortex" then
			state.speed_multiplier = UT.PASSIVE_VIF_SPEED_MULTIPLIER
		elseif unlock_id == "stun_boomerang" then
			-- reactive, nothing to wire up in advance — see resolve_ultra_effect()
		else
			local weapon = BASE_WEAPONS_BY_ID[unlock_id]
			if weapon and weapon.passive_interval > 0.0 then
				table.insert(state.timers, { weapon = weapon, elapsed = weapon.passive_interval })
			end
		end
	end
	return state
end

local function spawn_floating_text(position, text, color)
	table.insert(floating_texts, { position = position, text = text, color = color, age = 0.0, duration = 1.0 })
end

-- Ball-miss travel effect (gauge_fill_effect_node.gd, 2026-08-15, Camil:
-- "une petite boule va de l'endroit ou la balle a ete perdue jusqu'a la
-- jauge... et c'est en 'touchant' le joueur que le '+50' apparait"). A
-- single gold ball arcs from the loss point toward an approximate on-HUD
-- gauge anchor, while several tiny white dots fly straight at the ship
-- that just won the point — the "+X" popup (spawn_floating_text(), already
-- built for Spreader's heal) fires once they actually arrive rather than
-- instantly. The sparkle-trail resampling behind both travelers isn't
-- ported (diminishing returns — plain shapes already sell "something just
-- traveled here").
local GFX = {
	DURATION = 1.0,
	MINI_BALL_COUNT = 7,
	MINI_BALL_STAGGER = 0.04,
	ARC_HEIGHT = 60.0,
	MINI_BALL_SPREAD = 40.0,
}

-- Quadratic bezier (a -> control -> b at t) — gauge_fill_effect_node.gd's
-- own _bezier(), ported directly (Vector2 has no built-in :lerp() here).
local function bezier2(a, control, b, t)
	local p1 = a + (control - a) * t
	local p2 = control + (b - control) * t
	return p1 + (p2 - p1) * t
end

local function spawn_gauge_fill_effect(loss_position, target_player, fill_amount, send_gauge_ball)
	local gauge_anchor_x = target_player.side == 0 and (ARENA_BOUNDS.position.x + 80.0) or (ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x - 80.0)
	table.insert(gauge_fill_effects, {
		loss_position = loss_position,
		gauge_anchor = Vector2.new(gauge_anchor_x, 40.0), -- matches draw_player_hud()'s own gauge bar position
		target_player = target_player,
		fill_amount = fill_amount,
		send_gauge_ball = send_gauge_ball,
		elapsed = 0.0,
	})
end

local function update_gauge_fill_effects(dt)
	local i = 1
	while i <= #gauge_fill_effects do
		local fx = gauge_fill_effects[i]
		fx.elapsed = fx.elapsed + dt
		if fx.elapsed >= GFX.DURATION then
			spawn_floating_text(
				fx.target_player.ship.position + Vector2.new(0.0, -fx.target_player.ship.half_extents.y),
				string.format("+%d", fx.fill_amount),
				{ 1.0, 0.9, 0.4, 1.0 }
			)
			table.remove(gauge_fill_effects, i)
		else
			i = i + 1
		end
	end
end

local function draw_gauge_fill_effects()
	love.graphics.setColor(1, 1, 1)
	for _, fx in ipairs(gauge_fill_effects) do
		local t = mathx.clampf(fx.elapsed / GFX.DURATION, 0.0, 1.0)
		local eased = t * t -- "avec une acceleration" — visibly speeds up over the flight

		if fx.send_gauge_ball then
			local mid = (fx.loss_position + fx.gauge_anchor) * 0.5
			local dir = fx.gauge_anchor - fx.loss_position
			local perp = Vector2.new(-dir.y, dir.x):normalized()
			local control = mid + perp * GFX.ARC_HEIGHT
			local ball_pos = bezier2(fx.loss_position, control, fx.gauge_anchor, eased)
			love.graphics.setColor(1.0, 0.9, 0.4, 1.0)
			love.graphics.circle("fill", ball_pos.x, ball_pos.y, 5.0)
		end

		local target_pos = fx.target_player.ship.position
		local dot_dir = target_pos - fx.loss_position
		if dot_dir:length() > 0.01 then
			local dot_perp = Vector2.new(-dot_dir.y, dot_dir.x):normalized()
			for i = 0, GFX.MINI_BALL_COUNT - 1 do
				local delay = i * GFX.MINI_BALL_STAGGER
				local local_duration = GFX.DURATION - delay
				if local_duration > 0.0 then
					local local_t = mathx.clampf((fx.elapsed - delay) / local_duration, 0.0, 1.0)
					if local_t > 0.0 then
						local local_eased = local_t * local_t
						local fan = GFX.MINI_BALL_COUNT > 1 and mathx.lerp(-GFX.MINI_BALL_SPREAD, GFX.MINI_BALL_SPREAD, i / (GFX.MINI_BALL_COUNT - 1)) or 0.0
						local dot_mid = (fx.loss_position + target_pos) * 0.5 + dot_perp * fan
						local dot_pos = bezier2(fx.loss_position, dot_mid, target_pos, local_eased)
						love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
						love.graphics.rectangle("fill", dot_pos.x - 1.0, dot_pos.y - 1.0, 2.0, 2.0)
					end
				end
			end
		end
	end
end

-- Fires one unlocked PERIODIC passive reward, no player input at all.
-- Dispatches by weapon id into 6 bespoke effects (2026-08-16 same-day
-- rework, "il faut etre plus creatif" — the first pass had every one
-- reduce to "auto-fire this weapon's own shot"), each still tied to that
-- character's own established identity/Ultra. Weapon/entity-based ones
-- fire/land with no aim assist (the vertical laser is the exception —
-- it covers real space rather than needing to be aimed); the heal always
-- lands.
local function fire_passive_reward(ship, weapon)
	-- match_arena_node.gd gates this on `_round_playing`, which is false
	-- only during the pre-round "Pret ?" freeze (this port has no
	-- equivalent gate at all — rounds start immediately) or once the
	-- match itself has concluded — NOT during the brief ball-serve delay
	-- within an ongoing round, which is a different, much shorter pause
	-- this port's own `serving` flag tracks. match.match_over is the
	-- closest faithful equivalent.
	if match.match_over then
		return
	end
	local opponent = opponent_of(ship.side)
	if weapon.id == "turret" then
		spawn_turret(ship, weapon, false, UT.PASSIVE_TURRET_LIFETIME)
	elseif weapon.id == "machine_gun" then
		-- 2026-08-22 rework: a real 4-shot burst of the exact normal
		-- machine_gun projectile (same sprite/damage), staggered at the
		-- gun's own natural fire interval — not a self-firing module.
		local stagger = 1.0 / weapon.fire_rate
		local side = ship.side
		for i = 0, UT.PASSIVE_MITRAILLEUR_BURST_COUNT - 1 do
			if i == 0 then
				spawn_projectile(ship, weapon, 0.0)
			else
				timer.after(i * stagger, function()
					spawn_projectile(players[side + 1], weapon, 0.0)
				end)
			end
		end
	elseif weapon.id == "bazooka" then
		-- Two Pluie-de-Scuds-style strikes, each its own random point.
		local min_x = opponent.side == 0 and (ARENA_BOUNDS.position.x + UT.PLUIE_DE_SCUDS_TARGET_MARGIN) or current_frontier_x
		local max_x = opponent.side == 0 and current_frontier_x or (ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x - UT.PLUIE_DE_SCUDS_TARGET_MARGIN)
		local min_y = ARENA_BOUNDS.position.y + UT.PLUIE_DE_SCUDS_TARGET_MARGIN
		local max_y = ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y - UT.PLUIE_DE_SCUDS_TARGET_MARGIN
		for _ = 1, 2 do
			ultra_helpers.spawn_missile_strike(
				Vector2.new(min_x + math.random() * (max_x - min_x), min_y + math.random() * (max_y - min_y)),
				opponent, ship.side
			)
		end
	elseif weapon.id == "laser" then
		-- A vertical wall top-to-bottom of the opponent's half, sweeping
		-- toward whichever edge (center line or back wall) it's farther
		-- from, timed to arrive exactly as its lifetime runs out.
		local half_min_x, half_max_x
		if opponent.side == 0 then
			half_min_x, half_max_x = ARENA_BOUNDS.position.x, current_frontier_x
		else
			half_min_x, half_max_x = current_frontier_x, ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x
		end
		local random_x = half_min_x + math.random() * (half_max_x - half_min_x)
		local center_edge_x = current_frontier_x
		local back_edge_x = mathx.is_equal_approx(center_edge_x, half_min_x) and half_max_x or half_min_x
		local target_edge_x = (math.abs(random_x - center_edge_x) < math.abs(random_x - back_edge_x)) and back_edge_x or center_edge_x
		table.insert(laser_meshes, {
			start_point = Vector2.new(random_x, ARENA_BOUNDS.position.y),
			end_point = Vector2.new(random_x, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y),
			elapsed = 0.0,
			lifetime = UT.GRILLE_LASER_LIFETIME,
			damage_per_tick = UT.GRILLE_LASER_DAMAGE_PER_TICK,
			hit_timer = 0.0,
			target = opponent,
			owner_side = ship.side,
			thickness = UT.GRILLE_LASER_THICKNESS,
			horizontal_velocity = (target_edge_x - random_x) / UT.GRILLE_LASER_LIFETIME,
		})
	elseif weapon.id == "homing_missile" then
		spawn_projectile(ship, weapon, 0.0)
	elseif weapon.id == "mini_shot" then
		local heal_amount = ship.max_hp * UT.PASSIVE_SPREADER_HEAL_FRACTION
		ship.ship = ship_state.healed(ship.ship, heal_amount, ship.max_hp)
		spawn_floating_text(ship.ship.position + Vector2.new(0.0, -ship.ship.half_extents.y), string.format("+%d", heal_amount), UT.PASSIVE_HEAL_POPUP_COLOR)
		-- passive_heal_fx_node.gd (2026-08-16, Camil: "un eventail apparait
		-- et tourne autour du joueur... et lui redonne 15% de PV") — purely
		-- cosmetic, the heal itself already landed above.
		table.insert(heal_fx, { player = ship, elapsed = 0.0 })
	end
end

local function update_passive_rewards(dt)
	if match.match_over then
		return
	end
	for side = 0, 1 do
		local state = passive_state[side + 1]
		for _, entry in ipairs(state.timers) do
			entry.elapsed = entry.elapsed - dt
			if entry.elapsed <= 0.0 then
				entry.elapsed = entry.weapon.passive_interval
				fire_passive_reward(players[side + 1], entry.weapon)
			end
		end
	end
end

local function update_floating_texts(dt)
	local i = 1
	while i <= #floating_texts do
		local text = floating_texts[i]
		text.age = text.age + dt
		if text.age >= text.duration then
			table.remove(floating_texts, i)
		else
			i = i + 1
		end
	end
end

-- Spreader's passive heal flourish (passive_heal_fx_node.gd) — purely
-- cosmetic bookkeeping; the actual heal already landed the instant this
-- was spawned (fire_passive_reward()).
local function update_heal_fx(dt)
	local i = 1
	while i <= #heal_fx do
		local fx = heal_fx[i]
		fx.elapsed = fx.elapsed + dt
		if fx.elapsed >= UT.PASSIVE_SPREADER_FAN_DURATION then
			table.remove(heal_fx, i)
		else
			i = i + 1
		end
	end
end

-- "Parented to the ship" in Godot just means "orbit its LIVE position every
-- frame" here — same two-full-orbits-then-fade shape as passive_heal_fx_
-- node.gd's own _physics_process().
local function draw_heal_fx()
	for _, fx in ipairs(heal_fx) do
		local t = fx.elapsed / UT.PASSIVE_SPREADER_FAN_DURATION
		local angle = t * math.pi * 2.0 * 2.0 -- two full orbits over the whole duration
		local x = fx.player.ship.position.x + math.cos(angle) * UT.PASSIVE_SPREADER_FAN_RADIUS
		local y = fx.player.ship.position.y + math.sin(angle) * UT.PASSIVE_SPREADER_FAN_RADIUS
		love.graphics.setColor(1, 1, 1, 1.0 - t)
		draw_utils.draw_scaled(assets.bullets.mini_shot, x, y, 0.8)
	end
	love.graphics.setColor(1, 1, 1)
end

-- Dev-only cheat keys for faster manual testing (2026-08-13): K instantly
-- kills the opponent, U maxes P1's ultra meter (skip grinding 5 real
-- misses), M fills P1's ammo/weapon gauges to 100. Gated the same way
-- match_arena_node.gd gates them (_round_playing) — not during the ready
-- gate/pause/an Ultra intro/after match_over, where a kill or gauge-fill
-- would do something undefined.
local function update_cheat_keys()
	local kill_pressed = love.keyboard.isScancodeDown("k")
	if kill_pressed and not cheat_state.kill_prev then
		apply_damage_and_check_round(players[2], 0, players[2].ship.hp)
	end
	cheat_state.kill_prev = kill_pressed

	local ultra_pressed = love.keyboard.isScancodeDown("u")
	if ultra_pressed and not cheat_state.ultra_prev then
		while not weapon_system_state.ultra_ready(players[1].weapon) do
			players[1].weapon = weapon_system_state.with_ultra_pip_added(players[1].weapon)
		end
	end
	cheat_state.ultra_prev = ultra_pressed

	local ammo_pressed = love.keyboard.isScancodeDown("m")
	if ammo_pressed and not cheat_state.ammo_prev then
		for i = 0, #players[1].character.kit - 1 do
			players[1].weapon = weapon_system_state.with_gauge_added(players[1].weapon, players[1].weapon.kit[i + 1].gauge_max, i)
		end
	end
	cheat_state.ammo_prev = ammo_pressed
end

-- Story 1.12 bug report (2026-08-08): "si j'appuie sur F1 en mode
-- campagne, l'IA se desactive" — a campaign mook/rival/organizer has no
-- second human to hand control to, ever, so F1 must be a no-op there
-- instead of turning the opponent off.
local function update_ai_toggle()
	if campaign_mode then
		return
	end
	local pressed = love.keyboard.isScancodeDown("f1")
	if pressed and not cheat_state.ai_toggle_prev then
		players[2].is_ai = not players[2].is_ai
	end
	cheat_state.ai_toggle_prev = pressed
end

local function update_bullets(dt)
	local i = 1
	while i <= #bullets do
		local bullet = bullets[i]
		local target = opponent_of(bullet.owner_side)
		local remove = false
		local handled = false -- true once an enemy turret has already consumed this bullet this frame

		-- Generic projectile self-spin (WeaponData.projectile_spin_speed —
		-- mini_shot/ultra_pluie_de_bonbons/stun_boomerang); 0 for every other
		-- weapon, a harmless no-op. Ticked unconditionally (boomerang or not)
		-- since stun_boomerang itself is the one is_boomerang weapon that
		-- actually sets it.
		if bullet.spin_speed and bullet.spin_speed ~= 0.0 then
			bullet.rotation = bullet.rotation + mathx.deg_to_rad(bullet.spin_speed) * dt
		end

		if bullet.is_boomerang then
			remove = update_boomerang(bullet, dt)
			-- Perturbateur's charged Boomerang de Feu: drops a fire puddle
			-- every FIRE_TRAIL.DROP_INTERVAL of flight, both legs ("derriere
			-- lui" doesn't distinguish outbound from return).
			if bullet.leaves_fire_trail then
				bullet.fire_trail_timer = bullet.fire_trail_timer - dt
				if bullet.fire_trail_timer <= 0.0 then
					bullet.fire_trail_timer = FIRE_TRAIL.DROP_INTERVAL
					spawn_fire_trail(bullet.position, target, bullet.owner_side)
				end
			end
			-- 2026-09-27 (Camil: "j'ai l'impression que l'arme de
			-- Perturbateur ne touche pas les tourelles") — confirmed: this
			-- whole is_boomerang branch never checked turrets at all (only
			-- the generic non-boomerang branch below did). Same once-per-leg
			-- idea as the ship hit (see the "can_hit"/point_in_ship(target.
			-- ship, ...) block further down), gated by its own separate
			-- flags so a leg that already hit the ship can still also hit a
			-- turret in its path (or vice versa) — the boomerang isn't
			-- destroyed by either, same as before.
			for _, turret in ipairs(turrets) do
				if turret.owner_side ~= bullet.owner_side and turret.hp > 0.0 then
					local turret_can_hit = (bullet.boomerang_returning and not bullet.boomerang_turret_hit_return)
						or (not bullet.boomerang_returning and not bullet.boomerang_turret_hit_outbound)
					if turret_can_hit and point_in_ship(turret, bullet.position) then
						turret.hp = turret.hp - bullet.damage
						turret.flash_timer = TURRET.FLASH_DURATION
						spawn_impact(bullet.position, bullet.weapon_id)
						if bullet.boomerang_returning then
							bullet.boomerang_turret_hit_return = true
						else
							bullet.boomerang_turret_hit_outbound = true
						end
						break
					end
				end
			end
		else
			if bullet.is_sine then
				-- Vif's Tourbillon: velocity is recomputed every frame as the
				-- captured drift + a perpendicular component that oscillates
				-- sinusoidally — position integrates cleanly without drifting
				-- off-axis (same trick as a boomerang's fixed arc).
				bullet.sine_elapsed = bullet.sine_elapsed + dt
				if bullet.acceleration and bullet.acceleration ~= 0.0 then
					-- 2026-10-05 (Camil: "il faudrait que les tourbillons de
					-- l'ultra avancent en sinusoide comme le tir normal") —
					-- Bourrasque's own vortices now also use is_sine, but
					-- (unlike the normal Tourbillon shot) they keep speeding
					-- up the whole flight: growing the drift's magnitude here
					-- instead of a fixed one preserves that escalation.
					bullet.drift_velocity = bullet.drift_velocity + bullet.drift_velocity:normalized() * bullet.acceleration * dt
				end
				local wave_angle = mathx.deg_to_rad(bullet.sine_angular_speed) * bullet.sine_elapsed
				local drift_dir = bullet.drift_velocity:normalized()
				local perp = Vector2.new(-drift_dir.y, drift_dir.x)
				local lateral_speed = bullet.sine_amplitude * mathx.deg_to_rad(bullet.sine_angular_speed) * math.cos(wave_angle)
				bullet.velocity = bullet.drift_velocity + perp * lateral_speed
			elseif bullet.homing_full_turn and bullet.homing_strength > 0.0 then
				-- Traqueur's Ultra "La Meute": true 2D pursuit — the WHOLE
				-- velocity vector rotates toward the target at up to
				-- homing_strength rad/s, speed preserved, so a target behind
				-- the missile pulls it into a real U-turn (projectile_node.
				-- gd's homing_full_turn branch).
				local speed = bullet.velocity:length()
				if speed > 0.01 then
					local current_dir = bullet.velocity * (1.0 / speed)
					local desired_dir = (target.ship.position - bullet.position):normalized()
					local max_turn = bullet.homing_strength * dt
					local turn = mathx.clampf(wrap_angle(desired_dir:angle() - current_dir:angle()), -max_turn, max_turn)
					bullet.velocity = current_dir:rotated(turn) * speed
				end
			elseif bullet.homing_strength and bullet.homing_strength > 0.0 then
				-- Bazooka's homing (projectile_node.gd's non-full-turn
				-- branch): only the VERTICAL speed steers toward the target,
				-- horizontal speed never changes — it can track height but
				-- never turn around.
				local desired_vy = mathx.clampf((target.ship.position.y - bullet.position.y) * 2.0, -260.0, 260.0)
				local new_vy = mathx.lerp(bullet.velocity.y, desired_vy, mathx.clampf(bullet.homing_strength * dt, 0.0, 1.0))
				bullet.velocity = Vector2.new(bullet.velocity.x, new_vy)
			elseif bullet.acceleration and bullet.acceleration ~= 0.0 and bullet.velocity:length() > 0.01 then
				-- Vif's Ultra "Bourrasque": the vortex swarm speeds up the
				-- whole way across the arena (projectile_node.gd's generic
				-- `acceleration` field — direction held, speed grows).
				bullet.velocity = bullet.velocity + bullet.velocity:normalized() * bullet.acceleration * dt
			end
			-- Generic sprite flipbook (Bourrasque's wind1/wind2/wind3 cycle —
			-- see turret_node.gd's own SPRITE_FRAME_DURATION pattern, reused
			-- generically here rather than one-off per weapon).
			if bullet.anim_textures then
				bullet.anim_frame_timer = bullet.anim_frame_timer - dt
				if bullet.anim_frame_timer <= 0.0 then
					bullet.anim_frame_timer = bullet.anim_frame_duration
					bullet.anim_frame_index = (bullet.anim_frame_index % #bullet.anim_textures) + 1
				end
			end
			local bullet_x_before_move = bullet.position.x
			bullet.position = bullet.position + bullet.velocity * dt
			-- projectile_node.gd actually has NO arena-bounds cleanup at
			-- all — only a hit, a boomerang catch, or `lifetime <= 0.0`
			-- ever despawns one. This x-bounds check is this port's OWN
			-- safety net for ordinary weapons (which never spawn off-
			-- screen), so it must skip anything that already manages its
			-- own lifetime-based cleanup — Vif's Ultra "Bourrasque"
			-- deliberately spawns its vortices OFF-SCREEN behind the outer
			-- wall on purpose; without this guard they'd read as
			-- "immediately out of bounds" and vanish the same frame they
			-- spawn, before ever crossing into the visible arena.
			if not bullet.lifetime then
				local out_of_bounds = bullet.position.x < ARENA_BOUNDS.position.x - 32.0
					or bullet.position.x > ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x + 32.0
				if out_of_bounds then
					remove = true
				end
			end
			-- Spreader's Ultra "Pluie de Bonbons" (and now Bourrasque's
			-- vortices): a hard timeout mirrors ProjectileNode's generic
			-- `lifetime` field for anything that doesn't despawn some
			-- other way first (a hit, a wall, a catch).
			if bullet.lifetime then
				bullet.lifetime = bullet.lifetime - dt
				if bullet.lifetime <= 0.0 then
					remove = true
				end
			end

			-- 2026-09-27 (Camil, after a screenshot showing a vertical column
			-- of trigger marks all at the TARGET's own X: "le missile doit
			-- exploser quand il arrive a la meme position [horizontale] du
			-- vaisseau ennemi (uniquement)") — every bazooka bullet (normal
			-- AND charged, "doit fonctionner pour le tir charge de lourd
			-- egalement") detonates the instant it reaches the depth (X) of
			-- any enemy ship or turret, at whatever height it currently is.
			-- Turret splash is still an instant "within radius" check
			-- (turrets don't move); the SHIP only takes damage if it
			-- actually touches one of the explosion's own flying fragments
			-- during its lifetime (see update_impacts()) — no separate
			-- instant ship check needed here.
			if not remove and bullet.weapon_id == "bazooka" then
				local aligned = x_aligned(bullet_x_before_move, bullet.position.x, target.ship.position.x)
				if not aligned then
					for _, turret in ipairs(turrets) do
						if turret.owner_side ~= bullet.owner_side and turret.hp > 0.0
							and x_aligned(bullet_x_before_move, bullet.position.x, turret.position.x) then
							aligned = true
							break
						end
					end
				end
				if aligned then
					spawn_impact(bullet.position, "bazooka", bullet.owner_side, bullet.damage)
					for _, turret in ipairs(turrets) do
						if turret.owner_side ~= bullet.owner_side and turret.hp > 0.0
							and turret.position:distance_to(bullet.position) <= BIG_EXPLOSION_RADIUS then
							turret.hp = turret.hp - bullet.damage
							turret.flash_timer = TURRET.FLASH_DURATION
						end
					end
					remove = true
					handled = true
				end
			end

			-- Controleur's turret sits in the path of incoming enemy fire —
			-- any enemy projectile passing through it chips its hp instead of
			-- reaching the ship behind it. (Boomerangs skip this for now —
			-- no ported character combo exercises that combination yet.)
			if not remove then
				for _, turret in ipairs(turrets) do
					if turret.owner_side ~= bullet.owner_side and turret.hp > 0.0 and point_in_ship(turret, bullet.position) then
						turret.hp = turret.hp - bullet.damage
						turret.flash_timer = TURRET.FLASH_DURATION
						spawn_impact(bullet.position, bullet.weapon_id)
						remove = true
						handled = true
						break
					end
				end
			end
		end

		if not handled then
			-- A boomerang can land once per leg (outbound, then return)
			-- instead of despawning on its first hit like every other
			-- projectile.
			local can_hit = true
			if bullet.is_boomerang then
				can_hit = (bullet.boomerang_returning and not bullet.boomerang_hit_return)
					or (not bullet.boomerang_returning and not bullet.boomerang_hit_outbound)
			end

			-- Vif's "Saut": while airborne (dash_invuln_timer), the ship isn't
			-- just immune to damage — Camil, after seeing bullets still spark
			-- and vanish on contact: "pendant le saut, les tirs adversaires
			-- passent dessous". No collision at all, so they visibly fly
			-- straight through/under him instead of looking "blocked".
			local jumping = target.dash_invuln_timer and target.dash_invuln_timer > 0.0
			if not jumping and can_hit and point_in_ship(target.ship, bullet.position) then
				spawn_impact(bullet.position, bullet.weapon_id)
				if bullet.is_boomerang then
					if bullet.boomerang_returning then
						bullet.boomerang_hit_return = true
					else
						bullet.boomerang_hit_outbound = true
					end
				else
					remove = true
				end
				if apply_damage_and_check_round(target, bullet.owner_side, bullet.damage) then
					return -- round/match state just changed under us — bail out this frame
				end
			end
		end

		if remove then
			table.remove(bullets, i)
		else
			i = i + 1
		end
	end
end

-- Controleur's turret: ticks its own lifetime/cooldown and fires
-- autonomously at the opponent's CURRENT position (re-aimed fresh each
-- shot, then flies straight — not homing). Removed once its lifetime runs
-- out or an enemy projectile chips it down to 0 hp (see update_bullets()).
-- 2026-10-06 dash feature: Contrôleur's phantom paddle / Perturbateur's
-- mirror decoy — a stationary hitbox with its own lifetime (independently
-- also zeroed out the instant it bounces a ball, see resolve_ball_physics()).
local function update_ghost_paddles(dt)
	local i = 1
	while i <= #ghost_paddles do
		local ghost = ghost_paddles[i]
		if ghost.velocity then
			-- Mitrailleur's thrown clone — the only moving ghost_paddle; a
			-- stationary one (Contrôleur's/Perturbateur's) has no velocity set.
			ghost.position = ghost.position + ghost.velocity * dt
		end
		ghost.lifetime = ghost.lifetime - dt
		if ghost.lifetime <= 0.0 then
			table.remove(ghost_paddles, i)
		else
			i = i + 1
		end
	end
end

local function update_turrets(dt)
	local i = 1
	while i <= #turrets do
		local turret = turrets[i]
		turret.lifetime_left = turret.lifetime_left - dt
		turret.flash_timer = math.max(turret.flash_timer - dt, 0.0)
		if turret.lifetime_left <= 0.0 or turret.hp <= 0.0 then
			table.remove(turrets, i)
		else
			-- Mitrailleur's Ultra satellites (2026-08-15): "elles doivent
			-- suivre le vaisseau" — locked to their owner's position every
			-- tick instead of staying put like Controleur's own turret.
			if turret.follow_player then
				turret.position = turret.follow_player.ship.position + turret.follow_offset
			end
			if turret.autofire then
				turret.fire_cooldown = turret.fire_cooldown - dt
				if turret.fire_cooldown <= 0.0 then
					local target = opponent_of(turret.owner_side)
					local aim = (target.ship.position - turret.position):normalized()
					table.insert(bullets, {
						position = turret.position,
						velocity = aim * TURRET.SHOT_SPEED,
						owner_side = turret.owner_side,
						damage = turret.damage,
						weapon_id = turret.weapon_id,
						homing_strength = 0.0,
						visual_scale = (BULLET_VISUALS[turret.weapon_id] or BULLET_VISUALS.machine_gun).scale,
					})
					turret.fire_cooldown = turret.fire_cooldown_period
				end
			end
			i = i + 1
		end
	end
end

local function update_impacts(dt)
	local i = 1
	while i <= #impacts do
		local impact = impacts[i]
		impact.age = impact.age + dt
		-- 2026-09-27 (Camil: "si le vaisseau touche l'un des fragments de
		-- l'explosion, ca lui fait des degats") — Lourd's bazooka
		-- "big_explosion" (see spawn_impact()) is the only impact style with
		-- real gameplay behind it: while it's still alive, its own flying
		-- debris (impact.particles) can tag the opponent's ship, dealing
		-- damage once per explosion (not once per fragment, so lingering in
		-- a spray of them doesn't stack absurdly). `impact.owner_side` is
		-- nil for every other spawn_impact() caller (every other weapon,
		-- plus Lourd's Ultra missile-strike flash, which already deals its
		-- own damage separately) — this whole block is a no-op for those.
		if impact.owner_side ~= nil then
			local victim = opponent_of(impact.owner_side)
			if not impact.hit_sides[victim.side] then
				for _, vel in ipairs(impact.particles) do
					local fragment_pos = impact.position + vel * impact.age
					if point_in_ship(victim.ship, fragment_pos) then
						impact.hit_sides[victim.side] = true
						if apply_damage_and_check_round(victim, impact.owner_side, impact.damage) then
							return -- round/match state just changed under us — bail out this frame
						end
						break
					end
				end
			end
		end
		if impact.age >= impact.duration then
			table.remove(impacts, i)
		else
			i = i + 1
		end
	end
end

-- Perturbateur's charged Boomerang de Feu puddle: lingers for
-- FIRE_TRAIL.LIFETIME, ticking damage into the victim (repeatedly, not a
-- single hit) at FIRE_TRAIL.TICK_INTERVAL while they stand inside it, and
-- lets the particle system's own already-spawned particles finish out
-- their lifetime (rather than vanishing mid-flicker) once it enters its
-- own fade-out window.
local function update_fire_trails(dt)
	local i = 1
	while i <= #fire_trails do
		local trail = fire_trails[i]
		trail.lifetime = trail.lifetime - dt
		if trail.lifetime <= 0.0 then
			table.remove(fire_trails, i)
		else
			if not trail.fading and trail.lifetime < FIRE_TRAIL.FADE_OUT_DURATION then
				trail.fading = true
				trail.particle_system:stop()
			end
			trail.particle_system:update(dt)
			trail.tick_cooldown = math.max(trail.tick_cooldown - dt, 0.0)
			-- `victim` and `fire_trails` are always reset together on a round
			-- transition (start_new_round()/apply_damage_and_check_round()),
			-- so this can never end up pointing at a stale player table —
			-- no Godot-style is_instance_valid() guard needed here.
			if trail.tick_cooldown <= 0.0 then
				local ticked = false
				local half_extents = trail.victim.ship.half_extents
				local dx = math.abs(trail.victim.ship.position.x - trail.position.x)
				local dy = math.abs(trail.victim.ship.position.y - trail.position.y)
				if dx < FIRE_TRAIL.RADIUS + half_extents.x and dy < FIRE_TRAIL.RADIUS + half_extents.y then
					ticked = true
					-- 2026-09-27 (Camil: "il faudrait un indicateur visuel
					-- leger quand le feu de l'arme chargee touche le
					-- vaisseau") — the puddle's own particle system already
					-- reads as "on fire", but a damage TICK landing had no
					-- feedback of its own until now.
					spawn_impact(trail.victim.ship.position, "fire_trail_tick")
					if apply_damage_and_check_round(trail.victim, trail.owner_side, FIRE_TRAIL.DAMAGE_PER_TICK) then
						return -- round/match state just changed under us — bail out this frame
					end
				end
				-- 2026-09-27 (Camil: "j'ai l'impression que l'arme de
				-- Perturbateur ne touche pas... la trainee de feu [sur les
				-- tourelles]") — confirmed: the puddle only ever checked its
				-- one fixed `victim` (the ship), never any enemy turret
				-- standing in it.
				for _, turret in ipairs(turrets) do
					if turret.owner_side ~= trail.owner_side and turret.hp > 0.0 then
						local tdx = math.abs(turret.position.x - trail.position.x)
						local tdy = math.abs(turret.position.y - trail.position.y)
						if tdx < FIRE_TRAIL.RADIUS + turret.half_extents.x and tdy < FIRE_TRAIL.RADIUS + turret.half_extents.y then
							ticked = true
							turret.hp = turret.hp - FIRE_TRAIL.DAMAGE_PER_TICK
							turret.flash_timer = TURRET.FLASH_DURATION
							spawn_impact(turret.position, "fire_trail_tick")
						end
					end
				end
				if ticked then
					trail.tick_cooldown = FIRE_TRAIL.TICK_INTERVAL
				end
			end
			i = i + 1
		end
	end
end

-- Lourd's Ultra "Pluie de Scuds" telegraph: a closing ring counts down for
-- fall_duration, then the shell impacts — damage + knockback if the
-- opponent is still standing in the reticle, a "big_explosion" flash
-- either way (reuses the existing impact-VFX system rather than a bespoke
-- particle burst).
local function update_missile_strikes(dt)
	local i = 1
	while i <= #missile_strikes do
		local strike = missile_strikes[i]
		strike.elapsed = strike.elapsed + dt
		if strike.elapsed >= strike.fall_duration then
			table.remove(missile_strikes, i)
			local opp = strike.opponent
			spawn_impact(strike.position, "bazooka")
			if opp.ship.position:distance_to(strike.position) < strike.impact_radius then
				local direction = opp.ship.position - strike.position
				if direction:length() < 1.0 then
					direction = Vector2.new(opp.side == 0 and 1.0 or -1.0, 0.0)
				end
				opp.ship = ship_state.knocked_back(opp.ship, direction:normalized() * strike.impact_push, current_arena_bounds, current_frontier_x)
				if apply_damage_and_check_round(opp, strike.owner_side, strike.impact_damage) then
					return
				end
			end
		else
			i = i + 1
		end
	end
end

-- Contrôleur's Ultra "Trou noir": while the target is inside `radius`,
-- pulls them toward this hazard's position every tick and applies a
-- short, continuously-refreshed slow that fades fast once they leave; the
-- fainter outer halo slows only (no pull). Creeps slowly toward the
-- target's live position so camping the halo's far edge isn't permanent.
local function update_black_holes(dt)
	local i = 1
	while i <= #black_holes do
		local hole = black_holes[i]
		hole.duration = hole.duration - dt
		if hole.duration <= 0.0 then
			table.remove(black_holes, i)
		else
			hole.pulse_time = hole.pulse_time + dt
			hole.frame_timer = hole.frame_timer - dt
			if hole.frame_timer <= 0.0 then
				hole.frame_timer = UT.BLACK_HOLE_FRAME_DURATION
				hole.frame_index = (hole.frame_index % #assets.black_hole_frames) + 1
			end
			local target = hole.target
			local to_target = target.ship.position - hole.position
			if to_target:length() > 1.0 then
				hole.position = hole.position + to_target:normalized() * UT.TROU_NOIR_DRIFT_SPEED * dt
			end
			local dist = target.ship.position:distance_to(hole.position)
			if dist < hole.radius then
				apply_external_slow(target, UT.TROU_NOIR_SLOW_REFRESH_DURATION, hole.slow_multiplier)
				local direction = hole.position - target.ship.position
				if direction:length() >= 1.0 then
					target.ship = ship_state.knocked_back(target.ship, direction:normalized() * hole.pull_speed * dt, current_arena_bounds, current_frontier_x)
				end
			elseif dist < hole.outer_radius then
				apply_external_slow(target, UT.TROU_NOIR_SLOW_REFRESH_DURATION, hole.outer_slow_multiplier)
			end
			i = i + 1
		end
	end
end

-- Distance from `point` to the segment [a, b] (laser_mesh_node.gd's own
-- _distance_to_segment()).
local function distance_to_segment(point, a, b)
	local seg = b - a
	local len_sq = seg:length_squared()
	if len_sq < 0.0001 then
		return point:distance_to(a)
	end
	local t = mathx.clampf((point - a):dot(seg) / len_sq, 0.0, 1.0)
	return point:distance_to(a + seg * t)
end

-- Zoneur's Ultra "Grille Laser": each segment ticks damage at
-- UT.GRILLE_LASER_TICK_INTERVAL while the opponent's ship overlaps its line
-- (inflated by its own thickness), same quick fade in/out as the normal
-- beam weapon.
local function update_laser_meshes(dt)
	local i = 1
	while i <= #laser_meshes do
		local laser = laser_meshes[i]
		laser.elapsed = laser.elapsed + dt
		if laser.elapsed >= laser.lifetime then
			table.remove(laser_meshes, i)
		else
			-- Zoneur's passive reward only (2026-08-22): "il faudrait que le
			-- laser se deplace jusqu'au centre... ou vers le fond" — opt-in,
			-- 0 for every other use (the real Grille Laser Ultra's random
			-- static segments).
			if laser.horizontal_velocity and laser.horizontal_velocity ~= 0.0 then
				laser.start_point = Vector2.new(laser.start_point.x + laser.horizontal_velocity * dt, laser.start_point.y)
				laser.end_point = Vector2.new(laser.end_point.x + laser.horizontal_velocity * dt, laser.end_point.y)
			end
			laser.hit_timer = laser.hit_timer - dt
			if laser.hit_timer <= 0.0 then
				local target = laser.target
				local hit_radius = laser.thickness / 2.0 + math.max(target.ship.half_extents.x, target.ship.half_extents.y)
				-- Only the already-drawn part of a sweeping laser hurts.
				local reach = laser.end_point
				if laser.sweep_duration then
					reach = laser.start_point + (laser.end_point - laser.start_point) * mathx.clampf(laser.elapsed / laser.sweep_duration, 0.0, 1.0)
				end
				if distance_to_segment(target.ship.position, laser.start_point, reach) <= hit_radius then
					laser.hit_timer = UT.GRILLE_LASER_TICK_INTERVAL
					if apply_damage_and_check_round(target, opponent_of(target.side).side, laser.damage_per_tick) then
						return
					end
				end
			end
			i = i + 1
		end
	end
end

-- Vif's Ultra "Bourrasque": a continuous every-frame shove toward the
-- target's OWN outer wall for the whole attack (not an on-hit knockback —
-- 2026-08-16 correction), ramping from push_speed_start to push_speed_end
-- as the vortex swarm itself accelerates.
local function update_wind_gusts(dt)
	-- 2026-10-05 (Camil: "un effet bourrasque avec des particules, purement
	-- decoratif"): wind streaks blowing along with the vortices. Stored on
	-- wind_gusts itself (field `streaks`, so the existing resets of that list
	-- clear them too, and no extra top-level local — see UT's 200-local note).
	-- Purely visual: no collision, no damage, no effect on any ship.
	local streaks = wind_gusts.streaks
	if not streaks then
		streaks = {}
		wind_gusts.streaks = streaks
	end
	local si = 1
	while si <= #streaks do
		local streak = streaks[si]
		streak.age = streak.age + dt
		if streak.age >= streak.life then
			table.remove(streaks, si)
		else
			streak.x = streak.x + streak.speed * dt
			si = si + 1
		end
	end
	local i = 1
	while i <= #wind_gusts do
		local gust = wind_gusts[i]
		gust.duration = gust.duration - dt
		-- Wind streaks fly in the vortices' own direction (the shove's), fast,
		-- ramping up with the gust like the vortices do.
		local wind_dir = gust.target.side == 0 and -1.0 or 1.0
		local ramp = 1.0 + 1.5 * (1.0 - mathx.clampf(gust.duration / gust.total_duration, 0.0, 1.0))
		gust.streak_accum = (gust.streak_accum or 0.0) + dt * 110.0
		while gust.streak_accum >= 1.0 and #streaks < 220 do
			gust.streak_accum = gust.streak_accum - 1.0
			local size = 0.5 + math.random() * 0.9
			table.insert(streaks, {
				x = ARENA_BOUNDS.position.x + math.random() * ARENA_BOUNDS.size.x,
				y = ARENA_BOUNDS.position.y + math.random() * ARENA_BOUNDS.size.y,
				speed = wind_dir * (500.0 + math.random() * 700.0) * ramp * size,
				length = 30.0 + math.random() * 90.0 * size,
				thickness = 1.0 + size,
				life = 0.35 + math.random() * 0.35,
				age = 0.0,
				curl = math.random() < 0.3, -- some streaks end in a little swirl dot
			})
		end
		gust.streak_accum = gust.streak_accum % 1.0
		if gust.duration <= 0.0 then
			table.remove(wind_gusts, i)
		else
			local elapsed_fraction = 1.0 - mathx.clampf(gust.duration / gust.total_duration, 0.0, 1.0)
			local push_speed = mathx.lerp(gust.push_speed_start, gust.push_speed_end, elapsed_fraction)
			local direction = gust.target.side == 0 and -1.0 or 1.0 -- away from the frontier, toward the target's own outer wall
			gust.target.ship = ship_state.knocked_back(gust.target.ship, Vector2.new(direction * push_speed * dt, 0.0), current_arena_bounds, current_frontier_x)
			i = i + 1
		end
	end
end

-- Follows its shooter every frame (never a frozen origin — that's only for
-- the Ultra "grille laser" hazard, not the normal weapon), ticking damage
-- at BEAM.TICK_INTERVAL while the opponent sits within range and roughly
-- at the same height.
-- NOTE: written as an if/else rather than an early "goto continue" — Lua's
-- goto/labels are 5.2+, not available under LuaJIT/Lua 5.1 (see vector2.lua's
-- own portability rationale; applies here too since this actually runs
-- inside LÖVE's bundled interpreter, not just the Busted-tested simulation/
-- layer).
local function update_beams(dt)
	local i = 1
	while i <= #beams do
		local beam = beams[i]
		beam.elapsed = beam.elapsed + dt
		if beam.elapsed >= beam.lifetime then
			table.remove(beams, i)
		else
			local target = opponent_of(beam.player.side)
			local origin = beam.player.ship.position
			beam.hit_timer = beam.hit_timer - dt
			if beam.hit_timer <= 0.0 then
				beam.hit_timer = BEAM.TICK_INTERVAL
				local in_range = math.abs(target.ship.position.x - origin.x) <= beam.range
				local y_aligned = math.abs(target.ship.position.y - origin.y) < target.ship.half_extents.y + beam.thickness
				if in_range and y_aligned then
					spawn_impact(target.ship.position, beam.weapon_id)
					if apply_damage_and_check_round(target, beam.player.side, beam.damage_per_second * BEAM.TICK_INTERVAL) then
						return
					end
				end
				-- 2026-10-05 bug report (Camil: "les tirs type laser ne
				-- touchent pas les tourelles") — confirmed: this whole
				-- function only ever checked `target` (the opponent ship),
				-- same class of bug as Perturbateur's boomerang/fire-trail
				-- before their own fix.
				for _, turret in ipairs(turrets) do
					if turret.owner_side ~= beam.player.side and turret.hp > 0.0 then
						local turret_in_range = math.abs(turret.position.x - origin.x) <= beam.range
						local turret_y_aligned = math.abs(turret.position.y - origin.y) < turret.half_extents.y + beam.thickness
						if turret_in_range and turret_y_aligned then
							spawn_impact(turret.position, beam.weapon_id)
							turret.hp = turret.hp - beam.damage_per_second * BEAM.TICK_INTERVAL
							turret.flash_timer = TURRET.FLASH_DURATION
						end
					end
				end
			end
			i = i + 1
		end
	end
end

-- Epic 4 twists — see active_twist's own header comment for scope. A
-- no-op outside campaign mode or when the encounter carries no twist.
local function update_twist(dt)
	if not active_twist then
		return
	end

	if active_twist.twist_type == "shrinking_arena" then
		shrink_step_timer = shrink_step_timer + dt
		if shrink_step_timer >= active_twist.shrink_interval and shrink_step < TWIST_TUNING.MAX_SHRINK_STEPS then
			shrink_step_timer = 0.0
			shrink_step = shrink_step + 1
			local total_shrink_x = math.min(ARENA_BOUNDS.size.x * active_twist.shrink_fraction * shrink_step, ARENA_BOUNDS.size.x * 0.7)
			local total_shrink_y = math.min(ARENA_BOUNDS.size.y * active_twist.shrink_fraction * shrink_step, ARENA_BOUNDS.size.y * 0.7)
			shrink_start_bounds = current_arena_bounds
			shrink_target_bounds = {
				position = Vector2.new(ARENA_BOUNDS.position.x + total_shrink_x / 2.0, ARENA_BOUNDS.position.y + total_shrink_y / 2.0),
				size = Vector2.new(ARENA_BOUNDS.size.x - total_shrink_x, ARENA_BOUNDS.size.y - total_shrink_y),
			}
			shrink_anim_elapsed = 0.0
			shrink_animating = true
		end
		if shrink_animating then
			shrink_anim_elapsed = shrink_anim_elapsed + dt
			local t = mathx.clampf(shrink_anim_elapsed / active_twist.shrink_animation_duration, 0.0, 1.0)
			current_arena_bounds = {
				position = Vector2.new(
					mathx.lerp(shrink_start_bounds.position.x, shrink_target_bounds.position.x, t),
					mathx.lerp(shrink_start_bounds.position.y, shrink_target_bounds.position.y, t)
				),
				size = Vector2.new(
					mathx.lerp(shrink_start_bounds.size.x, shrink_target_bounds.size.x, t),
					mathx.lerp(shrink_start_bounds.size.y, shrink_target_bounds.size.y, t)
				),
			}
			current_frontier_x = current_arena_bounds.position.x + current_arena_bounds.size.x / 2.0
			if t >= 1.0 then
				shrink_animating = false
			end
		end
	elseif active_twist.twist_type == "hazard_zones" then
		hazard_spawn_timer = hazard_spawn_timer - dt
		if hazard_spawn_timer <= 0.0 then
			hazard_spawn_timer = active_twist.hazard_spawn_interval
			table.insert(hazards, {
				position = Vector2.new(
					current_arena_bounds.position.x + 60.0 + math.random() * math.max(current_arena_bounds.size.x - 120.0, 0.0),
					current_arena_bounds.position.y + 60.0 + math.random() * math.max(current_arena_bounds.size.y - 120.0, 0.0)
				),
				radius = active_twist.hazard_radius,
				lifetime = active_twist.hazard_lifetime,
				stuns_ships = active_twist.hazard_stuns_ships,
				deflects_ball = active_twist.hazard_deflects_ball,
				deflect_cooldown = 0.0,
			})
		end
		local i = 1
		while i <= #hazards do
			local hazard = hazards[i]
			hazard.lifetime = hazard.lifetime - dt
			if hazard.lifetime <= 0.0 then
				table.remove(hazards, i)
			else
				if hazard.stuns_ships then
					for _, player in ipairs(players) do
						if player.ship.position:distance_to(hazard.position) < hazard.radius + math.max(player.ship.half_extents.x, player.ship.half_extents.y) then
							player.stun_timer = math.max(player.stun_timer, TWIST_TUNING.HAZARD_STUN_DURATION)
						end
					end
				end
				if hazard.deflects_ball then
					hazard.deflect_cooldown = math.max(hazard.deflect_cooldown - dt, 0.0)
					if hazard.deflect_cooldown <= 0.0 and ball.position:distance_to(hazard.position) < hazard.radius + ball_state.RADIUS then
						ball = ball_state.bounced_off_hazard(ball, hazard.position)
						hazard.deflect_cooldown = TWIST_TUNING.HAZARD_DEFLECT_COOLDOWN
					end
				end
				i = i + 1
			end
		end
	elseif active_twist.twist_type == "energy_orb_pickup" then
		orb_spawn_timer = orb_spawn_timer - dt
		if orb_spawn_timer <= 0.0 then
			orb_spawn_timer = active_twist.orb_spawn_interval
			-- Spawn on a random side's actual playable half instead of
			-- exactly on the frontier — that strip is inside the neutral
			-- zone neither ship can ever enter (2026-08-09 bug fix carried
			-- over: an orb spawned there would be permanently unreachable).
			local side = math.random(0, 1)
			local x
			if side == 0 then
				x = current_arena_bounds.position.x + 40.0 + math.random() * math.max(current_frontier_x - current_arena_bounds.position.x - 80.0, 0.0)
			else
				x = current_frontier_x + 40.0 + math.random() * math.max(current_arena_bounds.position.x + current_arena_bounds.size.x - current_frontier_x - 80.0, 0.0)
			end
			local y = current_arena_bounds.position.y + 40.0 + math.random() * math.max(current_arena_bounds.size.y - 80.0, 0.0)
			table.insert(orbs, { position = Vector2.new(x, y), lifetime = TWIST_TUNING.ORB_LIFETIME })
		end
		local i = 1
		while i <= #orbs do
			local orb = orbs[i]
			orb.lifetime = orb.lifetime - dt
			if orb.lifetime <= 0.0 then
				table.remove(orbs, i)
			else
				local picked = false
				for _, player in ipairs(players) do
					if player.ship.position:distance_to(orb.position) < TWIST_TUNING.ORB_PICKUP_RADIUS + math.max(player.ship.half_extents.x, player.ship.half_extents.y) then
						local weapon = weapon_system_state.selected_weapon(player.weapon)
						player.weapon = weapon_system_state.with_gauge_added(player.weapon, weapon.gauge_max * active_twist.orb_gauge_bonus_percent / 100.0)
						table.remove(orbs, i)
						picked = true
						break
					end
				end
				if not picked then
					i = i + 1
				end
			end
		end
		boss_helpers.update_phases()
	elseif active_twist.twist_type == "drifting_neutral_zone" then
		current_frontier_x = current_frontier_x + active_twist.drift_speed * drift_direction * dt
		local offset = current_frontier_x - FRONTIER_X
		if math.abs(offset) >= active_twist.drift_range then
			current_frontier_x = FRONTIER_X + active_twist.drift_range * mathx.signf(offset)
			drift_direction = -drift_direction
		end
	elseif active_twist.twist_type == "visual_decoy" and decoy then
		decoy.wander_timer = decoy.wander_timer - dt
		if decoy.wander_timer <= 0.0 then
			pick_decoy_wander_target()
		end
		local to_target = decoy.wander_target - decoy.position
		if to_target:length() > 4.0 then
			decoy.position = decoy.position + to_target:normalized() * active_twist.decoy_wander_speed * dt
		end
	end
end

local function open_pause_menu()
	pause_state = { index = 0, up_prev = false, down_prev = false, confirm_prev = true }
end

local function resume_from_pause_menu()
	pause_state = nil
end

-- "Retourner au menu" — the exact action Escape used to perform outright,
-- now reached through the pause menu instead. Always TitleScreen, even
-- from a campaign fight (2026-08-22 precedent on the win path: "il faudrait
-- revenir a l'accueil" once there's nowhere more specific to send them —
-- Godot sends every pause-menu quit here uniformly, campaign or not).
local function quit_to_title_from_pause_menu()
	pause_state = nil
	campaign_context.return_to_map() -- harmless no-op in Versus; clears the transient debug/pending-encounter state in campaign mode
	local screen_manager = require("screen_manager")
	local title_screen = require("screens.title_screen")
	screen_manager.switch_to(title_screen)
end

local function update_pause_menu(dt)
	-- A shared full-screen overlay (either player can pause) — solo input
	-- (keyboard + the first connected gamepad), same convention as every
	-- other menu screen in this port.
	local move_down = input.solo_down()
	local move_up = input.solo_up()
	if move_down and not pause_state.down_prev then
		pause_state.index = (pause_state.index + 1) % #PAUSE_MENU_CHOICES
	elseif move_up and not pause_state.up_prev then
		pause_state.index = (pause_state.index - 1) % #PAUSE_MENU_CHOICES
	end
	pause_state.up_prev, pause_state.down_prev = move_up, move_down

	local confirm = input.solo_confirm()
	if confirm and not pause_state.confirm_prev then
		if pause_state.index == 0 then
			resume_from_pause_menu()
		else
			quit_to_title_from_pause_menu()
		end
	end
	if pause_state then -- quit_to_title_from_pause_menu() may have just cleared it
		pause_state.confirm_prev = confirm
	end
end

local function draw_pause_menu()
	love.graphics.setColor(0.0, 0.0, 0.0, 0.6)
	love.graphics.rectangle("fill", 0, 0, 1280, 720)
	love.graphics.setColor(1, 1, 1)
	love.graphics.printf("PAUSE", 0, 300, 1280, "center")
	for i, choice in ipairs(PAUSE_MENU_CHOICES) do
		local idx = i - 1
		local marker = (idx == pause_state.index) and "> " or "  "
		love.graphics.setColor(idx == pause_state.index and 1.0 or 0.75, idx == pause_state.index and 0.95 or 0.75, idx == pause_state.index and 0.6 or 0.8)
		love.graphics.printf(marker .. choice, 0, 340 + idx * 34, 1280, "center")
	end
end

-- Real sized Font (fonts.lua — see its own doc comment on why this beats
-- scaling the default font up), restoring the port's usual default font
-- afterward so no other screen inherits a leftover custom Font.
local function print_scaled(text, x, y, size, align, box_w)
	love.graphics.setFont(fonts.get(size))
	if align then
		love.graphics.printf(text, x, y, box_w, align)
	else
		love.graphics.print(text, x, y)
	end
	love.graphics.setFont(fonts.default)
end

-- match_arena_node.gd's own _process_ready_gate(): note the WAITING_FOR_
-- INPUT check is a plain "if pressed" with NO edge-guard — if Tir happens
-- to already be held (e.g. carried over from confirming character select),
-- round 1's gate skips waiting entirely. That's Godot's real behavior, not
-- a bug to fix here.
local function update_round_start_gate(dt)
	if round_start_gate.phase == "waiting_for_input" then
		local pressed = love.keyboard.isScancodeDown("space") or love.keyboard.isScancodeDown("return")
		if pressed then
			round_start_gate.phase = "ready_flash"
			round_start_gate.phase_timer = ROUND_START_GATE.READY_FLASH_DURATION
		end
	elseif round_start_gate.phase == "ready_flash" then
		round_start_gate.phase_timer = round_start_gate.phase_timer - dt
		if round_start_gate.phase_timer <= 0.0 then
			round_start_gate.phase = "go_flash"
			round_start_gate.phase_timer = ROUND_START_GATE.GO_FLASH_DURATION
		end
	else -- go_flash
		round_start_gate.phase_timer = round_start_gate.phase_timer - dt
		if round_start_gate.phase_timer <= 0.0 then
			local pending_serve_side = round_start_gate.pending_serve_side
			round_start_gate = nil
			serve_ball(pending_serve_side)
		end
	end
end

local function draw_round_start_gate()
	local text
	if round_start_gate.phase == "waiting_for_input" then
		text = string.format("Round %d\nPret ? (appuyez sur Tir pour commencer)", round_start_gate.round_number)
		love.graphics.setColor(0.95, 0.96, 1.0)
		print_scaled(text, 0, 320, 22, "center", 1280)
	elseif round_start_gate.phase == "ready_flash" then
		love.graphics.setColor(0.95, 0.96, 1.0)
		print_scaled("Ready......", 0, 320, 22, "center", 1280)
	else -- go_flash — bigger, gold, same "big moment" bump as MatchLabel's Victoire!/Match termine
		love.graphics.setColor(1.0, 0.84, 0.29)
		print_scaled("GO !", 0, 320, 48, "center", 1280)
	end
end

-- match_arena.update(dt) split into several top-level functions (2026-09-15
-- bug fix: "function at line 3587 has more than 60 upvalues" — a single
-- Lua function may close over at most 60 distinct outer-scope variables;
-- this file's match_arena.update() had grown to reference ~65 of them
-- directly across a season of additions, one module-level state table/
-- function at a time, each individually reasonable). Splitting the body
-- into cohesive top-level functions doesn't reduce how much STATE this
-- screen has — it reduces how many of those variables any ONE function
-- needs to close over at once, since match_arena.update() itself now only
-- references the few functions below (plus `match`/`serving` for its own
-- short-circuit), not everything they in turn touch.

-- Ultra intro, pause menu, ship explosion, round-start gate, and the
-- Versus-only post-match choice — the full freeze-gate chain, checked in
-- priority order every frame. Returns true when one of them handled this
-- frame (the caller must do nothing else), false once genuinely clear to
-- run the rest of update().
local function update_freeze_gates(dt)
	-- F1 AI-toggle is checked unconditionally every frame, even while
	-- frozen/paused (match_arena_node.gd calls _process_ai_toggle() before
	-- any of its own pause/ready-gate dispatch).
	update_ai_toggle()

	-- Ship explosion debris/disintegration bursts tick every frame no
	-- matter what's frozen — once spawned (at the very end of
	-- ship_explosion_helpers.update_explosion(), below) they need to keep
	-- animating through the round_start_gate/match-over freeze that
	-- follows them.
	ship_explosion_helpers.update_bursts(dt)

	-- ultra_intro_node.gd: the whole game freezes for the intro's ~1.67s
	-- (Godot's get_tree().paused = true; this port just skips every other
	-- update this frame instead) — only the intro's own phase timer keeps
	-- advancing, matching the intro node's own PROCESS_MODE_ALWAYS.
	if ultra_intro then
		update_ultra_intro(dt)
		return true
	end

	-- pause_controller.gd: available any time mid-match (not once match_over
	-- — Versus's own R/Escape rematch-or-menu prompt and campaign's win/loss
	-- continue prompt take over from there instead). Gamepad: Start, not B
	-- (2026-09-27, Camil's own button layout above — B is Ultra in a live
	-- match) — either player's Start can open it, checked directly rather
	-- than through input.solo_escape() (which still uses B, correctly, for
	-- every OTHER screen's back/cancel).
	local escape_pressed = love.keyboard.isScancodeDown("escape")
		or input.button_down(input.get_joystick(1), "start")
		or input.button_down(input.get_joystick(2), "start")
	if pause_state then
		update_pause_menu(dt)
		escape_prev = escape_pressed
		return true
	end
	if escape_pressed and not escape_prev and not match.match_over then
		open_pause_menu()
		escape_prev = escape_pressed
		return true
	end
	escape_prev = escape_pressed

	-- Ship explosion: same freeze pattern, checked after pause (still
	-- escapable) but before the ready gate — round_start_gate is always nil
	-- here anyway (start_new_round(), which sets it, is only called once
	-- the explosion itself finishes).
	if ship_explosion_helpers.round then
		ship_explosion_helpers.update_explosion(dt)
		return true
	end

	-- "Pret ?" round-start gate: same freeze pattern, checked after pause
	-- so Escape can still open the pause menu while waiting on it.
	if round_start_gate then
		update_round_start_gate(dt)
		return true
	end

	-- Versus-only post-match choice (2026-08-16 UX audit, Sally: "Versus
	-- mode ends in a dead screen") — campaign has its own win/loss
	-- continue-key handling instead (resolve_campaign_result()). Waits for
	-- the death explosion to finish, then a short beat, before offering
	-- the actual menu — same freeze pattern as everything else above.
	if match.match_over and not campaign_mode and not ship_explosion_helpers.round then
		if post_match_choice then
			local move = 0.0
			if input.solo_down() then
				move = move + 1.0
			end
			if input.solo_up() then
				move = move - 1.0
			end
			if math.abs(move) > 0.5 and math.abs(post_match_choice.move_prev) <= 0.5 then
				local step = move > 0.0 and 1 or -1
				post_match_choice.index = (post_match_choice.index + step) % #POST_MATCH_CHOICES
			end
			post_match_choice.move_prev = move

			local confirm = input.solo_confirm()
			if confirm and not post_match_choice.confirm_prev then
				if post_match_choice.index == 0 then -- Revanche
					match_arena.enter() -- resets post_match_choice to nil — return immediately, nothing below may touch it again
					return true
				else -- Choix des personnages
					local screen_manager = require("screen_manager")
					local character_select = require("screens.character_select")
					screen_manager.switch_to(character_select)
					return true
				end
			end
			post_match_choice.confirm_prev = confirm
			return true
		end
		post_match_choice_timer = (post_match_choice_timer or POST_MATCH_CHOICE_DELAY) - dt
		if post_match_choice_timer <= 0.0 then
			-- confirm_prev seeded true — the SAME keypress that just
			-- confirmed the last "Ready ?" gate/a rematch must not
			-- instantly confirm this menu's own default entry.
			post_match_choice = { index = 0, move_prev = 0.0, confirm_prev = true }
		end
		return true
	end

	return false
end

-- Ball trail emission/position + ball_node.gd's "zoom" (continuous spin,
-- post-miss oversized pop shrinking back to normal) for the primary ball
-- and every multi_ball extra.
local function update_ball_visuals(dt)
	-- Ball trail: no emission while frozen/serving (mirrors ball_node.gd's
	-- own `if not active: _trail.emitting = false`), but the ParticleSystem
	-- still ticks every frame regardless so already-emitted sparks keep
	-- fading out instead of freezing mid-flight.
	if serving or match.match_over then
		ball_trail_ps:setEmissionRate(0.0)
	else
		ball_trail_ps:setEmissionRate(BALL_TRAIL_EMISSION_RATE)
		ball_trail_ps:setPosition(ball.position.x, ball.position.y)
		if ball.velocity:length_squared() > 1.0 then
			ball_trail_ps:setDirection((-ball.velocity):angle())
		end
	end
	ball_trail_ps:update(dt)

	-- ball_node.gd's "zoom": the ball spins continuously (frozen or not),
	-- and pops in oversized after a miss, shrinking back to normal size
	-- over the serve freeze (see serve_ball()/RESPAWN_POP_START_SCALE).
	ball_rotation = ball_rotation + ROTATION_SPEED * dt
	if serving and serve_freeze_elapsed then
		serve_freeze_elapsed = serve_freeze_elapsed + dt
		local t = mathx.clampf(serve_freeze_elapsed / SERVE_DELAY, 0.0, 1.0)
		ball_scale = mathx.lerp(RESPAWN_POP_START_SCALE, 1.0, t)
	end

	-- multi_ball twist: each extra ball gets the same trail treatment as
	-- the primary, gated on ITS OWN frozen_timer (not the primary's
	-- `serving`) — matches these balls' independent physics.
	for _, extra in ipairs(extra_balls) do
		if extra.frozen_timer or match.match_over then
			extra.trail_ps:setEmissionRate(0.0)
		else
			extra.trail_ps:setEmissionRate(BALL_TRAIL_EMISSION_RATE)
			extra.trail_ps:setPosition(extra.ball_data.position.x, extra.ball_data.position.y)
			if extra.ball_data.velocity:length_squared() > 1.0 then
				extra.trail_ps:setDirection((-extra.ball_data.velocity):angle())
			end
		end
		extra.trail_ps:update(dt)
		extra.rotation = (extra.rotation or 0.0) + ROTATION_SPEED * dt
		if extra.frozen_timer then
			-- frozen_timer counts DOWN from SERVE_DELAY (see the multi_ball
			-- miss-handling loop) — invert it into the same 0..1 "how much
			-- of the freeze has elapsed" progress serve_freeze_elapsed uses.
			local t = mathx.clampf(1.0 - extra.frozen_timer / SERVE_DELAY, 0.0, 1.0)
			extra.scale = mathx.lerp(RESPAWN_POP_START_SCALE, 1.0, t)
		else
			extra.scale = 1.0
		end
	end
end

-- Boss phase-message decay, cheat keys, the timer wheel, and every
-- per-entity update() call (ships/weapons through to the campaign reward
-- system) — everything that runs once past the freeze gates and all the
-- way up to (but not including) the ball-physics/twist section, which has
-- its own function below since it alone needs a whole separate cluster of
-- upvalues (ships, turrets, twists, the boomerang/heavy_push rules...).
local function update_all_entities(dt)
	-- Epic boss phase-escalation message (match_arena_node.gd's own one-shot
	-- Timer callback) — self-clearing, ticked here so it fades out even
	-- through a serve delay.
	boss_helpers.message_timer = math.max(boss_helpers.message_timer - dt, 0.0)

	-- Only reachable once we're past every freeze gate above (ultra intro,
	-- pause, ready gate) and short of match_over — the same window
	-- match_arena_node.gd's own _round_playing represents.
	if not match.match_over then
		update_cheat_keys()
	end

	timer.update(dt)

	-- match_arena_node.gd's _resolve_round_end(): ships (and, by the same
	-- logic, their input) freeze the instant match_over flips — Versus
	-- itself already never reaches here once over (see update_freeze_
	-- gates()'s own post-match choice block), so this only actually
	-- matters for campaign mode's own brief "Victoire"/"Defaite" hold
	-- before the continue key.
	if not match.match_over then
		update_player_input(players[1], dt)
		update_player_input(players[2], dt)
	end
	-- 2026-09-18 (Camil: "quand il reste tres peu de PV a l'adversaire, et
	-- que je lance mon ultra, il meurt avant meme que l'ultra ne se
	-- declenche") — start_ultra_intro() (called from update_player_input
	-- above) only sets the `ultra_intro` freeze; update_freeze_gates() only
	-- checks it at the TOP of the *next* frame's update(), so without this
	-- an already-in-flight bullet/beam could still land its normal killing
	-- blow via update_bullets()/update_beams() below, THIS same frame,
	-- ending the round for real before the Ultra's own intro ever got a
	-- chance to play. Bail out immediately once an Ultra was just cast.
	if ultra_intro then
		return
	end
	update_bullets(dt)
	update_beams(dt)
	update_turrets(dt)
	update_ghost_paddles(dt)
	update_impacts(dt)
	update_fire_trails(dt)
	update_missile_strikes(dt)
	update_black_holes(dt)
	update_laser_meshes(dt)
	update_wind_gusts(dt)
	update_passive_rewards(dt)
	update_floating_texts(dt)
	update_gauge_fill_effects(dt)
	update_heal_fx(dt)
	feedback_fx.update_shake(dt)
end

-- The twist tick plus every ball's own physics (wall/turret/paddle bounce,
-- out-of-bounds miss handling, heavy_push) — primary and every multi_ball
-- extra alike. Never reached once match_over or mid-serve-freeze (see
-- match_arena.update() itself).
local function update_ball_and_twist(dt)
	update_twist(dt)

	-- Ball paddle bounce. Aim reuses the movement direction currently held
	-- (Pong-style: "où tu bouges, c'est là que tu vises" — ship_node.gd's
	-- get_aim_input()); lift charge comes from however long the lift key's
	-- been held (see lift_charge_fraction()). A successful return fills the
	-- RETURNING player's own gauge, scaling with lift charge (Story 1.7).
	local p1, p2 = players[1], players[2]

	-- Lourd's "heavy_push": a fully-charged return from a heavy_push
	-- character arms `push_pending`; the NEXT ship the ball touches (not
	-- necessarily the one it was aimed at) gets shoved, whether or not that
	-- contact goes on to be a successful return. Shared across every ball
	-- (primary or extra, multi_ball twist) — the first one to touch a ship
	-- while this is armed consumes it; ball_node.gd's own model has no
	-- second ball to disambiguate against, so this is the reasonable
	-- extension rather than a re-litigated design.
	local function resolve_pending_push(target_player, ball_velocity)
		if push_pending then
			target_player.ship = ship_state.knocked_back(
				target_player.ship,
				Vector2.new(mathx.signf(ball_velocity.x) * SHIP_FEEL.HEAVY_PUSH_DISTANCE, 0.0),
				current_arena_bounds,
				current_frontier_x
			)
			push_pending = false
		end
	end

	-- Wall/turret/paddle bounce + out-of-bounds detection for ONE ball —
	-- shared by the primary `ball` and every multi_ball extra (ball_node.gd
	-- itself is a fully self-contained per-ball script; this is that same
	-- logic pulled into one reusable function instead of duplicated).
	-- Nested here (not a top-level local — the 200-local ceiling) since
	-- only this one caller needs it. Returns the updated ball plus the
	-- missed side (0/1) if it just went out of bounds this frame, or nil.
		-- 2026-10-06 dash feature: Traqueur's "aimant a balle" — nudges the
		-- ball toward whichever player just dashed, for the dash's whole
		-- duration. A gentle steering force (not a snap), so it still has
		-- to be aimed/returned normally once it arrives. Camil: "l'aimant ne
		-- doit fonctionner que quand c'est au joueur de rattraper la balle
		-- [...] une fois la balle renvoyee, l'aimant ne marche plus, jusqu'a
		-- ce que ce soit de nouveau a lui de la renvoyer" — gated on the
		-- ball actually being on his own side (same check the AI's own
		-- ball_on_my_side uses), not just the timer: the instant he returns
		-- it, the pull stops, even mid-timer, and only resumes if the ball
		-- somehow comes back to his side before the timer runs out.
		local function apply_ball_magnet(current_ball, player)
			if player.dash_pull_timer <= 0.0 then
				return current_ball
			end
			local ball_on_his_side = player.side == 0 and current_ball.position.x < current_frontier_x
				or (player.side == 1 and current_ball.position.x > current_frontier_x)
			-- Camil, still unhappy after the first side-only gate: "ca ne
			-- doit aimanter QUE si la balle est 'a rattraper'. Si elle a ete
			-- renvoyee, l'aimant ne doit pas marcher" — right after he
			-- returns it, the ball is still briefly on his own side
			-- (hasn't crossed the frontier yet) but is now moving AWAY from
			-- him, so position alone isn't enough: also require it to
			-- actually be heading toward his own wall (same
			-- "moving_toward_my_wall" idea ai_helpers.ball_time_to_arrival
			-- uses for the AI's own interception logic).
			local moving_toward_him = player.side == 0 and current_ball.velocity.x < 0.0
				or (player.side == 1 and current_ball.velocity.x > 0.0)
			if not ball_on_his_side or not moving_toward_him then
				return current_ball
			end
			local to_player = player.ship.position - current_ball.position
			if to_player:length() < 1.0 then
				return current_ball
			end
			-- Camil: "l'aimant fait toujours accelerer la balle, il ne faut
			-- absolument pas ! on ne lui fait juste que s'orienter vers le
			-- vaisseau !" — adding a pull vector onto velocity (the previous
			-- approach) always changes its MAGNITUDE too, not just its
			-- heading, which is exactly the "acceleration" he keeps seeing
			-- even with the extra accel term removed. Steer the velocity's
			-- DIRECTION toward the player instead, by a fraction each frame,
			-- then rescale back to the ball's own ORIGINAL speed — heading
			-- changes, speed never does.
			local speed = current_ball.velocity:length()
			if speed < 0.01 then
				return current_ball
			end
			local turn_fraction = mathx.clampf(dash_helpers.TRAQUEUR_PULL_TURN_RATE * dt, 0.0, 1.0)
			local new_direction = (current_ball.velocity:normalized() * (1.0 - turn_fraction) + to_player:normalized() * turn_fraction):normalized()
			return ball_state.new(current_ball.position, new_direction * speed, current_ball.spin, current_ball.rally_count)
		end

	local function resolve_ball_physics(current_ball)
		current_ball = apply_ball_magnet(current_ball, p1)
		current_ball = apply_ball_magnet(current_ball, p2)
		-- Perturbateur's dash: "ralentir la balle pendant 1/2 secondes" — a
		-- slow-motion window on the ball itself (every ball, including
		-- multi_ball extras), not a speed change stored on the ball — it
		-- simply advances less per real frame while ball_slow_timer runs.
		local ball_dt = feedback_fx.ball_slow_timer > 0.0 and dt * dash_helpers.PERTURBATEUR_BALL_SLOW_FACTOR or dt
		current_ball = ball_state.update(current_ball, ball_dt)

		local min_y = current_arena_bounds.position.y + ball_state.RADIUS
		local max_y = current_arena_bounds.position.y + current_arena_bounds.size.y - ball_state.RADIUS
		if current_ball.position.y <= min_y then
			current_ball = ball_state.bounced_off_wall(current_ball, min_y)
		elseif current_ball.position.y >= max_y then
			current_ball = ball_state.bounced_off_wall(current_ball, max_y)
		end

		-- Turrets deflect the ball too (2026-08-09 playtest, Controleur:
		-- "les tourelles pourraient renvoyer la balle aussi !") — a
		-- stationary mirror-bounce, no aim/lift, gated by its own short
		-- cooldown so it can't re-bounce the same visit.
		for _, turret in ipairs(turrets) do
			if turret.bounce_cooldown <= 0.0 and point_in_ship(turret, current_ball.position) then
				local outgoing_side = turret.owner_side == 0 and 1 or -1
				current_ball = ball_state.returned(current_ball, Vector2.ZERO, 0.0, outgoing_side)
				turret.bounce_cooldown = 0.2
			end
		end

		-- 2026-10-06 dash feature: Contrôleur's phantom paddle / Perturbateur's
		-- mirror decoy (ghost_paddles) — a real paddle-style bounce (angle
		-- depends on contact position, same as a live paddle), but spends
		-- itself: one return, then it's gone (lifetime forced to 0, swept by
		-- update_ghost_paddles() this same frame's later pass).
		for _, ghost in ipairs(ghost_paddles) do
			if ghost.lifetime > 0.0 and point_in_ship(ghost, current_ball.position) then
				local outgoing_side = ghost.owner_side == 0 and 1 or -1
				local contact_offset = (current_ball.position.y - ghost.position.y) / ghost.half_extents.y
				current_ball = ball_state.returned(current_ball, Vector2.ZERO, 0.0, outgoing_side, nil, contact_offset)
				spawn_impact(current_ball.position, "paddle_bounce")
				ghost.lifetime = 0.0
			end
		end

		if ball_overlaps_ship(p1.ship, current_ball.position) then
			resolve_pending_push(p1, current_ball.velocity)
			if current_ball.velocity.x < 0.0 then
				local lift = lift_charge_fraction(p1.lift_charge_timer)
				local contact_offset = (current_ball.position.y - p1.ship.position.y) / p1.ship.half_extents.y
				current_ball = ball_state.returned(current_ball, p1.last_input_direction, lift, 1, nil, contact_offset)
				p1.paddle_flash_timer = feedback_fx.PADDLE_FLASH_DURATION
				-- 2026-10-05 bug report: "flash retour de balle ne marche
				-- pas" — a pure brightness multiply on the ship sprite (see
				-- ship_tint()) reads as near-invisible against some
				-- characters' own art, so this adds the SAME spark_ring
				-- flash every bullet hit already uses (battle-tested
				-- visible), right at the ball's own contact point.
				spawn_impact(current_ball.position, "paddle_bounce")
				-- gauge_floor twist: self-fill-on-return is locked (the
				-- passive trickle in update_player_input() is what
				-- prevents a total stall instead) — Story 1.6's miss-fill
				-- is never gated by this.
				if not (active_twist and active_twist.twist_type == "gauge_floor") then
					local fill_amount = mathx.lerp(weapon_system_state.RETURN_GAUGE_FILL, weapon_system_state.RETURN_GAUGE_FILL_MAX_LIFT, lift)
					p1.weapon = weapon_system_state.with_gauge_added(p1.weapon, fill_amount)
					-- match_arena_node.gd's _on_gauge_filled(): a plain "+X"
					-- popup on EVERY gauge fill (ship_1/2.gauge_filled is
					-- connected unconditionally, normal returns included, not
					-- just the elaborate miss-fill travel effect above).
					spawn_floating_text(p1.ship.position + Vector2.new(0.0, -p1.ship.half_extents.y), string.format("+%d", math.floor(fill_amount)), { 1.0, 0.9, 0.4, 1.0 })
				end
				if p1.character.special_rule == "heavy_push" and lift >= 1.0 then
					push_pending = true
				end
			end
		end
		if ball_overlaps_ship(p2.ship, current_ball.position) then
			resolve_pending_push(p2, current_ball.velocity)
			if current_ball.velocity.x > 0.0 then
				local lift = lift_charge_fraction(p2.lift_charge_timer)
				local contact_offset = (current_ball.position.y - p2.ship.position.y) / p2.ship.half_extents.y
				current_ball = ball_state.returned(current_ball, p2.last_input_direction, lift, -1, nil, contact_offset)
				p2.paddle_flash_timer = feedback_fx.PADDLE_FLASH_DURATION
				spawn_impact(current_ball.position, "paddle_bounce")
				if not (active_twist and active_twist.twist_type == "gauge_floor") then
					local fill_amount = mathx.lerp(weapon_system_state.RETURN_GAUGE_FILL, weapon_system_state.RETURN_GAUGE_FILL_MAX_LIFT, lift)
					p2.weapon = weapon_system_state.with_gauge_added(p2.weapon, fill_amount)
					spawn_floating_text(p2.ship.position + Vector2.new(0.0, -p2.ship.half_extents.y), string.format("+%d", math.floor(fill_amount)), { 1.0, 0.9, 0.4, 1.0 })
				end
				if p2.character.special_rule == "heavy_push" and lift >= 1.0 then
					push_pending = true
				end
			end
		end

		-- Missing the ball never ends the round by itself (GDD: "the ball
		-- never deals damage") — it fills the WINNING side's gauge (Story
		-- 1.6), adds an Ultra pip (ball_node.gd's "systeme des 5 balles" —
		-- same trigger as the gauge miss-fill). Re-serving is the caller's
		-- job (the primary and an extra ball respawn differently — see
		-- serve_ball() vs the multi_ball loop below).
		local missed_side = nil
		if current_ball.position.x < current_arena_bounds.position.x then
			missed_side = 0
			local pips_before = p2.weapon.ultra_pips
			p2.weapon = weapon_system_state.with_gauge_added(p2.weapon, weapon_system_state.MISS_GAUGE_FILL)
			p2.weapon = weapon_system_state.with_ultra_pip_added(p2.weapon)
			spawn_gauge_fill_effect(current_ball.position, p2, weapon_system_state.MISS_GAUGE_FILL, pips_before < weapon_system_state.ULTRA_METER_MAX)
		elseif current_ball.position.x > current_arena_bounds.position.x + current_arena_bounds.size.x then
			missed_side = 1
			local pips_before = p1.weapon.ultra_pips
			p1.weapon = weapon_system_state.with_gauge_added(p1.weapon, weapon_system_state.MISS_GAUGE_FILL)
			p1.weapon = weapon_system_state.with_ultra_pip_added(p1.weapon)
			spawn_gauge_fill_effect(current_ball.position, p1, weapon_system_state.MISS_GAUGE_FILL, pips_before < weapon_system_state.ULTRA_METER_MAX)
		end
		if missed_side ~= nil then
			feedback_fx.trigger_shake(feedback_fx.SHAKE_MISS_MAGNITUDE, feedback_fx.SHAKE_MISS_DURATION)
		end
		return current_ball, missed_side
	end

	for _, turret in ipairs(turrets) do
		turret.bounce_cooldown = math.max(turret.bounce_cooldown - dt, 0.0)
	end
	feedback_fx.ball_slow_timer = math.max(feedback_fx.ball_slow_timer - dt, 0.0) -- Perturbateur's dash — ticked once per frame here, not inside resolve_ball_physics (which runs once per ball, including multi_ball extras)

	local missed_side
	ball, missed_side = resolve_ball_physics(ball)
	if missed_side ~= nil then
		serve_ball(missed_side)
	end

	-- multi_ball twist: each extra ball is fully independent — its own
	-- miss just re-centers/re-freezes THAT ball (mirrors ball_node.gd's own
	-- reset_to_center(missed_side, freeze_on_respawn=true)), never touching
	-- the shared `serving` flag (that's the PRIMARY ball's own brief
	-- freeze). One simplification, documented rather than chased: while
	-- the primary itself is mid-`serving` (its own ~1s post-miss freeze),
	-- extras pause too, since this whole block already sits behind
	-- match_arena.update()'s own `if match.match_over or serving then
	-- return end` — true frame-for-frame independence during that specific
	-- window isn't worth splitting the freeze architecture over.
	for _, extra in ipairs(extra_balls) do
		if extra.frozen_timer then
			extra.frozen_timer = extra.frozen_timer - dt
			if extra.frozen_timer <= 0.0 then
				extra.ball_data = ball_state.new(extra.ball_data.position, extra.pending_velocity)
				extra.frozen_timer = nil
				extra.pending_velocity = nil
			end
		else
			local extra_missed_side
			extra.ball_data, extra_missed_side = resolve_ball_physics(extra.ball_data)
			if extra_missed_side ~= nil then
				extra.ball_data = ball_state.new(
					Vector2.new(current_frontier_x, current_arena_bounds.position.y + current_arena_bounds.size.y / 2.0),
					Vector2.ZERO
				)
				extra.pending_velocity = spawn_velocity(extra_missed_side)
				extra.frozen_timer = SERVE_DELAY
			end
		end
	end
end

function match_arena.update(dt)
	if update_freeze_gates(dt) then
		return
	end
	update_ball_visuals(dt)
	update_all_entities(dt)
	if match.match_over or serving then
		return
	end
	update_ball_and_twist(dt)
end

-- ship_node.gd's _physics_process() modulate chain (stun -> scramble ->
-- vulnerability -> charge-ready blink -> charging gradient -> lift-charge
-- gradient -> default white, plus this port's own explosion-flicker on
-- top) — reused as a color TINT over the real sprite (setColor multiplies
-- a textured draw the same way it multiplies a flat fill, so this still
-- works now that ships draw real art instead of placeholder rectangles).
-- Dash tint isn't ported — no character currently uses special_rule ==
-- "dash_lift" in Godot either (Vif's own rewrite replaced it with
-- Tourbillon), so there is nothing to tint.
local function ship_tint(player)
	-- Epic "il faudrait une explosion lente du vaisseau avant apparition du
	-- 'appuyer pour continuer'" (2026-09-12) — the loser flickers red/white
	-- for the whole ship_explosion_helpers.DURATION buildup before the actual
	-- debris/disintegration burst lands (see ship_explosion_helpers.update_explosion()).
	-- Highest priority: nothing else matters once a ship is about to blow.
	if ship_explosion_helpers.round and ship_explosion_helpers.round.loser == player then
		if ship_explosion_helpers.round.flicker_on then
			return 1.0, 0.25, 0.15
		end
		return 1.0, 1.0, 1.0
	end
	-- 2026-10-05 feedback FX: a brief overbright flash the instant a return
	-- lands — see the paddle-bounce call sites in update_ball_and_twist().
	-- High priority (right after the explosion check) so it's never masked
	-- by whatever other state the ship happens to be in at that moment.
	if player.paddle_flash_timer > 0.0 then
		local t = player.paddle_flash_timer / feedback_fx.PADDLE_FLASH_DURATION
		local brightness = mathx.lerp(1.0, 2.2, t)
		return brightness, brightness, brightness
	end
	if player.stun_timer > 0.0 then
		return 0.75, 0.75, 1.0 -- pale blue-white
	end
	if player.controls_scrambled_timer > 0.0 then
		-- 2026-08-15 bug report (Camil): "Perturbateur ne fait rien du tout ?"
		-- — the scramble was always inverting input correctly, it just had
		-- zero visual feedback. A fast violet flicker makes it readable.
		local blink_on = math.fmod(player.controls_scrambled_timer, SHIP_FEEL.CONTROL_SCRAMBLE_BLINK_PERIOD) < SHIP_FEEL.CONTROL_SCRAMBLE_BLINK_PERIOD / 2.0
		if blink_on then
			return 0.6, 0.5, 0.9
		end
		return 1.0, 0.6, 1.0
	end
	if player.vulnerability_timer > 0.0 then
		return 1.0, 0.45, 0.45
	end
	local weapon = weapon_system_state.selected_weapon(player.weapon)
	local charge_capable = weapon.charge_fire_duration > 0.0
	local is_charging = charge_capable and player.fire_held_duration > SHIP_FEEL.NORMAL_FIRE_GRACE
	if is_charging and player.fire_held_duration >= weapon.charge_fire_duration then
		-- Fully charged and ready to release — a fast blink, unmistakable.
		local blink_on = math.fmod(player.fire_held_duration, SHIP_FEEL.CHARGE_READY_BLINK_PERIOD) < SHIP_FEEL.CHARGE_READY_BLINK_PERIOD / 2.0
		if blink_on then
			return 1.7, 1.7, 1.7
		end
		return 1.0, 0.35, 0.1
	elseif is_charging then
		local t = mathx.clampf(player.fire_held_duration / math.max(weapon.charge_fire_duration, 0.001), 0.0, 1.0)
		return 1.0, mathx.lerp(1.0, 0.35, t), mathx.lerp(1.0, 0.1, t) -- builds toward orange-red
	elseif player.lift_charge_timer > 0.0 then
		local t = mathx.clampf(player.lift_charge_timer / SHIP_FEEL.LIFT_CHARGE_CAP, 0.0, 1.0)
		return 1.0, mathx.lerp(1.0, 0.84, t), mathx.lerp(1.0, 0.29, t) -- builds toward gold
	end
	return 1.0, 1.0, 1.0
end

-- Ships: real ship.png stretched to exactly fill the hitbox (matches
-- ship_node.gd's own _update_character_art(): sprite.scale = half_extents*2
-- / tex_size, no flip — every character's ship reads the same either
-- side). Falls back to the flat team-colored rectangle if a character
-- somehow has no ship art registered.
local function draw_ship(player)
	if player.exploded_hidden then
		return -- match_arena_node.gd's _play_ship_explosion(): "loser.visible = false" — stays hidden through the match-over screen (match_over case only; a fresh round rebuilds the player table from scratch and this flag along with it)
	end
	local ship = player.ship
	-- Epic boss skin override (ship_node.gd's apply_boss_skin()): masks
	-- whichever rival is secretly playing the organizer with a dedicated
	-- look, in-game AND on the Ultra intro slot (draw_ultra_intro() below).
	local art = boss_helpers.is_ship(player) and assets.organisateur or assets.characters[player.character.id]
	local r, g, b = ship_tint(player)
	-- Vif's "saut": a visual-only zoom-in/zoom-out pulse over the jump's
	-- duration (peaks at the midpoint, back to 1.0 at takeoff/landing) — the
	-- hitbox itself (ship.half_extents) is untouched, only the drawn size.
	local jump_scale = 1.0
	if player.dash_jump_timer > 0.0 and player.dash_jump_duration > 0.0 then
		local elapsed_fraction = 1.0 - player.dash_jump_timer / player.dash_jump_duration
		jump_scale = 1.0 + dash_helpers.VIF_JUMP_SCALE_PEAK * math.sin(math.pi * elapsed_fraction)
	end
	local draw_w, draw_h = ship.half_extents.x * 2.0 * jump_scale, ship.half_extents.y * 2.0 * jump_scale
	if art and art.ship then
		love.graphics.setColor(r, g, b)
		draw_utils.draw_stretched(art.ship, ship.position.x, ship.position.y, draw_w, draw_h)
	else
		local color = SIDE_COLOR[ship.side]
		love.graphics.setColor(color[1] * r, color[2] * g, color[3] * b)
		love.graphics.rectangle("fill", ship.position.x - draw_w / 2.0, ship.position.y - draw_h / 2.0, draw_w, draw_h)
	end
end

local function draw_bar(x, y, w, h, fraction, color)
	love.graphics.setColor(0.15, 0.15, 0.18)
	love.graphics.rectangle("fill", x, y, w, h)
	love.graphics.setColor(color[1], color[2], color[3])
	love.graphics.rectangle("fill", x, y, w * mathx.clampf(fraction, 0.0, 1.0), h)
	love.graphics.setColor(0.4, 0.4, 0.45)
	love.graphics.rectangle("line", x, y, w, h)
end

-- ultra_meter_node.gd's own _draw(): a row of pip indicators, briefly
-- shaking red (a decaying sine jitter, not a fixed offset) when the
-- trigger key was pressed before the meter was actually full.
local ULTRA_PIP_SIZE = 16.0
local ULTRA_PIP_SPACING = 6.0
local ULTRA_PIP_COLOR = { 1.0, 0.84, 0.29 }
local ULTRA_DENY_COLOR = { 0.92, 0.28, 0.24 }

local function draw_ultra_pips(player, x, y)
	local shaking = player.ultra_deny_shake_timer > 0.0
	local shake_x = 0.0
	if shaking then
		shake_x = math.sin(player.ultra_deny_shake_timer * 90.0) * (player.ultra_deny_shake_timer / ULTRA_MISC.DENY_SHAKE_DURATION) * 4.0
	end
	local color = shaking and ULTRA_DENY_COLOR or ULTRA_PIP_COLOR
	local pips = player.weapon.ultra_pips
	love.graphics.setLineWidth(2.0)
	for i = 0, weapon_system_state.ULTRA_METER_MAX - 1 do
		local px = x + i * (ULTRA_PIP_SIZE + ULTRA_PIP_SPACING) + shake_x
		love.graphics.setColor(color[1], color[2], color[3], i < pips and 1.0 or 0.18)
		love.graphics.rectangle("fill", px, y, ULTRA_PIP_SIZE, ULTRA_PIP_SIZE)
		love.graphics.setColor(color[1], color[2], color[3])
		love.graphics.rectangle("line", px, y, ULTRA_PIP_SIZE, ULTRA_PIP_SIZE)
	end
	love.graphics.setLineWidth(1.0)
end

local function draw_player_hud(player, x)
	local weapon = weapon_system_state.selected_weapon(player.weapon)
	love.graphics.setColor(1, 1, 1)
	love.graphics.print(player.character.display_name, x, 8)
	draw_bar(x, 26, 160, 10, player.ship.hp / player.max_hp, { 0.3, 0.9, 0.4 })
	draw_bar(x, 40, 160, 6, player.weapon.gauges[1] / weapon.gauge_max, { 1.0, 0.85, 0.2 })
	draw_bar(x, 50, 160, 4, player.weapon.heats[1] / (weapon.heat_max > 0.0 and weapon.heat_max or 1.0), { 1.0, 0.3, 0.3 })
	draw_bar(x, 58, 160, 4, lift_charge_fraction(player.lift_charge_timer), { 0.6, 0.8, 1.0 })
	-- 2026-10-06 dash feature: fills back up as the cooldown counts down —
	-- full/bright = ready to use again.
	draw_bar(x, 64, 160, 4, 1.0 - player.dash_cooldown_timer / dash_helpers.COOLDOWN, { 0.75, 0.4, 0.95 })
	draw_ultra_pips(player, x, 76)
	if player.double_fire_shots_remaining > 0 then
		love.graphics.setColor(1.0, 0.84, 0.29)
		love.graphics.print(string.format("DOUBLE x%d", player.double_fire_shots_remaining), x, 98)
	end
	if player.ultra_flash_timer > 0.0 then
		love.graphics.setColor(1.0, 0.84, 0.29)
		love.graphics.print("ULTRA !", x, 98)
	end
end

function match_arena.draw()
	-- 2026-10-05 (feedback FX) — the whole gameplay world (background
	-- through ships/projectiles/popups) shakes; the HUD drawn after
	-- love.graphics.pop() below never does, so bars/text stay readable
	-- through a shake.
	love.graphics.push()
	do
		local shake_x, shake_y = feedback_fx.shake_offset()
		love.graphics.translate(shake_x, shake_y)
	end

	-- MatchArena.tscn's real Background art (arena_background.png),
	-- cover-fit into whatever the CURRENT arena bounds are (the
	-- shrinking_arena twist resizes this rect live — see
	-- _sync_twist_visuals() in match_arena_node.gd).
	love.graphics.setColor(1, 1, 1)
	draw_utils.draw_cover(assets.arena_background, current_arena_bounds.position.x, current_arena_bounds.position.y, current_arena_bounds.size.x, current_arena_bounds.size.y)

	-- NeutralZone: a translucent gold band straddling the frontier (ships
	-- can never cross into it — see ship_state.lua's own
	-- NEUTRAL_ZONE_HALF_WIDTH), also live-repositioned by
	-- drifting_neutral_zone.
	love.graphics.setColor(1.0, 0.84, 0.29, 0.08)
	love.graphics.rectangle(
		"fill",
		current_frontier_x - ship_state.NEUTRAL_ZONE_HALF_WIDTH,
		current_arena_bounds.position.y,
		ship_state.NEUTRAL_ZONE_HALF_WIDTH * 2.0,
		current_arena_bounds.size.y
	)

	love.graphics.setColor(0.27, 0.85, 1.0, 0.6)
	love.graphics.line(current_frontier_x, current_arena_bounds.position.y, current_frontier_x, current_arena_bounds.position.y + current_arena_bounds.size.y)

	-- Perturbateur's charged Boomerang de Feu puddles (fire_trail_node.gd) —
	-- a real ParticleSystem per puddle, drawn at ground level (under ships/
	-- projectiles), same ordering intent as the neutral zone/frontier line.
	love.graphics.setColor(1, 1, 1)
	for _, trail in ipairs(fire_trails) do
		love.graphics.draw(trail.particle_system, trail.position.x, trail.position.y)
	end

	-- Contrôleur's Ultra "Trou noir" (black_hole_node.gd) — a fainter outer
	-- halo (slow-only) behind a pulsing, animated inner vortex (pull+slow).
	-- The CPUParticles2D inward spiral isn't ported (diminishing returns —
	-- the animated sprite + breathing rings already read as "a black hole").
	for _, hole in ipairs(black_holes) do
		local pulse = 1.0 + math.sin(hole.pulse_time * 3.0) * 0.05
		love.graphics.setColor(0.25, 0.05, 0.35, 80.0 / 255.0)
		love.graphics.circle("fill", hole.position.x, hole.position.y, hole.outer_radius * pulse)
		love.graphics.setColor(1, 1, 1)
		draw_utils.draw_stretched(
			assets.black_hole_frames[hole.frame_index],
			hole.position.x, hole.position.y,
			hole.radius * 2.0 * pulse, hole.radius * 2.0 * pulse
		)
		-- 2026-10-05 (Camil: "les effets autour des ultras sont hyper
		-- classe" -> same treatment for the black hole): decorative
		-- specks sucked in along a spiral from the outer halo toward the
		-- core, speeding up and fading as they fall. Stateless — every
		-- speck's position is a pure function of hole.pulse_time, so no
		-- particle list to spawn/cull; no collision, no gameplay effect.
		for k = 1, 56 do
			local t = (hole.pulse_time * 0.5 + k / 56.0) % 1.0 -- 0 = outer edge, 1 = core
			local r = hole.outer_radius * (1.0 - t) ^ 1.3 + 8.0
			local angle = k * 2.399963 + hole.pulse_time * 0.6 + t * t * 7.0 -- golden-angle scatter, winding tighter inward
			local alpha = math.min(math.sin(t * math.pi) * 1.6, 1.0)
			love.graphics.setColor(0.8 + 0.2 * t, 0.55 + 0.45 * t, 1.0, alpha)
			love.graphics.circle("fill", hole.position.x + math.cos(angle) * r, hole.position.y + math.sin(angle) * r * 0.9, 2.5 + (1.0 - t) * 2.5)
		end
		love.graphics.setColor(1, 1, 1)
	end

	-- Perturbateur's Ultra "Brouillage de commandes": decorative glitch
	-- aura around the scrambled ship — jittering violet scan-bars plus
	-- a few static sparks, re-rolled ~20x/s so it reads as interference.
	-- Purely visual (stateless: seeded from the clock, not stored).
	for _, victim in ipairs(players) do
		if victim.controls_scrambled_timer > 0.0 then
			local frame = math.floor(love.timer.getTime() * 20.0)
			local px, py = victim.ship.position.x, victim.ship.position.y
			local fade = mathx.clampf(victim.controls_scrambled_timer / 0.5, 0.0, 1.0) -- fades out over the last half-second
			for k = 1, 6 do
				local h = math.sin(frame * 12.9898 + k * 78.233) * 43758.5453
				local r1 = h - math.floor(h)
				local r2 = (h * 7.0) - math.floor(h * 7.0)
				local bar_w = 24.0 + r1 * 52.0
				love.graphics.setColor(0.8, 0.4, 1.0, (0.6 + 0.4 * r2) * fade)
				love.graphics.rectangle("fill", px - bar_w * 0.5 + (r2 - 0.5) * 30.0, py + (r1 - 0.5) * 80.0, bar_w, 3.0 + r2 * 3.0)
			end
			for k = 1, 8 do
				local h = math.sin(frame * 5.123 + k * 31.417) * 24634.6345
				local r1 = h - math.floor(h)
				local r2 = (h * 13.0) - math.floor(h * 13.0)
				local ang = r1 * math.pi * 2.0
				local dist = 28.0 + r2 * 34.0
				love.graphics.setColor(0.95, 0.8, 1.0, fade)
				love.graphics.rectangle("fill", px + math.cos(ang) * dist, py + math.sin(ang) * dist, 5.0, 5.0)
			end
		end
	end
	love.graphics.setColor(1, 1, 1)

	draw_ship(players[1])
	-- invisible_opponent twist: the AI side's ship is simply never drawn
	-- (it still moves/collides/fires normally — only the render is
	-- skipped), matching ship_node.gd's own "hidden_from_opponent" flag.
	if not (active_twist and active_twist.twist_type == "invisible_opponent" and players[2].is_ai) then
		draw_ship(players[2])
	end

	-- debug_overlay.gd's TAB hitbox toggle — the EXACT rect projectile
	-- collision checks against (ship_node.gd/turret_node.gd's own _draw()).
	if show_hitboxes then
		love.graphics.setColor(1.0, 0.15, 0.15, 0.9)
		love.graphics.setLineWidth(4.0)
		love.graphics.rectangle("line", ship_rect(players[1].ship))
		love.graphics.rectangle("line", ship_rect(players[2].ship))
		for _, turret in ipairs(turrets) do
			love.graphics.rectangle("line", ship_rect(turret))
		end
		love.graphics.setLineWidth(1.0)
	end

	-- Ship explosion debris/disintegration bursts (ship_explosion_helpers.round) —
	-- drawn right over where the ship just was.
	love.graphics.setColor(1, 1, 1)
	for _, burst in ipairs(ship_explosion_helpers.bursts) do
		love.graphics.draw(burst.particle_system, 0, 0)
	end

	-- Spreader's passive heal flourish — orbits whichever ship it just healed.
	draw_heal_fx()

	-- hazard_zones twist — real hazard_zone.png warning badge, stretched to
	-- radius*2 (hazard_zone_node.gd: sprite.scale = radius*2/tex_size), so
	-- it always matches the actual hit-test circle.
	for _, hazard in ipairs(hazards) do
		love.graphics.setColor(1, 1, 1)
		draw_utils.draw_stretched(assets.hazard_zone, hazard.position.x, hazard.position.y, hazard.radius * 2.0, hazard.radius * 2.0)
	end

	-- energy_orb_pickup twist — a small spinning-looking octagon (real art
	-- is Phase 7).
	for _, orb in ipairs(orbs) do
		love.graphics.setColor(1.0, 0.9, 0.3, 0.9)
		love.graphics.circle("fill", orb.position.x, orb.position.y, TWIST_TUNING.ORB_PICKUP_RADIUS)
	end

	-- visual_decoy twist ("Double moi") — a slightly translucent copy of
	-- the opponent's own ship art, pure confusion, no collision with
	-- anything.
	if decoy then
		local art = assets.characters[decoy.character_id]
		if art and art.ship then
			love.graphics.setColor(1, 1, 1, 0.75)
			draw_utils.draw_stretched(art.ship, decoy.position.x, decoy.position.y, SHIP_HALF_EXTENTS.x * 2.0, SHIP_HALF_EXTENTS.y * 2.0)
		else
			love.graphics.setColor(decoy.color[1], decoy.color[2], decoy.color[3], 0.85)
			love.graphics.rectangle("fill", decoy.position.x - 14.0, decoy.position.y - 28.0, 28.0, 56.0)
		end
	end

	-- Controleur's turrets — real turret.png (or the gold turret_charged.png
	-- for a charged-fire placement) stretched to fill the hitbox
	-- (turret_node.gd: sprite.scale = half_extents*2/tex_size), flipped for
	-- side 1 (mirrors the dial/handle detail), white-tinted normally and
	-- briefly brightened (not recolored) on a hit flash.
	for _, turret in ipairs(turrets) do
		local flash = turret.flash_timer > 0.0 and 1.5 or 1.0
		love.graphics.setColor(flash, flash, flash)
		draw_utils.draw_stretched(
			turret.is_charged and assets.turret_charged or assets.turret,
			turret.position.x,
			turret.position.y,
			turret.half_extents.x * 2.0,
			turret.half_extents.y * 2.0,
			turret.owner_side == 1
		)
		-- Mitrailleur's Ultra satellites: little energy arcs crackling
		-- around the module and orbiting it. Decorative, stateless.
		if turret.weapon_id == ULTRA_MITRAILLEUSES_SATELLITES.id then
			local now = love.timer.getTime()
			local frame = math.floor(now * 24.0)
			local cx, cy = turret.position.x, turret.position.y
			local orbit_r = math.max(turret.half_extents.x, turret.half_extents.y) * 1.5
			for k = 1, 5 do
				local base = now * (3.0 + k) + k * 2.094 -- three arcs orbiting at different speeds, 120 deg apart
				local x1, y1 = cx + math.cos(base) * orbit_r, cy + math.sin(base) * orbit_r
				local px, py = x1, y1
				love.graphics.setColor(0.5, 0.9, 1.0, 0.9)
				love.graphics.setLineWidth(3.0)
				for s = 1, 5 do
					local h = math.sin(frame * 12.9898 + k * 31.7 + s * 78.233) * 43758.5453
					local jitter = (h - math.floor(h)) - 0.5
					local a2 = base + s * 0.22
					local nx = cx + math.cos(a2) * (orbit_r + jitter * 22.0)
					local ny = cy + math.sin(a2) * (orbit_r + jitter * 22.0)
					love.graphics.line(px, py, nx, ny)
					px, py = nx, ny
				end
				love.graphics.setColor(0.9, 1.0, 1.0, 1.0)
				love.graphics.circle("fill", x1, y1, 4.0)
			end
			love.graphics.setLineWidth(1.0)
			love.graphics.setColor(1, 1, 1)
		end
	end

	-- Bourrasque's decorative wind streaks (behind the vortices; see
	-- update_wind_gusts()).
	if wind_gusts.streaks then
		for _, streak in ipairs(wind_gusts.streaks) do
			local t = streak.age / streak.life
			local alpha = 0.75 * math.sin(t * math.pi) -- fade in then out
			local dir = streak.speed >= 0.0 and 1.0 or -1.0
			love.graphics.setColor(0.85, 0.95, 1.0, alpha)
			love.graphics.setLineWidth(streak.thickness)
			love.graphics.line(streak.x, streak.y, streak.x - dir * streak.length, streak.y)
			if streak.curl then
				love.graphics.circle("line", streak.x, streak.y, 3.0 + streak.thickness)
			end
		end
		love.graphics.setLineWidth(1)
	end

	-- Weapon projectiles: real per-weapon art (assets.bullets), sized by
	-- the bullet's own visual_scale (set at spawn time — see
	-- spawn_projectile()'s size_multiplier param, which charged fire uses
	-- to bump a boomerang up "5 fois la taille") and flipped by travel
	-- direction — machine_gun/turret bullets are already side-specific
	-- textures (no flip needed for those). Turret bullets fly straight at
	-- their target, so they're rotated to face their own velocity
	-- (turret_node.gd's _fire_at_target(): rotation = aim.angle()).
	for _, bullet in ipairs(bullets) do
		local image
		if bullet.anim_textures then
			-- Bourrasque's wind1/wind2/wind3 flipbook (no self-rotation —
			-- 2026-08-16 playtest: "les tourbillons ne doivent pas tourner
			-- sur eux meme", the animated cycle alone sells the tornado).
			image = bullet.anim_textures[bullet.anim_frame_index]
		else
			local weapon_id = assets.bullets[bullet.weapon_id] and bullet.weapon_id or "machine_gun"
			image = assets.bullets[weapon_id]
			if SIDE_SPLIT_BULLET_WEAPONS[weapon_id] then
				image = image[bullet.owner_side]
			end
		end
		love.graphics.setColor(1, 1, 1)
		if bullet.weapon_id == "turret" then
			draw_utils.draw_scaled(image, bullet.position.x, bullet.position.y, bullet.visual_scale, false, bullet.velocity:angle())
		else
			-- projectile_factory.gd: flip_h = direction < 0.0 for every
			-- weapon EXCEPT is_heavy (bazooka), which is the one deliberate
			-- inversion (flip_h = direction > 0.0). Bourrasque's vortices are
			-- built directly (never through the factory), so they keep its
			-- default: never flipped.
			local flip_h
			if bullet.weapon_id == "bazooka" then
				flip_h = bullet.velocity.x > 0.0
			elseif bullet.weapon_id == "ultra_bourrasque" then
				flip_h = false
			else
				flip_h = bullet.velocity.x < 0.0
			end
			draw_utils.draw_scaled(image, bullet.position.x, bullet.position.y, bullet.visual_scale, flip_h, bullet.rotation)
		end

		-- 2026-10-05 decorative per-bullet particles (Spreader's Ultra fans,
		-- Traqueur's missile plume) — shared with the mini-jeu screens, see bullet_fx.lua.
		bullet_fx.draw(bullet, image)
	end

	-- 2026-10-06 dash feature: Contrôleur's phantom paddle / Mitrailleur's &
	-- Spreader's thrown clones — drawn AFTER bullets (not before), so a shot
	-- passing through one visibly disappears behind the ship art instead of
	-- rendering on top of it (Camil: "le tir doit passer dessous le vaisseau
	-- [...] cache par le vaisseau"). Just the owner's own real ship art,
	-- translucent and gently pulsing — no hitbox outline anymore ("enleve le
	-- rectangle de hitbox"). Fade window is relative to each clone's own
	-- lifetime, not a flat 0.5s (Spreader's 0.25s clones were nearly
	-- invisible under that: "on ne voit pas assez les clones").
	for _, ghost in ipairs(ghost_paddles) do
		local art = assets.characters[ghost.character_id]
		if art and art.ship then
			local fade_window = math.min(0.5, ghost.initial_lifetime)
			local fade = mathx.clampf(ghost.lifetime / fade_window, 0.0, 1.0)
			local pulse = 0.75 + 0.2 * math.sin(love.timer.getTime() * 10.0)
			love.graphics.setColor(1.0, 1.0, 1.0, pulse * fade)
			draw_utils.draw_stretched(art.ship, ghost.position.x, ghost.position.y, ghost.half_extents.x * 2.0, ghost.half_extents.y * 2.0)
		end
	end
	love.graphics.setColor(1, 1, 1)

	-- Lourd's Ultra "Pluie de Scuds" (missile_strike_node.gd): a closing
	-- ring counts down to impact while the shell sprite falls in (starts
	-- big + offset upward, shrinks/slides down onto the target).
	love.graphics.setLineWidth(3.0)
	for _, strike in ipairs(missile_strikes) do
		local t = mathx.clampf(strike.elapsed / strike.fall_duration, 0.0, 1.0)
		love.graphics.setColor(1.0, 0.35, 0.1, 0.85)
		love.graphics.arc("line", "open", strike.position.x, strike.position.y, strike.impact_radius, -math.pi / 2.0, -math.pi / 2.0 + math.pi * 2.0 * t, 32)
		love.graphics.setColor(1, 1, 1)
		local shell_scale = mathx.lerp(UT.MISSILE_STRIKE_START_SCALE, 1.0, t)
		local y_offset = mathx.lerp(-UT.MISSILE_STRIKE_SPAWN_Y_OFFSET, 0.0, t)
		draw_utils.draw_scaled(assets.bullets.bazooka, strike.position.x, strike.position.y + y_offset, shell_scale)
	end
	love.graphics.setLineWidth(1.0)

	-- Zoneur's Ultra "Grille Laser" (laser_mesh_node.gd): arbitrary-angle
	-- segments, same quick fade in/out as the normal beam weapon.
	for _, laser in ipairs(laser_meshes) do
		local alpha = 1.0
		if laser.elapsed < UT.GRILLE_LASER_FADE_DURATION and not laser.sweep_duration then
			alpha = laser.elapsed / UT.GRILLE_LASER_FADE_DURATION
		elseif laser.elapsed > laser.lifetime - UT.GRILLE_LASER_FADE_DURATION then
			alpha = mathx.clampf((laser.lifetime - laser.elapsed) / UT.GRILLE_LASER_FADE_DURATION, 0.0, 1.0)
		end
		love.graphics.setColor(UT.GRILLE_LASER_COLOR[1], UT.GRILLE_LASER_COLOR[2], UT.GRILLE_LASER_COLOR[3], UT.GRILLE_LASER_COLOR[4] * alpha)
		love.graphics.setLineWidth(laser.thickness)
		local head = laser.end_point
		if laser.sweep_duration then
			head = laser.start_point + (laser.end_point - laser.start_point) * mathx.clampf(laser.elapsed / laser.sweep_duration, 0.0, 1.0)
		end
		love.graphics.line(laser.start_point.x, laser.start_point.y, head.x, head.y)
		-- Welding-torch sparks at the racing head (and for a moment after it
		-- lands), flying off in random directions. Decorative, stateless
		-- (re-seeded from the clock ~60x/s).
		if laser.sweep_duration and laser.elapsed < laser.sweep_duration + 0.3 then
			local frame = math.floor(love.timer.getTime() * 60.0)
			local spark_fade = laser.elapsed < laser.sweep_duration and 1.0 or (1.0 - (laser.elapsed - laser.sweep_duration) / 0.3)
			love.graphics.setColor(1.0, 1.0, 0.85, spark_fade)
			love.graphics.circle("fill", head.x, head.y, laser.thickness * 2.0)
			for k = 1, 18 do
				local h = math.sin(frame * 12.9898 + k * 78.233) * 43758.5453
				local r1 = h - math.floor(h)
				local r2 = (h * 7.0) - math.floor(h * 7.0)
				local ang = r1 * math.pi * 2.0
				local dist = 4.0 + r2 * 38.0
				love.graphics.setColor(1.0, 0.85 + 0.15 * r2, 0.4, spark_fade)
				love.graphics.rectangle("fill", head.x + math.cos(ang) * dist, head.y + math.sin(ang) * dist, 4.0, 4.0)
			end
		end
	end
	love.graphics.setLineWidth(1.0)

	-- Zoneur's beam (beam_node.gd's _update_shape()/_update_fade()): a
	-- translucent bar from the shooter out to the arena wall (or its own
	-- range, whichever is closer), fading in/out quickly at both ends.
	for _, beam in ipairs(beams) do
		local origin = beam.player.ship.position
		local direction = beam.player.side == 0 and 1.0 or -1.0
		local wall_x = direction > 0.0 and (current_arena_bounds.position.x + current_arena_bounds.size.x) or current_arena_bounds.position.x
		local max_reach_x = origin.x + direction * beam.range
		local far_x = direction > 0.0 and math.min(wall_x, max_reach_x) or math.max(wall_x, max_reach_x)
		local length = math.abs(far_x - origin.x)

		local alpha = 1.0
		if beam.elapsed < BEAM.FADE_DURATION then
			alpha = beam.elapsed / BEAM.FADE_DURATION
		elseif beam.elapsed > beam.lifetime - BEAM.FADE_DURATION then
			alpha = mathx.clampf((beam.lifetime - beam.elapsed) / BEAM.FADE_DURATION, 0.0, 1.0)
		end

		love.graphics.setColor(0.4, 1.0, 0.5, 0.7 * alpha)
		love.graphics.rectangle(
			"fill",
			direction > 0.0 and origin.x or (origin.x - length),
			origin.y - beam.thickness / 2.0,
			length,
			beam.thickness
		)
	end

	-- Per-weapon impact VFX (see IMPACT_STYLE_BY_WEAPON):
	-- "spark_ring" (Mitrailleur) — a small, very quick expanding/fading ring.
	-- "fan_shatter" (Spreader) — the fan's sprite breaking into a few
	-- tumbling fragments that fly outward and fade, like a tiny firework.
	-- "big_explosion" (Lourd) — a fading shockwave ring plus flying debris
	-- particles (2026-09-27).
	-- "saber_slash" (Perturbateur) — "une ligne tres rapide et courte...
	-- comme un coup de sabre" — a short diagonal flash.
	-- "laser_spark" (Zoneur) — "des mini particules blanches qui popent
	-- comme des petits eclairs", fired once per damage tick while the beam
	-- connects, reading as a continuous sparkle rather than one-off hits.
	love.graphics.setLineWidth(2.0)
	for _, impact in ipairs(impacts) do
		local t = impact.age / impact.duration
		if impact.style == "fan_shatter" then
			for _, vel in ipairs(impact.particles) do
				local p = impact.position + vel * impact.age
				love.graphics.setColor(1.0, 1.0 - 0.5 * t, 0.4 + 0.4 * t, 1.0 - t)
				love.graphics.rectangle("fill", p.x - 2.0, p.y - 2.0, 4.0, 4.0)
			end
		elseif impact.style == "laser_spark" then
			for _, vel in ipairs(impact.particles) do
				local p = impact.position + vel * impact.age
				love.graphics.setColor(1.0, 1.0, 1.0, 1.0 - t)
				love.graphics.circle("fill", p.x, p.y, 2.0)
			end
		elseif impact.style == "vortex_split" then
			for _, vel in ipairs(impact.particles) do
				local p = impact.position + vel * impact.age
				love.graphics.setColor(0.7, 0.9, 1.0, 1.0 - t)
				love.graphics.circle("fill", p.x, p.y, 3.0)
			end
		elseif impact.style == "saber_slash" then
			-- saber_slash_node.gd: always the SAME corner-to-corner
			-- diagonal (top-left to bottom-right of the target's own
			-- bounding box) — not a random angle.
			love.graphics.setColor(0.6, 0.85, 1.0, 1.0 - t)
			love.graphics.setLineWidth(4.0)
			love.graphics.line(
				impact.position.x - SHIP_HALF_EXTENTS.x,
				impact.position.y - SHIP_HALF_EXTENTS.y,
				impact.position.x + SHIP_HALF_EXTENTS.x,
				impact.position.y + SHIP_HALF_EXTENTS.y
			)
			love.graphics.setLineWidth(2.0)
		elseif impact.style == "big_explosion" then
			-- Fading shockwave ring plus real flying debris (2026-09-27,
			-- replacing the old plain-ring-only look).
			love.graphics.setColor(1.0, 0.55, 0.2, 0.6 * (1.0 - t))
			love.graphics.circle("line", impact.position.x, impact.position.y, impact.radius * t)
			for _, vel in ipairs(impact.particles) do
				local p = impact.position + vel * impact.age
				love.graphics.setColor(1.0, 0.55 + 0.35 * (1.0 - t), 0.1 + 0.2 * (1.0 - t), 1.0 - t)
				love.graphics.circle("fill", p.x, p.y, 3.0 + 2.0 * (1.0 - t))
			end
		elseif impact.style == "bounce_flash" then
			-- 2026-10-05 playtest, round 2: "c'est super ! L'anneau est un
			-- peu 'large' et trop blanc (80% suffiraient), par contre le
			-- radius est parfait" — a solid filled disc read as too heavy/
			-- "large"; a stroked ring at the same radius (kept exactly as
			-- playtested) reads lighter, and the color is dimmed to 80%
			-- white instead of a pure, fully-opaque white.
			love.graphics.setColor(0.8, 0.8, 0.8, 0.8 * (1.0 - t))
			love.graphics.setLineWidth(5.0)
			love.graphics.circle("line", impact.position.x, impact.position.y, impact.radius * (1.0 - t * 0.5))
			love.graphics.setLineWidth(1.0)
		else
			local c = impact.color
			love.graphics.setColor(c[1], c[2], c[3], 1.0 - t)
			love.graphics.circle("line", impact.position.x, impact.position.y, impact.radius * t)
		end
	end
	love.graphics.setLineWidth(1.0)

	-- Ball's "etoile filante" trail, drawn BEFORE the ball sprite so it
	-- always reads as trailing behind it, never on top. Drawn at the
	-- origin, not at the ball's position — setPosition() (called every
	-- frame in match_arena.update()) already baked each particle's real
	-- world-space spawn point in.
	love.graphics.setColor(1, 1, 1)
	love.graphics.draw(ball_trail_ps, 0, 0)

	-- ball_node.gd: native ball_1.png size * 1.4 (BALL_SPRITE_SCALE), an
	-- art-direction size independent of BallState.RADIUS's own hit-test
	-- geometry — times ball_scale (the post-miss "pops in oversized,
	-- shrinks back" zoom), spinning continuously via ball_rotation.
	-- 2026-10-05 ("tout plus gros" pass, Camil: "l'a balle n'est pas plus
	-- grosse") — found it: this draw-only scale is exactly that
	-- RADIUS-independent art size the comment above warns about, so
	-- bumping ball_state.RADIUS alone (already done) never touched what's
	-- actually drawn. x1.5 on top of the base 1.4, matching every other
	-- bullet's own `.scale` bump.
	love.graphics.setColor(1, 1, 1)
	draw_utils.draw_scaled(assets.ball, ball.position.x, ball.position.y, 1.4 * 1.5 * ball_scale, false, ball_rotation)

	-- multi_ball twist's extra balls — same sprite/scale/spin AND trail as
	-- the primary, each with its own independent ParticleSystem.
	for _, extra in ipairs(extra_balls) do
		love.graphics.setColor(1, 1, 1)
		love.graphics.draw(extra.trail_ps, 0, 0)
		draw_utils.draw_scaled(assets.ball, extra.ball_data.position.x, extra.ball_data.position.y, 1.4 * 1.5 * (extra.scale or 1.0), false, extra.rotation or 0.0)
	end

	-- Ball-miss travel effect (gauge_fill_effect_node.gd) — drawn before its
	-- own eventual "+X" floating text lands.
	draw_gauge_fill_effects()

	-- "+X" popups drifting up and fading — Spreader's heal (green) and the
	-- gauge-fill travel effect's own arrival (gold), same FloatingTextNode
	-- convention either way.
	for _, text in ipairs(floating_texts) do
		local t = mathx.clampf(text.age / text.duration, 0.0, 1.0)
		love.graphics.setColor(text.color[1], text.color[2], text.color[3], (text.color[4] or 1.0) * (1.0 - t))
		love.graphics.print(text.text, text.position.x, text.position.y - t * 24.0)
	end

	love.graphics.pop() -- end of the shaking gameplay world — HUD below stays fixed

	draw_player_hud(players[1], ARENA_BOUNDS.position.x)
	draw_player_hud(players[2], ARENA_BOUNDS.position.x + ARENA_BOUNDS.size.x - 160)

	love.graphics.setColor(1, 1, 1)
	local title = string.format("Manches : %d - %d", match_state.rounds_for(match, 0), match_state.rounds_for(match, 1))
	if active_twist then
		title = title .. " | Twist : " .. active_twist.display_name
	end
	love.graphics.printf(
		title,
		ARENA_BOUNDS.position.x,
		ARENA_BOUNDS.position.y - 20,
		ARENA_BOUNDS.size.x,
		"center"
	)

	-- Epic boss phase escalation beat (match_arena_node.gd's
	-- _flash_boss_phase_message()) — non-blocking, fades out on its own.
	if boss_helpers.message_timer > 0.0 then
		love.graphics.setColor(1, 1, 1)
		print_scaled(boss_helpers.message, 0, ARENA_BOUNDS.position.y - 50, 40, "center", 1280)
	end

	-- Gated on ship_explosion_helpers.round being nil (match.match_over itself
	-- already flips the instant the killing blow lands) so the "appuyer
	-- pour continuer" reveal genuinely waits for the explosion to finish —
	-- matches Godot awaiting the whole explosion before touching
	-- match_state.match_over's consequences at all.
	if match.match_over and not ship_explosion_helpers.round then
		local message
		if campaign_mode then
			if match.winner_side == 0 then
				-- match_arena_node.gd's _resolve_campaign_result() reveal —
				-- a mook win is routine ("Victoire (+X)"); a real rival win
				-- shows the unlocked reward's icon/name/description; the
				-- Organisateur win gets the tournament's own biggest beat,
				-- naming whichever rival was secretly playing the masked
				-- boss (see boss_helpers).
				if campaign_context.debug_encounter then
					message = "Victoire"
				elseif campaign_context.is_organizer_fight() then
					message = string.format("Tournoi remporte !\nL'Organisateur etait... %s !\n(Espace/Entree pour continuer)", campaign_encounter.opponent.display_name)
				elseif campaign_encounter.is_mook then
					message = string.format("Victoire (+%d)\n(Espace/Entree pour continuer)", campaign_encounter.reward_currency)
				elseif campaign_encounter.unlock_reward then
					message = string.format(
						"Rival vaincu !\nVous avez gagne : %s\n%s\n(Espace/Entree pour continuer)",
						campaign_encounter.unlock_reward.display_name,
						campaign_encounter.unlock_reward.passive_description
					)
				else
					message = "Rival vaincu !\n(Espace/Entree pour continuer)"
				end
			else
				message = "Defaite... (Espace/Entree pour continuer)"
			end
		else
			message = string.format("Match termine - Joueur %d gagne !", match.winner_side + 1)
		end
		love.graphics.printf(
			message,
			ARENA_BOUNDS.position.x,
			ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0 - 30,
			ARENA_BOUNDS.size.x,
			"center"
		)

		-- match_arena_node.gd's own reward-reveal icon ("on pourrait
		-- ajouter la recompense: icone + nom + description") — a small
		-- tinted swatch above the "Vous avez gagne" text.
		if campaign_mode and match.winner_side == 0 and not campaign_context.debug_encounter
			and not campaign_context.is_organizer_fight() and not campaign_encounter.is_mook
			and campaign_encounter.unlock_reward then
			local tint = WEAPON_TINT[campaign_encounter.unlock_reward.id] or { 1.0, 1.0, 1.0 }
			love.graphics.setColor(tint[1], tint[2], tint[3])
			love.graphics.rectangle("fill", 1280.0 / 2.0 - 12.0, ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0 - 62.0, 24.0, 24.0)
		end

		-- Versus's own post-match choice menu (see match_arena.update()'s
		-- own doc comment) — drawn below the "Match termine" line above,
		-- once the short beat after it has elapsed.
		if post_match_choice then
			local lines = {}
			for i, choice in ipairs(POST_MATCH_CHOICES) do
				local marker = (i - 1 == post_match_choice.index) and "> " or "  "
				table.insert(lines, marker .. choice)
			end
			love.graphics.setColor(0.95, 0.95, 1.0)
			love.graphics.printf(
				table.concat(lines, "\n"),
				ARENA_BOUNDS.position.x,
				ARENA_BOUNDS.position.y + ARENA_BOUNDS.size.y / 2.0 + 20,
				ARENA_BOUNDS.size.x,
				"center"
			)
		end
	end

	if round_start_gate then
		draw_round_start_gate()
	end

	-- Drawn LAST — covers the whole screen for a moment, on top of the HP
	-- bars/labels too, same as Godot's own intro (added as a child of
	-- DebugHUD, the topmost layer).
	if ultra_intro then
		draw_ultra_intro()
	end
	if pause_state then
		draw_pause_menu()
	end
end

-- Grants the win's reward (mook currency, or a rival/organizer's unlock),
-- advances the flat campaign step, and persists it — only on an actual
-- win; a loss changes nothing so the same tile can be retried. Either way
-- returns to CampaignMap.
local function resolve_campaign_result()
	-- Lazy requires to avoid a load-time cycle: campaign_map/
	-- campaign_cheat_menu require this module up front to switch INTO it,
	-- so this module can't require them back at the top of the file. By
	-- the time a keypress can happen every screen is long since fully
	-- loaded, so this just returns the cached module instantly (same
	-- pattern as the Versus Escape handler below).
	local screen_manager = require("screen_manager")

	-- Cheat menu fight (campaign_context.debug_encounter set): "No
	-- currency/unlock/branch_step side effects" — bounces straight back to
	-- the cheat menu instead of CampaignMap so twists can be swapped and
	-- re-tested immediately, and so a debug fight can NEVER corrupt real
	-- campaign progress on disk.
	if campaign_context.debug_encounter then
		campaign_context.return_to_map()
		local campaign_cheat_menu = require("screens.campaign_cheat_menu")
		screen_manager.switch_to(campaign_cheat_menu)
		return
	end

	local won_the_tournament = false
	if match.winner_side == 0 then
		if campaign_encounter.is_mook then
			campaign_save.add_currency(campaign_character_id, campaign_encounter.reward_currency)
		else
			if campaign_encounter.unlock_reward then
				campaign_save.grant_unlock(campaign_character_id, campaign_encounter.unlock_reward.id)
			end
			if campaign_context.is_organizer_fight() then
				campaign_save.mark_organizer_defeated(campaign_character_id)
				won_the_tournament = true
			end
		end
		-- 2026-08-31 graph-mode (Camil: "la campagne DOIT se baser
		-- uniquement sur la carte") — mark this specific node resolved by
		-- id rather than advancing a linear integer step; branch/linear-
		-- mode characters keep the old path. Neither runs on a tournament
		-- win — nothing left to track once the campaign is over.
		if not won_the_tournament then
			if campaign_context.is_graph_mode then
				campaign_save.add_resolved_case_id(campaign_character_id, campaign_context.current_graph_node_id)
			else
				campaign_context.advance_step()
				campaign_save.set_campaign_progress(campaign_character_id, campaign_context.campaign_step)
			end
		end
	end
	campaign_context.return_to_map()
	if won_the_tournament then
		-- 2026-08-22 (Camil: "fin du tournoi => Tournoi remporte, il faudrait
		-- revenir a l'accueil ensuite") — nothing left to do on THIS
		-- character's own map once its organizer is beaten; TitleScreen is
		-- the real home screen (was CampaignMap before this fix).
		campaign_context.clear()
		local title_screen = require("screens.title_screen")
		screen_manager.switch_to(title_screen)
	else
		local campaign_map = require("screens.campaign_map")
		screen_manager.switch_to(campaign_map)
	end
end

function match_arena.keypressed(key)
	if key == "tab" then
		show_hitboxes = not show_hitboxes
		return
	end
	if campaign_mode then
		if match.match_over and not ship_explosion_helpers.round and (key == "space" or key == "return") then
			resolve_campaign_result()
		elseif key == "escape" and campaign_context.debug_encounter then
			-- Cheat-menu fights skip the universal pause menu entirely and
			-- bail straight back, mid-fight or not — same fast-iteration
			-- "Echap ramene au menu" the cheat menu workflow has always
			-- used. Counts as neither a win nor a loss: nothing is granted,
			-- nothing advances, the tile stays exactly as it was. A REAL
			-- campaign fight's mid-fight Escape goes through the pause menu
			-- instead (polled in match_arena.update(), see open_pause_menu()).
			local screen_manager = require("screen_manager")
			campaign_context.return_to_map()
			local campaign_cheat_menu = require("screens.campaign_cheat_menu")
			screen_manager.switch_to(campaign_cheat_menu)
		end
		return
	end

	-- 2026-09-14: R/Escape used to shortcut straight to rematch/character-
	-- select here — replaced by the real post-match choice MENU (see
	-- match_arena.update()'s own doc comment), same up/down+confirm
	-- interaction every other menu in this port uses, matching Godot's own
	-- _process_post_match_choice() (which has no keyboard shortcuts of its
	-- own either, menu-only).
end

return match_arena
