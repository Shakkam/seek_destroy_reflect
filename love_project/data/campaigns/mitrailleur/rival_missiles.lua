local rival_encounter_data = require("simulation.rival_encounter_data")
local missiles = require("data.characters.missiles")
local multi_ball = require("data.twists.multi_ball")
local homing_missile = require("data.weapons.homing_missile")

return rival_encounter_data.new({ opponent = missiles, is_mook = false, twist = multi_ball, unlock_reward = homing_missile })
