local rival_encounter_data = require("simulation.rival_encounter_data")
local mini = require("data.characters.mini")
local energy_orb_boss = require("data.twists.energy_orb_boss")

return rival_encounter_data.new({ opponent = mini, is_mook = false, twist = energy_orb_boss })
