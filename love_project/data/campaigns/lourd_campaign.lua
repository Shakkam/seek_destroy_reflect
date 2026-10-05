local campaign_data = require("simulation.campaign_data")
local lourd = require("data.characters.lourd")
local branch_vif = require("data.campaigns.lourd.branch_vif")
local branch_zoneur = require("data.campaigns.lourd.branch_zoneur")
local branch_perturbateur = require("data.campaigns.lourd.branch_perturbateur")
local branch_missiles = require("data.campaigns.lourd.branch_missiles")
local branch_controleur = require("data.campaigns.lourd.branch_controleur")
local branch_mitrailleur = require("data.campaigns.lourd.branch_mitrailleur")
local branch_mini = require("data.campaigns.lourd.branch_mini")
local organizer_encounter = require("data.campaigns.lourd.organizer_encounter")

-- 2026-09-22 (Camil: "il faudrait reporter la campagne de mitrailleur sur
-- tous les autres persos") — see vif_campaign.lua's own doc comment for
-- the full rule ("vs_mitrailleur" mirrors Mitrailleur's own "vs_lourd"
-- branch). Organizer fight untouched.
return campaign_data.new({
	character = lourd,
	mini_branches = { branch_vif, branch_zoneur, branch_perturbateur, branch_missiles, branch_controleur, branch_mitrailleur, branch_mini },
	required_branch_count = 3,
	organizer_encounter = organizer_encounter,
})
