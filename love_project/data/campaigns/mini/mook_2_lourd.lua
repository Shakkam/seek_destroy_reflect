local rival_encounter_data = require("simulation.rival_encounter_data")
local lourd = require("data.characters.lourd")

return rival_encounter_data.new({ opponent = lourd, is_mook = true, mook_hp_multiplier = 0.6, reward_currency = 100 })
