local character_data = require("simulation.character_data")
local stun_boomerang = require("data.weapons.stun_boomerang")

-- Ported from godot_project/data/characters/perturbateur.tres. Fourth
-- character ported (Phase 4) — introduces the boomerang motion (a fixed,
-- non-homing outbound banana arc, then a live-homing return leg that can
-- be dodged), the only projectile shape so far that survives its own hit
-- and keeps flying instead of despawning.
return character_data.new({
	id = "perturbateur",
	display_name = "Perturbateur",
	archetype = "Perturbateur",
	kit = { stun_boomerang },
	complexity = "advanced",
})
