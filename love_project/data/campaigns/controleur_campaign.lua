local campaign_data = require("simulation.campaign_data")
local controleur = require("data.characters.controleur")
local branch_vif = require("data.campaigns.controleur.branch_vif")
local branch_zoneur = require("data.campaigns.controleur.branch_zoneur")
local branch_perturbateur = require("data.campaigns.controleur.branch_perturbateur")
local branch_missiles = require("data.campaigns.controleur.branch_missiles")
local branch_mitrailleur = require("data.campaigns.controleur.branch_mitrailleur")
local branch_lourd = require("data.campaigns.controleur.branch_lourd")
local branch_mini = require("data.campaigns.controleur.branch_mini")
local organizer_encounter = require("data.campaigns.controleur.organizer_encounter")

-- 2026-09-22 (Camil: "il faudrait reporter la campagne de mitrailleur sur
-- tous les autres persos") — see vif_campaign.lua's own doc comment for
-- the full rule ("vs_mitrailleur" mirrors Mitrailleur's own
-- "vs_controleur" branch). Organizer fight untouched.
return campaign_data.new({
	character = controleur,
	mini_branches = { branch_vif, branch_zoneur, branch_perturbateur, branch_missiles, branch_mitrailleur, branch_lourd, branch_mini },
	required_branch_count = 3,
	organizer_encounter = organizer_encounter,
})
