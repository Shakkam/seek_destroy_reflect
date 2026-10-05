local rival_encounter_data = require("simulation.rival_encounter_data")
local lourd = require("data.characters.lourd")
local drifting_neutral_zone = require("data.twists.drifting_neutral_zone")
local bazooka = require("data.weapons.bazooka")

return rival_encounter_data.new({ opponent = lourd, is_mook = false, twist = drifting_neutral_zone, unlock_reward = bazooka })
