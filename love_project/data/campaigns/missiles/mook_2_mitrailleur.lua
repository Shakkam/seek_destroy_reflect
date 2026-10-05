local rival_encounter_data = require("simulation.rival_encounter_data")
local mitrailleur = require("data.characters.mitrailleur")

return rival_encounter_data.new({
	opponent = mitrailleur,
	is_mook = true,
	mook_hp_multiplier = 0.6,
	reward_currency = 100,
	challenge_type = "space_invaders",
})
