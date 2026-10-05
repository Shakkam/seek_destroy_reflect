local campaign_data = require("simulation.campaign_data")
local mitrailleur = require("data.characters.mitrailleur")
local branch_vif = require("data.campaigns.mitrailleur.branch_vif")
local branch_zoneur = require("data.campaigns.mitrailleur.branch_zoneur")
local branch_perturbateur = require("data.campaigns.mitrailleur.branch_perturbateur")
local branch_missiles = require("data.campaigns.mitrailleur.branch_missiles")
local branch_controleur = require("data.campaigns.mitrailleur.branch_controleur")
local branch_lourd = require("data.campaigns.mitrailleur.branch_lourd")
local branch_mini = require("data.campaigns.mitrailleur.branch_mini")
local organizer_encounter = require("data.campaigns.mitrailleur.organizer_encounter")

return campaign_data.new({
	character = mitrailleur,
	mini_branches = { branch_vif, branch_zoneur, branch_perturbateur, branch_missiles, branch_controleur, branch_lourd, branch_mini },
	required_branch_count = 3,
	organizer_encounter = organizer_encounter,
})
