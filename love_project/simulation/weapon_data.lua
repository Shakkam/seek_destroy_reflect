-- Ported from godot_project/simulation/weapon_data.gd — data-driven weapon
-- definition. Per the port spec (section 3, "Resource -> Lua table"),
-- there is no Resource/.tres equivalent in Lua: this module is the SCHEMA
-- (the full set of fields + their Godot @export defaults), and an actual
-- weapon (e.g. what laser.tres held) is built by overriding fields on top
-- of it — see data/weapons/*.lua once that folder itself is ported.
--
-- Never hardcode weapon stats anywhere else — always build a weapon via
-- weapon_data.new(overrides).

local weapon_data = {}

function weapon_data.new(overrides)
	local w = {
		id = "",
		display_name = "",
		damage = 2.0, -- fixed damage per hit. For effect_type == "beam", reinterpreted as damage PER SECOND for the pulse's duration.
		fire_rate = 5.0, -- shots per second (beam: cooldown between pulses)
		gauge_max = 100.0,
		gauge_cost_per_shot = 10.0,
		is_heavy = false, -- triggers a vulnerability window on fire (Story 1.8)

		-- "damage" | "turret" | "mobility_boost" | "stun" | "beam"
		effect_type = "damage",

		-- effect_type == "mobility_boost" / "stun" only:
		effect_duration = 0.0,
		effect_speed_multiplier = 1.0,

		homing_strength = 0.0, -- 0 = straight line; >0 = gently steers toward target
		beam_range = 500.0, -- effect_type == "beam" only
		beam_duration = 0.5, -- effect_type == "beam" only: normal-fire pulse duration
		beam_thickness_multiplier = 1.0,
		charged_beam_duration = 0.0, -- 0 falls back to beam_duration
		charged_beam_shooter_slow_multiplier = 1.0,
		charged_beam_thickness_multiplier = 1.0,
		turret_hp = 22.0, -- effect_type == "turret" only
		turret_lifetime = 25.0,

		-- Controleur's charged turret: fires faster, expires sooner.
		charged_turret_fire_rate_multiplier = 1.0,
		charged_turret_lifetime = 0.0, -- 0 = fall back to turret_lifetime

		-- "Shmup juice pass" — data-driven so tuning any of this is authoring
		-- data, never a code change.
		spread_deg = 2.0, -- random angle jitter per shot, non-heavy weapons only
		projectile_count = 1,
		burst_spread_deg = 0.0,
		burst_stagger = 0.0, -- seconds between each projectile's spawn within a burst
		is_boomerang = false,
		visual_scale_multiplier = 1.0,

		-- Heat gauge: 0 = disabled.
		heat_max = 0.0,
		heat_per_shot = 0.0,
		heat_cooldown_rate = 0.0, -- heat drained per second while not firing

		-- Per-weapon projectile speed/spin.
		projectile_speed = 620.0,
		projectile_spin_speed = 0.0, -- deg/sec

		-- Vif's original Tourbillon (small forward-advancing loops).
		is_looping = false,
		loop_radius = 18.0,
		loop_angular_speed = 1080.0, -- deg/sec

		-- 2026-08-13 rework of Vif's Tourbillon: straight-line net progress
		-- with a lateral wave riding on top.
		is_sine = false,
		sine_amplitude = 40.0,
		sine_angular_speed = 720.0, -- deg/sec

		-- Vif's fire-recoil speed kick, decaying linearly to 0. 0 = disabled.
		fire_recoil_speed_boost = 0.0,
		fire_recoil_boost_decay_time = 0.5,

		-- Charged fire. 0 duration = this weapon has no charged fire at all.
		charge_fire_duration = 0.0,
		charge_fire_slow_multiplier = 1.0,
		charged_projectile_count = 1,
		charged_burst_spread_deg = 0.0,
		charged_burst_ping_pong = false, -- sweep out and back within the same burst (triangle wave) instead of one-way
		charged_stagger = 0.0,
		charged_speed_multiplier = 1.0,
		charged_damage_multiplier = 1.0,
		charged_visual_scale_multiplier = 1.0,

		-- Perturbateur's boomerang range: 0 on either field means "use the
		-- engine-side default".
		boomerang_out_duration = 0.0, -- seconds outbound before curving back on a NORMAL throw
		charged_boomerang_out_duration = 0.0, -- ...on the CHARGED throw

		-- Mitrailleur's charged fire: a pure self-buff on release (no
		-- projectile burst at all — charged_projectile_count is ignored).
		charged_double_fire_shots = 0, -- how many subsequent normal shots fire doubled. 0 = disabled.
		charged_double_fire_offset = 10.0, -- px vertical separation between the two parallel shots

		-- Epic 4 reward system: auto-fires on this interval with no player
		-- input once unlocked. 0 (default) = not usable as a passive reward.
		passive_interval = 0.0,
		passive_description = "", -- one-line, player-facing description shown on the reward reveal screen
	}
	for key, value in pairs(overrides or {}) do
		w[key] = value
	end
	return w
end

return weapon_data
