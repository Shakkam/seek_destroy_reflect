class_name MatchState
extends RefCounted

## Pure, deterministic match state: round score and win condition.
## Story 1.9 — best-of-3 rounds, 100 HP per round (HP itself lives on ShipState).

var rounds_won: Array[int] # index 0 = side 0 (left), index 1 = side 1 (right)
var match_over: bool
var winner_side: int # -1 if match not over

func _init(p1_rounds: int = 0, p2_rounds: int = 0, is_over: bool = false, winner: int = -1) -> void:
	rounds_won = [p1_rounds, p2_rounds]
	match_over = is_over
	winner_side = winner

func round_won_by(side: int) -> MatchState:
	var new_rounds: Array[int] = rounds_won.duplicate()
	new_rounds[side] += 1
	var is_over: bool = new_rounds[side] >= 2
	return MatchState.new(new_rounds[0], new_rounds[1], is_over, side if is_over else -1)
