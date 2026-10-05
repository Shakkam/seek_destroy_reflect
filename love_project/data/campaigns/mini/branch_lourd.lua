local mini_branch_data = require("simulation.mini_branch_data")
local mook_1 = require("data.campaigns.mini.mook_1_lourd")
local mook_2 = require("data.campaigns.mini.mook_2_lourd")
local rival = require("data.campaigns.mini.rival_lourd")

return mini_branch_data.new({ id = "vs_lourd", display_name = "Contre Lourd", mook_1 = mook_1, mook_2 = mook_2, rival = rival })
