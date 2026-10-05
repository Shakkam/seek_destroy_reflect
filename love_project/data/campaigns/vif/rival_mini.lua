local rival_encounter_data = require("simulation.rival_encounter_data")
local mini = require("data.characters.mini")
local multi_ball = require("data.twists.multi_ball")
local mini_shot = require("data.weapons.mini_shot")

return rival_encounter_data.new({ opponent = mini, is_mook = false, twist = multi_ball, unlock_reward = mini_shot })
