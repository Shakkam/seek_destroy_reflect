-- Ported from godot_project/simulation/campaign_data.gd — one character's
-- full solo campaign: up to 7 possible mini-branches, `required_branch_count`
-- of which must be completed before the final node unlocks.

local campaign_data = {}

function campaign_data.new(overrides)
	local c = {
		character = nil, -- character_data
		mini_branches = {}, -- of mini_branch_data — up to 7
		required_branch_count = 3, -- 3-4 per the brainstorm ("force la rejouabilite")

		-- The organizer's final-boss encounter for this character's
		-- campaign. Only `twist` is meaningful here — it must be an
		-- "energy_orb_pickup"-type twist_data.
		organizer_encounter = nil, -- rival_encounter_data
	}
	for key, value in pairs(overrides or {}) do
		c[key] = value
	end
	return c
end

return campaign_data
