-- Ported from godot_project/simulation/match_state.gd — pure, deterministic
-- match state: round score and win condition. Story 1.9 — best-of-3
-- rounds, 100 HP per round (HP itself lives on ship_state.lua).
--
-- rounds_won is kept as a 1-indexed Lua array internally ({side0, side1}),
-- but every public function takes/returns a 0-based `side` (0 = left,
-- 1 = right) to match the Godot source and the rest of this port —
-- rounds_for() is the one seam between the two conventions.

local match_state = {}

function match_state.new(p1_rounds, p2_rounds, is_over, winner)
	return {
		rounds_won = { p1_rounds or 0, p2_rounds or 0 },
		match_over = is_over or false,
		winner_side = winner == nil and -1 or winner,
	}
end

function match_state.rounds_for(state, side)
	return state.rounds_won[side + 1]
end

function match_state.round_won_by(state, side)
	local new_rounds = { state.rounds_won[1], state.rounds_won[2] }
	new_rounds[side + 1] = new_rounds[side + 1] + 1
	local is_over = new_rounds[side + 1] >= 2
	return match_state.new(new_rounds[1], new_rounds[2], is_over, is_over and side or -1)
end

return match_state
