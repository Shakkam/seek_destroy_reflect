local mini_branch_data = require("simulation.mini_branch_data")
local mook_1 = require("data.campaigns.perturbateur.mook_1_mini")
local mook_2 = require("data.campaigns.perturbateur.mook_2_mini")
local rival = require("data.campaigns.perturbateur.rival_mini")

return mini_branch_data.new({ id = "vs_mini", display_name = "Contre Spreader", mook_1 = mook_1, mook_2 = mook_2, rival = rival })
