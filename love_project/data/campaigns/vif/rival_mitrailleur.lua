local rival_encounter_data = require("simulation.rival_encounter_data")
local mitrailleur = require("data.characters.mitrailleur")
local hazard_zones = require("data.twists.hazard_zones")
local machine_gun = require("data.weapons.machine_gun")

-- 2026-09-24 (Camil) — the mirror rule (see vif_campaign.lua's own doc
-- comment) originally reused vif's OWN weapon here (mitrailleur's real
-- "vs_vif" branch rewards vortex for beating Vif) — narratively backwards
-- for Vif's own campaign ("beat Mitrailleur, unlock your own weapon").
-- Rewards Mitrailleur's own weapon instead.
return rival_encounter_data.new({ opponent = mitrailleur, is_mook = false, twist = hazard_zones, unlock_reward = machine_gun })
