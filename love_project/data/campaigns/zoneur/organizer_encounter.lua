local rival_encounter_data = require("simulation.rival_encounter_data")
local controleur = require("data.characters.controleur")
local energy_orb_boss = require("data.twists.energy_orb_boss")

return rival_encounter_data.new({ opponent = controleur, is_mook = false, twist = energy_orb_boss })
