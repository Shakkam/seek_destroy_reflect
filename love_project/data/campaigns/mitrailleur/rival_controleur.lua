local rival_encounter_data = require("simulation.rival_encounter_data")
local controleur = require("data.characters.controleur")
local gauge_floor = require("data.twists.gauge_floor")
local turret = require("data.weapons.turret")

return rival_encounter_data.new({ opponent = controleur, is_mook = false, twist = gauge_floor, unlock_reward = turret })
