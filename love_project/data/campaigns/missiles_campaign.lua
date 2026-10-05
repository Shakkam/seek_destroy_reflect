local campaign_data = require("simulation.campaign_data")
local missiles = require("data.characters.missiles")
local branch_vif = require("data.campaigns.missiles.branch_vif")
local branch_zoneur = require("data.campaigns.missiles.branch_zoneur")
local branch_perturbateur = require("data.campaigns.missiles.branch_perturbateur")
local branch_mitrailleur = require("data.campaigns.missiles.branch_mitrailleur")
local branch_controleur = require("data.campaigns.missiles.branch_controleur")
local branch_lourd = require("data.campaigns.missiles.branch_lourd")
local branch_mini = require("data.campaigns.missiles.branch_mini")
local organizer_encounter = require("data.campaigns.missiles.organizer_encounter")

-- 2026-09-22 (Camil: "il faudrait reporter la campagne de mitrailleur sur
-- tous les autres persos") — see vif_campaign.lua's own doc comment for
-- the full rule ("vs_mitrailleur" mirrors Mitrailleur's own
-- "vs_missiles" branch). Organizer fight untouched.
return campaign_data.new({
	character = missiles,
	mini_branches = { branch_vif, branch_zoneur, branch_perturbateur, branch_mitrailleur, branch_controleur, branch_lourd, branch_mini },
	required_branch_count = 3,
	organizer_encounter = organizer_encounter,
})
