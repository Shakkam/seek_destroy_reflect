class_name EnergyOrbNode
extends Node2D

## Epic 4, Story 4.8 — the organizer's signature "energy_orb_pickup" twist:
## a neutral pickup that grants a flat percentage of gauge to whichever
## ship touches it. Reuses ShipNode.fill_selected_gauge() /
## WeaponSystemState.with_gauge_added() — no new gauge system, per Camil's
## simplification ("on pourrait faire poper... des billes d'énergie").

var gauge_bonus_percent := 20.0
var ships: Array = [] # of ShipNode
var lifetime := 12.0 # despawns if nobody grabs it in time

const PICKUP_RADIUS := 16.0

func _ready() -> void:
	var visual := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 8:
		var angle := TAU * i / 8.0
		points.append(Vector2(cos(angle), sin(angle)) * PICKUP_RADIUS)
	visual.polygon = points
	visual.color = Color(1.0, 0.9, 0.3, 0.9)
	add_child(visual)

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	for s in ships:
		var ship: ShipNode = s
		if is_instance_valid(ship) and ship.position.distance_to(position) < PICKUP_RADIUS + maxf(ship.half_extents.x, ship.half_extents.y):
			var weapon: WeaponData = ship.weapon_state.selected_weapon()
			ship.fill_selected_gauge(weapon.gauge_max * gauge_bonus_percent / 100.0)
			queue_free()
			return
