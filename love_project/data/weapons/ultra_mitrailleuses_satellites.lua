local weapon_data = require("simulation.weapon_data")

-- Ported from godot_project/data/weapons/ultra_mitrailleuses_satellites.tres
-- — Mitrailleur's Ultra: two escort turrets (autofire=false, never fire on
-- their own — see spawn_satellite_turrets() in match_arena.lua) that echo
-- his own normal machine_gun shots from offset positions. fire_rate/damage
-- here are unused (kept only for parity with the .tres); turret_hp/
-- turret_lifetime are what actually matter.
return weapon_data.new({
	id = "ultra_mitrailleuses_satellites",
	display_name = "Mitrailleuses Satellites",
	damage = 2.0,
	fire_rate = 7.0,
	effect_type = "turret",
	turret_hp = 15.0,
	turret_lifetime = 12.0,
})
