extends Node2D

## Balance-testing batch harness (2026-08-17, Camil: "gros probleme
## d'equilibrage... lance tout un tas de games en back, avec differents
## personnages, et liste les taux de victoire sur chaque VS"). Runs many
## full best-of-3 matches, BOTH sides AI-controlled, across every unordered
## pair of the 8-character roster, and prints a win-rate table. Never
## previously exercised: ship_1 (normally the human slot) set ai_controlled
## = true here too — nothing in ship_node.gd/match_arena_node.gd hard-codes
## player_index==1 as "must be human", confirmed by reading both files.
##
## Skips the "Pret ? / Ready... / GO!" pacing gate every round (pure UI
## beat, zero gameplay effect — forcing _unfreeze_round() the instant we
## detect !_round_playing is the same shortcut several existing tests use)
## but does NOT skip Ultra intro pauses — those are real match pacing and
## matter for realistic results.
##
## CampaignSave is reset before AND after — this must run on a clean,
## unlock-free baseline, or Camil's own real campaign progress (passive
## rewards) would leak into "character balance" results. Same
## reset-before/after convention as reward_reveal_check.gd.
##
## Run with (foreground, blocks until done). --fixed-fps 60 is required —
## without it Godot throttles physics ticks to a real-time clock even
## headless, and a single match can take 100s+ of real time to simulate
## 2-3 simulated minutes; with it, ticks run as fast as the CPU allows
## (~2s real per match measured on this machine):
##   Godot --headless --path . res://tests/balance_simulation.tscn --quit-after 6000000 --fixed-fps 60
## RUNS_PER_MATCHUP below controls total runtime.

const CHAR_IDS := ["lourd", "controleur", "mitrailleur", "vif", "zoneur", "perturbateur", "missiles", "mini"]
const RUNS_PER_MATCHUP := 45 # 2026-08-17: bumped from 16 — a run's-worth of noise (±12pt std error at n=16) was swamping real signal on the last few tuning passes; ~0.93s/match measured, so 28*45=1260 matches lands around 20 real minutes.
const MAX_TICKS_PER_MATCH := 24000 # safety cap (~800s simulated @ 30fps) — real matches should never need this long; a hit here is logged as a timeout, not a crash

var _matchups: Array[Dictionary] = []

func _ready() -> void:
	CampaignSave.reset_all()

	for i in CHAR_IDS.size():
		for j in range(i + 1, CHAR_IDS.size()):
			_matchups.append({"a": CHAR_IDS[i], "b": CHAR_IDS[j], "wins_a": 0, "wins_b": 0, "timeouts": 0})

	var total_matches := _matchups.size() * RUNS_PER_MATCHUP
	print("=== balance_simulation: %d matchups x %d runs = %d matches ===" % [_matchups.size(), RUNS_PER_MATCHUP, total_matches])

	var match_index := 0
	for m in _matchups:
		for run in RUNS_PER_MATCHUP:
			match_index += 1
			var start_ticks := Time.get_ticks_msec()
			var result := await _play_one_match(m["a"], m["b"])
			var elapsed_s := (Time.get_ticks_msec() - start_ticks) / 1000.0
			if result["timeout"]:
				m["timeouts"] += 1
				print("[%d/%d] %s vs %s run %d: TIMEOUT after %d ticks (%.1fs real)" % [match_index, total_matches, m["a"], m["b"], run + 1, result["ticks"], elapsed_s])
			else:
				if result["winner"] == m["a"]:
					m["wins_a"] += 1
				else:
					m["wins_b"] += 1
				print("[%d/%d] %s vs %s run %d: winner=%s (%d ticks, %.1fs real)" % [match_index, total_matches, m["a"], m["b"], run + 1, result["winner"], result["ticks"], elapsed_s])

	print("\n=== FINAL WIN-RATE TABLE ===")
	for m in _matchups:
		var decided: int = m["wins_a"] + m["wins_b"]
		if decided == 0:
			print("%s vs %s: no decided matches (all timed out)" % [m["a"], m["b"]])
			continue
		var pct_a: float = 100.0 * m["wins_a"] / decided
		var pct_b: float = 100.0 * m["wins_b"] / decided
		var timeout_note := "" if m["timeouts"] == 0 else " [%d timeout(s)]" % m["timeouts"]
		print("%s vs %s: %d-%d  (%s %.0f%% / %s %.0f%%)%s" % [m["a"], m["b"], m["wins_a"], m["wins_b"], m["a"], pct_a, m["b"], pct_b, timeout_note])

	print("\n=== PER-CHARACTER OVERALL WIN RATE ===")
	for cid in CHAR_IDS:
		var wins := 0
		var total := 0
		for m in _matchups:
			if m["a"] == cid or m["b"] == cid:
				var decided: int = m["wins_a"] + m["wins_b"]
				total += decided
				wins += m["wins_a"] if m["a"] == cid else m["wins_b"]
		if total > 0:
			print("%s: %d/%d (%.0f%%)" % [cid, wins, total, 100.0 * wins / total])

	CampaignSave.reset_all()
	get_tree().quit(0)

## Plays one full best-of-3 match, both ships AI-controlled, and returns
## {"winner": character_id, "timeout": bool, "ticks": int}.
func _play_one_match(char_a_id: String, char_b_id: String) -> Dictionary:
	MatchSetup.p1_character = load("res://data/characters/%s.tres" % char_a_id)
	MatchSetup.p2_character = load("res://data/characters/%s.tres" % char_b_id)

	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	arena.ship_1.ai_controlled = true
	arena.ship_2.ai_controlled = true
	if not arena._round_playing:
		arena._unfreeze_round()

	var ticks := 0
	while not arena.match_state.match_over and ticks < MAX_TICKS_PER_MATCH:
		await get_tree().physics_frame
		ticks += 1
		if not arena._round_playing and not arena.match_state.match_over:
			arena._unfreeze_round() # skip the "Pret ?/Ready/GO" pacing gate every round transition — pure UI beat, no gameplay effect

	var result := {"ticks": ticks}
	if arena.match_state.match_over:
		result["timeout"] = false
		result["winner"] = char_a_id if arena.match_state.winner_side == 0 else char_b_id
	else:
		result["timeout"] = true
		result["winner"] = ""

	arena.queue_free()
	await get_tree().process_frame
	return result
