local rival_encounter_data = require("simulation.rival_encounter_data")
local missiles = require("data.characters.missiles")

return rival_encounter_data.new({
	opponent = missiles,
	is_mook = true,
	mook_hp_multiplier = 0.6,
	reward_currency = 100,
	challenge_type = "breakout",
})
