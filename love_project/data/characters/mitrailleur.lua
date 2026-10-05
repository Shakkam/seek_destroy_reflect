local character_data = require("simulation.character_data")
local machine_gun = require("data.weapons.machine_gun")

-- Ported from godot_project/data/characters/mitrailleur.tres. Chosen as
-- Phase 3's "one simple character, ported end to end" per the port spec —
-- a single weapon, full_auto, no special movement rule.
return character_data.new({
	id = "mitrailleur",
	display_name = "Mitrailleur",
	archetype = "Mitrailleur",
	kit = { machine_gun },
	complexity = "beginner",
	full_auto = true,
})
