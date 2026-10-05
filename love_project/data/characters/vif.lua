local character_data = require("simulation.character_data")
local vortex = require("data.weapons.vortex")

-- Ported from godot_project/data/characters/vif.tres. Eighth and final
-- roster character (Phase 4) — special_rule is "none" (an earlier
-- "dash_lift" rework was tried 2026-08-09 and reverted 2026-08-13 in
-- favor of the Tourbillon's sine trajectory + fire-recoil speed kick
-- instead; Vif plays on the shared hold-to-charge lift like most of the
-- roster). Introduces is_sine: a straight-line net trajectory with a
-- lateral wave riding on top.
return character_data.new({
	id = "vif",
	display_name = "Vif",
	archetype = "Vif",
	kit = { vortex },
	complexity = "intermediate",
	special_rule = "none",
})
