local mini_branch_data = require("simulation.mini_branch_data")
local mook_1 = require("data.campaigns.perturbateur.mook_1_zoneur")
local mook_2 = require("data.campaigns.perturbateur.mook_2_zoneur")
local rival = require("data.campaigns.perturbateur.rival_zoneur")

return mini_branch_data.new({ id = "vs_zoneur", display_name = "Contre Zoneur", mook_1 = mook_1, mook_2 = mook_2, rival = rival })
