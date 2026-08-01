class_name WeaponSystemState
extends RefCounted

## Pure, deterministic weapon/gauge state for one ship. No Node/Godot
## references — see project-context.md, Regle absolue n1.
##
## Gauges are per-weapon (the GDD's "current lean", validated here by
## prototyping rather than decided upfront). Gauges now start EMPTY —
## Stories 1.6 (miss fills opponent's gauge) and 1.7 (successful return
## fills your own gauge, with a trick-shot bonus) are implemented below.

const RETURN_GAUGE_FILL := 10.0 # Story 1.7 — standard fill per successful return, no lift
const RETURN_GAUGE_FILL_MAX_LIFT := 15.0 # Story 1.7 — fill at a fully-charged (100%) lift return
const MISS_GAUGE_FILL := 50.0 # Story 1.6 — playtest-tuned down from a "full charge" (2026-08-01 feedback)

var kit: Array[WeaponData]
var gauges: Array[float] # parallel array to kit — current charge per weapon
var selected_index: int
var cooldown: float # seconds remaining before the next shot is allowed

func _init(weapon_kit: Array[WeaponData], start_selected: int = 0) -> void:
	kit = weapon_kit
	gauges = []
	for weapon in kit:
		gauges.append(0.0)
	selected_index = start_selected
	cooldown = 0.0

func selected_weapon() -> WeaponData:
	return kit[selected_index]

func with_selection(index: int) -> WeaponSystemState:
	var new_state := _clone()
	new_state.selected_index = ((index % kit.size()) + kit.size()) % kit.size()
	return new_state

## Fills a weapon's gauge (defaults to the currently selected weapon),
## clamped to that weapon's max. Used for both Story 1.6 (miss fills the
## opponent) and Story 1.7 (successful return fills your own gauge).
func with_gauge_added(amount: float, index: int = -1) -> WeaponSystemState:
	var target_index := index if index >= 0 else selected_index
	var new_state := _clone()
	new_state.gauges[target_index] = minf(gauges[target_index] + amount, kit[target_index].gauge_max)
	return new_state

func with_cooldown_ticked(delta: float) -> WeaponSystemState:
	var new_state := _clone()
	new_state.cooldown = maxf(cooldown - delta, 0.0)
	return new_state

## Attempts to fire the currently selected weapon.
## Returns {"state": WeaponSystemState, "fired": bool, "damage": int, "is_heavy": bool}
func fired() -> Dictionary:
	var weapon := selected_weapon()
	if cooldown > 0.0 or gauges[selected_index] < weapon.gauge_cost_per_shot:
		return {"state": self, "fired": false, "damage": 0, "is_heavy": false}

	var new_state := _clone()
	new_state.gauges[selected_index] = gauges[selected_index] - weapon.gauge_cost_per_shot
	new_state.cooldown = 1.0 / weapon.fire_rate
	return {"state": new_state, "fired": true, "damage": weapon.damage, "is_heavy": weapon.is_heavy}

func _clone() -> WeaponSystemState:
	var copy := WeaponSystemState.new(kit, selected_index)
	copy.gauges = gauges.duplicate()
	copy.cooldown = cooldown
	return copy
