-- Ported from godot_project/simulation/character_data.gd — data-driven
-- character definition. Adding or tuning a character is authoring a data
-- table (see data/characters/*.lua once that folder is ported), never a
-- code change.

local character_data = {}

function character_data.new(overrides)
	local c = {
		id = "",
		display_name = "",
		archetype = "", -- e.g. "Lourd", "Controleur", "Mitrailleur"...
		kit = {}, -- ordered weapon_data list, index 1 = default selected weapon
		complexity = "intermediate", -- "beginner" | "intermediate" | "advanced"

		-- An opt-in per-character movement/lift rule that replaces the shared
		-- hold-to-charge lift. "none" = the original shared mechanic,
		-- untouched. "dash_lift" (Vif): can never charge a lift at all, but
		-- the Lift button instead triggers a short directional dash.
		-- "heavy_push" (Lourd): a fully-charged lift return knocks the
		-- opponent back on contact. Add new values here (and a matching
		-- branch on the LÖVE-side ship logic) as more characters get their
		-- own rule — never hardcode a rule to a character id there.
		special_rule = "none", -- "none" | "dash_lift" | "heavy_push"

		-- Only Mitrailleur fires repeatedly while held; everyone else needs a
		-- fresh press per shot, even during a charge-capable weapon's
		-- pre-charge grace window.
		full_auto = false,

		-- One short line of French describing this character's own Dash
		-- effect (match_arena.lua's dash_helpers.effects[id]) — shown in the
		-- in-match pause menu's "Commandes" screen, since the shared Dash
		-- button does something completely different per character.
		dash_description = "",
	}
	for key, value in pairs(overrides or {}) do
		c[key] = value
	end
	return c
end

return character_data
