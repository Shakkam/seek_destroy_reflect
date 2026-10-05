local rival_encounter_data = require("simulation.rival_encounter_data")
local controleur = require("data.characters.controleur")

return rival_encounter_data.new({ opponent = controleur, is_mook = true, mook_hp_multiplier = 0.6, reward_currency = 100 })
