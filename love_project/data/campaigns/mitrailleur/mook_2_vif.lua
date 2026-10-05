local rival_encounter_data = require("simulation.rival_encounter_data")
local vif = require("data.characters.vif")

return rival_encounter_data.new({ opponent = vif, is_mook = true, mook_hp_multiplier = 0.6, reward_currency = 100 })
