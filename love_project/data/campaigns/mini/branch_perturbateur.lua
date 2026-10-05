local mini_branch_data = require("simulation.mini_branch_data")
local mook_1 = require("data.campaigns.mini.mook_1_perturbateur")
local mook_2 = require("data.campaigns.mini.mook_2_perturbateur")
local rival = require("data.campaigns.mini.rival_perturbateur")

return mini_branch_data.new({
	id = "vs_perturbateur",
	display_name = "Contre Perturbateur",
	prerequisite_ids = { "vs_vif" },
	mook_1 = mook_1,
	mook_2 = mook_2,
	rival = rival,
})
