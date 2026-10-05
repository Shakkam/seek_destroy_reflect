local campaign_data = require("simulation.campaign_data")
local vif = require("data.characters.vif")
local branch_mitrailleur = require("data.campaigns.vif.branch_mitrailleur")
local branch_zoneur = require("data.campaigns.vif.branch_zoneur")
local branch_perturbateur = require("data.campaigns.vif.branch_perturbateur")
local branch_missiles = require("data.campaigns.vif.branch_missiles")
local branch_controleur = require("data.campaigns.vif.branch_controleur")
local branch_lourd = require("data.campaigns.vif.branch_lourd")
local branch_mini = require("data.campaigns.vif.branch_mini")
local organizer_encounter = require("data.campaigns.vif.organizer_encounter")

-- 2026-09-22 (Camil: "il faudrait reporter la campagne de mitrailleur sur
-- tous les autres persos. Meme campagne, sauf que les rivaux different")
-- — Mitrailleur's own campaign (7 branches, one per other character) is
-- the reference template; every branch here reuses his exact
-- challenge_type/twist/reward for that same opponent verbatim, EXCEPT
-- "vs_mitrailleur" itself (he has no branch against himself) — that one
-- mirrors Mitrailleur's own "vs_vif" branch instead, opponent swapped to
-- Mitrailleur (Camil's own resolution to that exact ambiguity). The
-- organizer fight is untouched — Camil chose to keep each character's own
-- existing final boss as-is.
return campaign_data.new({
	character = vif,
	mini_branches = { branch_mitrailleur, branch_zoneur, branch_perturbateur, branch_missiles, branch_controleur, branch_lourd, branch_mini },
	required_branch_count = 3,
	organizer_encounter = organizer_encounter,
})
