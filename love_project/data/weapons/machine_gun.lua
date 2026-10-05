local weapon_data = require("simulation.weapon_data")

-- Ported from godot_project/data/weapons/machine_gun.tres.
return weapon_data.new({
	id = "machine_gun",
	display_name = "Mitraillette",
	damage = 2.0,
	fire_rate = 9.0,
	-- 2026-09-03 (Camil: "on tirait souvent dans le vide. Je pense qu'on peut
	-- accelerer legerement (+15%) la vitesse des missiles") — own override,
	-- not the shared 620 default. 620 * 1.15 = 713.
	projectile_speed = 713.0,
	gauge_max = 100.0,
	gauge_cost_per_shot = 4.0,
	is_heavy = false,
	heat_max = 6.0,
	heat_per_shot = 1.0,
	heat_cooldown_rate = 6.0,
	-- Charged fire: a double-fire buff on release (the next N normal shots
	-- fire doubled, see match_arena.lua's own double_fire_shots_remaining).
	charge_fire_duration = 3.0,
	charge_fire_slow_multiplier = 0.3,
	charged_double_fire_shots = 10,
	-- 2026-10-05 ("tout plus gros" pass, Camil: "il faut aussi augmenter
	-- l'espacement de x1.5 sinon ils sont 'colles'") — bullets got x1.5
	-- bigger (BULLET_VISUALS) but this fixed parallel gap didn't, so the
	-- two parallel streams started visually overlapping.
	charged_double_fire_offset = 10.0 * 1.5,
	-- Epic 4 passive reward.
	passive_interval = 3.0,
	passive_description = "Une salve de 4 tirs de mitraillette part automatiquement toutes les 3s.",
})
