local character_data = require("simulation.character_data")
local turret = require("data.weapons.turret")

-- Ported from godot_project/data/characters/controleur.tres. Sixth
-- character ported (Phase 4) — introduces the "turret" effect_type:
-- firing doesn't launch a projectile at all, it PLACES a stationary,
-- destructible, autonomously-firing entity at the shooter's current
-- position instead.
return character_data.new({
	id = "controleur",
	display_name = "Controleur",
	archetype = "Controleur",
	kit = { turret },
	complexity = "intermediate",
	dash_description = "Invoque un clone fantome immobile a sa position actuelle, qui peut renvoyer la balle une fois.",
})
