local rival_encounter_data = require("simulation.rival_encounter_data")
local mini = require("data.characters.mini")

return rival_encounter_data.new({ opponent = mini, is_mook = true, mook_hp_multiplier = 0.65, reward_currency = 120 })
