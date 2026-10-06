local character_data = require("simulation.character_data")
local homing_missile = require("data.weapons.homing_missile")

-- Ported from godot_project/data/characters/missiles.tres. Seventh
-- character ported (Phase 4) — the first with zero new engine work: its
-- homing (vertical-only, non-full-turn) and fan burst already exist
-- (bazooka, Spreader), so this is purely a data port.
return character_data.new({
	id = "missiles",
	display_name = "Traqueur",
	archetype = "Missiles teleguides",
	kit = { homing_missile },
	complexity = "advanced",
	dash_description = "Oriente la balle vers lui (sans changer sa vitesse) tant qu'elle approche de son cote.",
})
