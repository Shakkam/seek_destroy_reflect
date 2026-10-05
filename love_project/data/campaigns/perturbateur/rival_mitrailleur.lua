local rival_encounter_data = require("simulation.rival_encounter_data")
local mitrailleur = require("data.characters.mitrailleur")
local invisible_opponent = require("data.twists.invisible_opponent")
local machine_gun = require("data.weapons.machine_gun")

-- 2026-09-24 (Camil) — see vif/rival_mitrailleur.lua's own doc comment:
-- rewards Mitrailleur's own weapon instead of Perturbateur's own (the
-- mirror rule's original self-referential result).
return rival_encounter_data.new({ opponent = mitrailleur, is_mook = false, twist = invisible_opponent, unlock_reward = machine_gun })
