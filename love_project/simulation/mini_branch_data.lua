-- Ported from godot_project/simulation/mini_branch_data.gd — one of a
-- character's up to 7 mini-branches: a 3-fight arc (2 mooks -> 1 "real"
-- rival) targeting a specific roster archetype. Order within one branch is
-- fixed: mook_1 -> mook_2 -> rival.

local mini_branch_data = {}

function mini_branch_data.new(overrides)
	local b = {
		id = "",
		display_name = "", -- the target archetype's name, e.g. "Contre Lourd"

		-- Empty = available from the very start ("depart"). Non-empty =
		-- locked until AT LEAST ONE of these branch ids is completed (never
		-- ALL of them — the player only ever follows a single path down
		-- through any given fork; two branches converging on the same next
		-- node is an "either path unlocks it" join, not an "and" gate).
		prerequisite_ids = {},

		mook_1 = nil, -- rival_encounter_data
		mook_2 = nil, -- rival_encounter_data
		rival = nil, -- rival_encounter_data

		-- Preview art for the campaign map — optional, unset until the LÖVE
		-- integration layer exists.
		preview_texture = nil,
	}
	for key, value in pairs(overrides or {}) do
		b[key] = value
	end
	return b
end

return mini_branch_data
