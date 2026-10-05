local rival_encounter_data = require("simulation.rival_encounter_data")
local mitrailleur = require("data.characters.mitrailleur")
local multi_ball = require("data.twists.multi_ball")
local machine_gun = require("data.weapons.machine_gun")

-- 2026-09-24 (Camil) — see vif/rival_mitrailleur.lua's own doc comment:
-- rewards Mitrailleur's own weapon instead of Spreader's own (the mirror
-- rule's original self-referential result).
return rival_encounter_data.new({ opponent = mitrailleur, is_mook = false, twist = multi_ball, unlock_reward = machine_gun })
