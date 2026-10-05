local mini_branch_data = require("simulation.mini_branch_data")
local mook_1 = require("data.campaigns.missiles.mook_1_mitrailleur")
local mook_2 = require("data.campaigns.missiles.mook_2_mitrailleur")
local rival = require("data.campaigns.missiles.rival_mitrailleur")

return mini_branch_data.new({ id = "vs_mitrailleur", display_name = "Contre Mitrailleur", mook_1 = mook_1, mook_2 = mook_2, rival = rival })
