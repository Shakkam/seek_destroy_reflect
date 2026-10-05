local mini_branch_data = require("simulation.mini_branch_data")
local mook_1 = require("data.campaigns.vif.mook_1_missiles")
local mook_2 = require("data.campaigns.vif.mook_2_missiles")
local rival = require("data.campaigns.vif.rival_missiles")

return mini_branch_data.new({
	id = "vs_missiles",
	display_name = "Contre Traqueur",
	prerequisite_ids = { "vs_zoneur" },
	mook_1 = mook_1,
	mook_2 = mook_2,
	rival = rival,
})
