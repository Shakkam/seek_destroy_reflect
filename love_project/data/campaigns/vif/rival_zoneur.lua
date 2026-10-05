local rival_encounter_data = require("simulation.rival_encounter_data")
local zoneur = require("data.characters.zoneur")
local shrinking_arena = require("data.twists.shrinking_arena")
local laser = require("data.weapons.laser")

return rival_encounter_data.new({ opponent = zoneur, is_mook = false, twist = shrinking_arena, unlock_reward = laser })
