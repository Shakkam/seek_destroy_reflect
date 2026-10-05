local rival_encounter_data = require("simulation.rival_encounter_data")
local perturbateur = require("data.characters.perturbateur")
local invisible_opponent = require("data.twists.invisible_opponent")
local stun_boomerang = require("data.weapons.stun_boomerang")

return rival_encounter_data.new({ opponent = perturbateur, is_mook = false, twist = invisible_opponent, unlock_reward = stun_boomerang })
