local weapon_data = require("simulation.weapon_data")

-- Ported from godot_project/data/weapons/bazooka.tres.
return weapon_data.new({
	id = "bazooka",
	display_name = "Bazooka",
	damage = 10.0,
	fire_rate = 0.8,
	gauge_max = 100.0,
	gauge_cost_per_shot = 20.0, -- 2026-10-07 balance pass — first tried 15 (from 25), but that + the bigger splash made Lourd "beaucoup trop fort" after testing; settled on 20, splash reverted to its pre-pass size
	is_heavy = true, -- triggers the shooter's own vulnerability window on fire (Story 1.8)
	homing_strength = 1.8,
	-- Charged fire: a 2-shot staggered burst (match_arena.lua's
	-- fire_charged_weapon_shots()).
	charge_fire_duration = 3.0,
	charge_fire_slow_multiplier = 0.3,
	charged_projectile_count = 2,
	charged_stagger = 0.15,
	charged_speed_multiplier = 1.4,
	-- Epic 4 passive reward (Pluie de Scuds strikes) — fire_passive_reward()
	-- in match_arena.lua.
	passive_interval = 3.0,
	passive_description = "2 scuds tombent au hasard dans le camp adverse toutes les 3s, sans rien faire.",
})
