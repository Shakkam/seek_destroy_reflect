local character_data = require("simulation.character_data")
local laser = require("data.weapons.laser")

-- Ported from godot_project/data/characters/zoneur.tres. Fifth character
-- ported (Phase 4) — introduces the beam weapon: not a projectile at all,
-- a self-contained timed hitscan ray that follows its shooter and ticks
-- damage while the opponent sits inside its range/thickness.
return character_data.new({
	id = "zoneur",
	display_name = "Zoneur",
	archetype = "Zoneur/Precision",
	kit = { laser },
	complexity = "intermediate",
})
