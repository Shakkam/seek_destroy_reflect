extends Node2D

## One-off scene-boot verification for the 2026-08-16 AI rework (Camil:
## "l'IA n'utilise pas les ultra => il faut qu'elle le fasse. L'IA n'est
## pas tres maline. Il faudrait qu'elle cherche vraiment a renvoyer la
## balle au maximum, c'est sa priorite. Deuxieme priorite: esquiver les
## tirs. 3eme prio: faire des degats. Moins elle a de PV, plus elle va
## essayer de securiser: ses prios vont devenir: eviter les tirs, et taper
## l'adversaire => elle sera moins regardante sur le fait de renvoyer la
## balle."). Confirms: (1) an AI-controlled ship actually triggers its
## Ultra once the meter is full, (2)/(3)/(4) ProjectileNode-based dodge
## detection reacts only to a threat that's both close AND Y-aligned, (5)
## the ball-return-vs-aggression Y-target blend actually flips from
## chasing the ball (full HP) to tracking the opponent (near death), (6)
## fire tolerance widens the same way. Run with:
##   Godot --headless --path godot_project res://tests/ai_behavior_check.tscn --quit-after 400

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame

	arena.ship_2.ai_controlled = true
	arena._unfreeze_round() # skip the ready gate — irrelevant to what's under test here

	# --- (1) AI uses its Ultra once ready ---
	while not arena.ship_2.weapon_state.ultra_ready():
		arena.ship_2.add_ultra_pip()
	await get_tree().physics_frame
	await get_tree().physics_frame # matches ultra_abilities_check.gd's press-then-2-frames pattern — one tick alone isn't always reliably observed
	# _process_ultra_trigger() only reaches with_ultra_consumed() through the
	# exact same guarded branch that then emits ultra_triggered, so a
	# consumed meter IS proof the AI actually triggered its Ultra (no need
	# for a separate signal listener — GDScript lambdas capture outer
	# locals by VALUE, not by reference, so a `func(): flag = true` here
	# would silently mutate its own copy and never prove anything anyway).
	var ultra_fired: bool = not arena.ship_2.weapon_state.ultra_ready()
	print("PASS: an AI-controlled ship triggers its Ultra once the meter is full (consumed on trigger)" if ultra_fired else "FAIL: the AI never triggered its Ultra")

	# --- (2)/(3)/(4) Dodge detection (priority 2) — defensiveness passed
	# directly as an argument, independent of the ship's real HP. ---
	var threat := ProjectileNode.new()
	threat.target = arena.ship_2
	threat.position = arena.ship_2.position + Vector2(40.0, 0.0) # close, dead-level in Y -> should trigger a dodge
	arena.add_child(threat)
	var dodge_when_lined_up: float = arena.ship_2._ai_dodge_direction(0.0)
	print(("PASS: a close, Y-aligned threat produces a real dodge direction (%.0f)" % dodge_when_lined_up) if dodge_when_lined_up != 0.0 else "FAIL: no dodge direction against a lined-up close threat")

	threat.position = arena.ship_2.position + Vector2(40.0, 300.0) # close-ish but nowhere near my Y
	var dodge_when_off_axis: float = arena.ship_2._ai_dodge_direction(0.0)
	print("PASS: a threat that's not Y-aligned produces no dodge" if dodge_when_off_axis == 0.0 else ("FAIL: dodged a threat that wasn't lined up (%.0f)" % dodge_when_off_axis))

	threat.position = arena.ship_2.position + Vector2(2000.0, 0.0) # aligned but far out of detection range
	var dodge_when_far: float = arena.ship_2._ai_dodge_direction(0.0)
	print("PASS: a far-away threat produces no dodge" if dodge_when_far == 0.0 else ("FAIL: dodged a threat that was too far (%.0f)" % dodge_when_far))
	threat.queue_free()

	# --- (5) Ball-return priority (1) vs. aggression (3), at FULL HP ---
	# Opponent parked near the top, ball parked near the bottom and
	# "on ship_2's side" (urgent) — a healthy AI should chase the ball
	# (move down, positive Y), not the opponent.
	var bounds := Rect2(arena.arena_origin, arena.arena_size)
	arena.ship_1.position = Vector2(arena.ship_2.position.x - 200.0, bounds.position.y + 60.0)
	arena.ball.position = Vector2(arena.ship_2.position.x - 100.0, bounds.position.y + bounds.size.y - 60.0)
	arena.ball.state.velocity = Vector2(-50.0, 0.0)
	arena.ship_2.position = Vector2(arena.ship_2.position.x, bounds.position.y + bounds.size.y * 0.5)
	var healthy_dir: Vector2 = arena.ship_2._ai_read_input()
	print(("PASS: at full HP the AI moves toward the ball, not the opponent (dir.y=%.2f)" % healthy_dir.y) if healthy_dir.y > 0.0 else ("FAIL: full-HP AI didn't chase the ball (dir.y=%.2f)" % healthy_dir.y))

	# --- (6) Fire tolerance (priority 3), at FULL HP — 130px offset sits
	# past the healthy ~90px tolerance, within the near-death ~170px one. ---
	arena.ship_1.position.y = arena.ship_2.position.y + 130.0
	var fires_healthy: bool = arena.ship_2._ai_should_fire()
	print("PASS: at full HP the AI holds fire past its tighter tolerance" if not fires_healthy else "FAIL: full-HP AI fired at a 130px offset")

	# --- Now cut HP down to near-death and re-check both (5) and (6). ---
	arena.ship_2.state = arena.ship_2.state.damaged(95.0) # ~5 HP left
	arena.ship_1.position = Vector2(arena.ship_2.position.x - 200.0, bounds.position.y + 60.0)
	var critical_dir: Vector2 = arena.ship_2._ai_read_input()
	print(("PASS: near death the AI moves toward the opponent instead (dir.y=%.2f)" % critical_dir.y) if critical_dir.y < 0.0 else ("FAIL: critical-HP AI still chased the ball (dir.y=%.2f)" % critical_dir.y))

	arena.ship_1.position.y = arena.ship_2.position.y + 130.0
	var fires_critical: bool = arena.ship_2._ai_should_fire()
	print("PASS: near death the AI fires at the same offset (wider tolerance)" if fires_critical else "FAIL: critical-HP AI still held fire at a 130px offset")

	var all_ok := ultra_fired \
		and dodge_when_lined_up != 0.0 and dodge_when_off_axis == 0.0 and dodge_when_far == 0.0 \
		and healthy_dir.y > 0.0 and not fires_healthy \
		and critical_dir.y < 0.0 and fires_critical
	get_tree().quit(0 if all_ok else 1)
