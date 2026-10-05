local mini_branch_data = require("simulation.mini_branch_data")
local mook_1 = require("data.campaigns.mini.mook_1_vif")
local mook_2 = require("data.campaigns.mini.mook_2_vif")
local rival = require("data.campaigns.mini.rival_vif")

return mini_branch_data.new({ id = "vs_vif", display_name = "Contre Vif", mook_1 = mook_1, mook_2 = mook_2, rival = rival })
