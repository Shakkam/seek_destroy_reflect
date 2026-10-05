local campaign_data = require("simulation.campaign_data")
local perturbateur = require("data.characters.perturbateur")
local branch_vif = require("data.campaigns.perturbateur.branch_vif")
local branch_zoneur = require("data.campaigns.perturbateur.branch_zoneur")
local branch_mitrailleur = require("data.campaigns.perturbateur.branch_mitrailleur")
local branch_missiles = require("data.campaigns.perturbateur.branch_missiles")
local branch_controleur = require("data.campaigns.perturbateur.branch_controleur")
local branch_lourd = require("data.campaigns.perturbateur.branch_lourd")
local branch_mini = require("data.campaigns.perturbateur.branch_mini")
local organizer_encounter = require("data.campaigns.perturbateur.organizer_encounter")

-- 2026-09-22 (Camil: "il faudrait reporter la campagne de mitrailleur sur
-- tous les autres persos") — see vif_campaign.lua's own doc comment for
-- the full rule ("vs_mitrailleur" mirrors Mitrailleur's own
-- "vs_perturbateur" branch). Organizer fight untouched.
return campaign_data.new({
	character = perturbateur,
	mini_branches = { branch_vif, branch_zoneur, branch_mitrailleur, branch_missiles, branch_controleur, branch_lourd, branch_mini },
	required_branch_count = 3,
	organizer_encounter = organizer_encounter,
})
