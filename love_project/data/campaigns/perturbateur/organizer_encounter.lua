local rival_encounter_data = require("simulation.rival_encounter_data")
local mitrailleur = require("data.characters.mitrailleur")
local energy_orb_boss = require("data.twists.energy_orb_boss")

return rival_encounter_data.new({ opponent = mitrailleur, is_mook = false, twist = energy_orb_boss })
