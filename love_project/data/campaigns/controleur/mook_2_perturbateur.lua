local rival_encounter_data = require("simulation.rival_encounter_data")
local perturbateur = require("data.characters.perturbateur")

return rival_encounter_data.new({ opponent = perturbateur, is_mook = true, mook_hp_multiplier = 0.6, reward_currency = 100 })
