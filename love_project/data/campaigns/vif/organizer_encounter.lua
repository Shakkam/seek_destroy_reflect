local rival_encounter_data = require("simulation.rival_encounter_data")
local perturbateur = require("data.characters.perturbateur")
local energy_orb_boss = require("data.twists.energy_orb_boss")

-- Ported from godot_project/data/campaigns/vif/organizer_encounter.tres.
-- Only `opponent`/`twist` are meaningful here — see campaign_data.lua's
-- own field comment.
return rival_encounter_data.new({
	opponent = perturbateur,
	is_mook = false,
	twist = energy_orb_boss,
})
