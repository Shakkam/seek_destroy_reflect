local campaign_data = require("simulation.campaign_data")
local zoneur = require("data.characters.zoneur")
local branch_vif = require("data.campaigns.zoneur.branch_vif")
local branch_mitrailleur = require("data.campaigns.zoneur.branch_mitrailleur")
local branch_perturbateur = require("data.campaigns.zoneur.branch_perturbateur")
local branch_missiles = require("data.campaigns.zoneur.branch_missiles")
local branch_controleur = require("data.campaigns.zoneur.branch_controleur")
local branch_lourd = require("data.campaigns.zoneur.branch_lourd")
local branch_mini = require("data.campaigns.zoneur.branch_mini")
local organizer_encounter = require("data.campaigns.zoneur.organizer_encounter")

-- 2026-09-22 (Camil: "il faudrait reporter la campagne de mitrailleur sur
-- tous les autres persos") — see vif_campaign.lua's own doc comment for
-- the full rule (Mitrailleur's own campaign is the reference template;
-- "vs_mitrailleur" mirrors Mitrailleur's own "vs_zoneur" branch instead).
-- Organizer fight untouched.
return campaign_data.new({
	character = zoneur,
	mini_branches = { branch_vif, branch_mitrailleur, branch_perturbateur, branch_missiles, branch_controleur, branch_lourd, branch_mini },
	required_branch_count = 3,
	organizer_encounter = organizer_encounter,
})
