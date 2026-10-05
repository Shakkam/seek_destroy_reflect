local rival_encounter_data = require("simulation.rival_encounter_data")
local vif = require("data.characters.vif")
local hazard_zones = require("data.twists.hazard_zones")
local vortex = require("data.weapons.vortex")

return rival_encounter_data.new({ opponent = vif, is_mook = false, twist = hazard_zones, unlock_reward = vortex })
