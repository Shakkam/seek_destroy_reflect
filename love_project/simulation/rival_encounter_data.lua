-- Ported from godot_project/simulation/rival_encounter_data.gd — a single
-- encounter within a mini-branch: either one of the two "mook" warm-up
-- fights, or the mini-branch's "real" rival.

local rival_encounter_data = {}

function rival_encounter_data.new(overrides)
	local r = {
		opponent = nil, -- character_data
		is_mook = true,

		-- A mook-slot encounter (mook_1/mook_2 only — the rival/organizer
		-- slot always stays "combat") can be a different challenge instead of
		-- a straight 1v1. "combat" (default) = the existing MatchArena-
		-- equivalent fight, unchanged.
		challenge_type = "combat", -- "combat" | "breakout" | "space_invaders" | "gradius"

		-- Mooks only — a reduced-strength version of the archetype. 1.0 =
		-- same as a normal ship_state.START_HP.
		mook_hp_multiplier = 0.6,

		-- Real rival only — the twist applied for the duration of this
		-- fight. Left unset (nil) for mooks.
		twist = nil, -- twist_data

		-- Real rival only — reward unlocked on victory: a bonus variant
		-- "traced" from this rival, not a copy of their actual weapon. Left
		-- unset for mooks, which grant currency instead.
		unlock_reward = nil, -- weapon_data

		-- Mooks only — Exp/Gold granted on victory.
		reward_currency = 100,
	}
	for key, value in pairs(overrides or {}) do
		r[key] = value
	end
	return r
end

return rival_encounter_data
