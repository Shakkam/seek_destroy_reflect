extends Node2D

## One-off scene-boot verification for the 2026-08-06 bug fix ("à la fin du
## round 1 les tourelles restent, elles devraient disparaître"). Run with:
##   Godot --headless --path godot_project res://tests/round_end_check.tscn --quit-after 10
## Unlike smoke_test.gd (a custom SceneTree run via -s, which does NOT
## initialize project autoloads — confirmed 2026-08-07), this runs as a
## normal scene so MatchSetup (referenced by match_arena_node.gd) is
## available. Prints PASS/FAIL and exits non-zero on failure.

func _ready() -> void:
	var arena_scene := load("res://scenes/MatchArena.tscn") as PackedScene
	var arena := arena_scene.instantiate() as MatchArenaNode
	add_child(arena)
	await get_tree().process_frame # let MatchArenaNode._ready() (onready ship/ball wiring) actually run

	var turret_data: WeaponData = load("res://data/weapons/turret.tres")
	var turret := TurretNode.new()
	turret.weapon = turret_data
	turret.owner_side = 0
	turret.target = arena.ship_2
	turret.hp = turret_data.turret_hp
	arena.add_child(turret)
	await get_tree().process_frame

	var alive_before := not turret.is_queued_for_deletion()
	print("PASS: turret alive before cleanup" if alive_before else "FAIL: turret already queued before cleanup")

	arena._clear_round_entities()
	var freed := turret.is_queued_for_deletion()
	print("PASS: round-end cleanup frees turrets" if freed else "FAIL: turret survived _clear_round_entities()")

	get_tree().quit(0 if (alive_before and freed) else 1)
