-- Ported from godot_project/simulation/twist_data.gd — data-driven "match
-- twist" definition. A rival/boss encounter references one of these, and
-- the match orchestration layer applies its configuration for the
-- duration of that match. Pure data — no simulation logic lives here.

local twist_data = {}

function twist_data.new(overrides)
	local t = {
		id = "",
		display_name = "",

		-- Drives which systems read the fields below.
		twist_type = "none", -- "none" | "multi_ball" | "gauge_floor" | "shrinking_arena" | "invisible_opponent" | "hazard_zones" | "drifting_neutral_zone" | "visual_decoy" | "energy_orb_pickup"

		-- twist_type == "multi_ball" only:
		ball_count = 2, -- 2 = double balle, 3 = triple

		-- twist_type == "gauge_floor" only: self-fill on successful return is
		-- locked, but the miss-gauge-fill is never touched ("sinon on perd
		-- le core game").
		passive_trickle_rate = 2.5, -- % of gauge_max per second, guarantees no softlock

		-- twist_type == "shrinking_arena" only:
		shrink_interval = 15.0, -- seconds between each shrink step
		shrink_fraction = 0.1, -- fraction of depth removed per side, per step
		shrink_animation_duration = 1.5, -- seconds — never instant

		-- twist_type == "hazard_zones" only:
		hazard_count = 2,
		hazard_radius = 24.0,
		hazard_spawn_interval = 8.0,
		hazard_lifetime = 6.0,
		hazard_stuns_ships = true,
		hazard_deflects_ball = true,

		-- twist_type == "drifting_neutral_zone" only: continuous
		-- back-and-forth motion at drift_speed.
		drift_speed = 40.0, -- px/sec
		drift_range = 120.0, -- max distance from the arena's true center before reversing

		-- twist_type == "visual_decoy" only ("Double moi" — zero damage, zero
		-- HP, pure confusion):
		decoy_wander_speed = 180.0,

		-- twist_type == "energy_orb_pickup" only — the organizer's OWN
		-- signature mechanic, deliberately NOT part of the shared pool above
		-- (reserved for the boss, needs its own spawn/pickup state machine).
		orb_gauge_bonus_percent = 20.0, -- reuses weapon_system_state.with_gauge_added(), no new gauge system
		orb_spawn_interval = 10.0,

		-- 3-phase final boss: same energy_orb_pickup twist, extended rather
		-- than a second boss-only twist_type — this IS already "the boss's
		-- own mechanic".
		boss_size_multiplier = 2.5, -- half_extents scale
		boss_hp_multiplier = 2.2, -- on top of ship_state.START_HP
		boss_permanent_buff_percent = 15.0, -- phase 1 baseline edge over a normal character (fire_rate + damage)
		boss_phase2_hp_fraction = 0.65, -- crossing this (falling) triggers phase 2
		boss_phase3_hp_fraction = 0.30, -- crossing this (falling) triggers phase 3
		boss_phase2_orb_interval_multiplier = 0.5, -- halves orb_spawn_interval from phase 2 onward
	}
	for key, value in pairs(overrides or {}) do
		t[key] = value
	end
	return t
end

return twist_data
