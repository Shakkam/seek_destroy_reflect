local rival_encounter_data = require("simulation.rival_encounter_data")
local zoneur = require("data.characters.zoneur")

return rival_encounter_data.new({ opponent = zoneur, is_mook = true, mook_hp_multiplier = 0.6, reward_currency = 100 })
