local character_data = require("simulation.character_data")
local mini_shot = require("data.weapons.mini_shot")

-- Ported from godot_project/data/characters/mini.tres ("Spreader"). The
-- second character ported (Phase 4) — deliberately different from
-- Mitrailleur (a multi-projectile fan burst instead of a full-auto single
-- shot) to prove the weapon pipeline generalizes, not just mirror-match a
-- single kit against itself.
return character_data.new({
	id = "mini",
	display_name = "Spreader",
	archetype = "Glass cannon Spreader",
	kit = { mini_shot },
	complexity = "advanced",
	dash_description = "Envoie 4 mini-clones rapides dans les 4 diagonales pendant 1/4 de seconde.",
})
