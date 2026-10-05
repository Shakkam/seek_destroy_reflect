local campaign_data = require("simulation.campaign_data")
local mini = require("data.characters.mini")
local branch_vif = require("data.campaigns.mini.branch_vif")
local branch_zoneur = require("data.campaigns.mini.branch_zoneur")
local branch_perturbateur = require("data.campaigns.mini.branch_perturbateur")
local branch_missiles = require("data.campaigns.mini.branch_missiles")
local branch_controleur = require("data.campaigns.mini.branch_controleur")
local branch_lourd = require("data.campaigns.mini.branch_lourd")
local branch_mitrailleur = require("data.campaigns.mini.branch_mitrailleur")
local organizer_encounter = require("data.campaigns.mini.organizer_encounter")

-- 2026-09-22 (Camil: "il faudrait reporter la campagne de mitrailleur sur
-- tous les autres persos") — see vif_campaign.lua's own doc comment for
-- the full rule ("vs_mitrailleur" mirrors Mitrailleur's own "vs_mini"
-- branch). Organizer fight untouched.
return campaign_data.new({
	character = mini,
	mini_branches = { branch_vif, branch_zoneur, branch_perturbateur, branch_missiles, branch_controleur, branch_lourd, branch_mitrailleur },
	required_branch_count = 3,
	organizer_encounter = organizer_encounter,
})
