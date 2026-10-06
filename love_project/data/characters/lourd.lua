local character_data = require("simulation.character_data")
local bazooka = require("data.weapons.bazooka")

-- Ported from godot_project/data/characters/lourd.tres. Third character
-- ported (Phase 4) — introduces a homing heavy weapon (vulnerability
-- window on fire) AND the "heavy_push" special_rule (a fully-charged lift
-- return knocks the opponent back), which is what pulled the lift/aim/
-- charge mechanic itself into the LÖVE port for the first time.
return character_data.new({
	id = "lourd",
	display_name = "Lourd",
	archetype = "Lourd",
	kit = { bazooka },
	complexity = "beginner",
	special_rule = "heavy_push",
	dash_description = "Fonce dans sa direction, verrouillee pendant 1/2 seconde (glisse incontrolable, comme sur de la glace).",
})
