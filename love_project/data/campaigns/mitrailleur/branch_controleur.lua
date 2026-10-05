local mini_branch_data = require("simulation.mini_branch_data")
local mook_1 = require("data.campaigns.mitrailleur.mook_1_controleur")
local mook_2 = require("data.campaigns.mitrailleur.mook_2_controleur")
local rival = require("data.campaigns.mitrailleur.rival_controleur")

return mini_branch_data.new({ id = "vs_controleur", display_name = "Contre Controleur", mook_1 = mook_1, mook_2 = mook_2, rival = rival })
