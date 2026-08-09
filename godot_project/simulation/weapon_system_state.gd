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

var kit: Array # of WeaponData
var gauges: Array[float] # parallel array to kit — current charge per weapon
var heats: Array[float] # parallel array to kit — current "barrel heat" per weapon (see WeaponData.heat_max)
var selected_index: int
var cooldown: float # seconds remaining before the next shot is allowed

func _init(weapon_kit: Array, start_selected: int = 0) -> void:
	kit = weapon_kit
	gauges = []
	heats = []
	for weapon in kit:
		gauges.append(0.0)
		heats.append(0.0)
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

## Heat gauge (2026-08-09 playtest, replacing the earlier hard burst-limit:
## "je tire 4 balles, j'attends 3 secondes, et je ne peux tirer que 2 balles
## => frustrant" — a flat "N shots then a fixed 1s lockout" counter never
## decayed on a partial pause, so stopping early bought nothing). Only
## drains while NOT actively firing ("des qu'on relache le bouton de tir la
## jauge remonte progressivement"), so any pause — however short — always
## helps a little instead of being wasted.
func with_heat_ticked(delta: float, is_firing: bool) -> WeaponSystemState:
	if is_firing:
		return self # heat only changes via fired()'s own increment while actively shooting
	var weapon := selected_weapon()
	if weapon.heat_cooldown_rate <= 0.0 or heats[selected_index] <= 0.0:
		return self
	var new_state := _clone()
	new_state.heats[selected_index] = maxf(heats[selected_index] - weapon.heat_cooldown_rate * delta, 0.0)
	return new_state

## Attempts to fire the currently selected weapon.
## Returns {"state": WeaponSystemState, "fired": bool, "weapon": WeaponData}
func fired() -> Dictionary:
	var weapon := selected_weapon()
	if cooldown > 0.0 or gauges[selected_index] < weapon.gauge_cost_per_shot:
		return {"state": self, "fired": false, "weapon": null}
	if weapon.heat_max > 0.0 and heats[selected_index] >= weapon.heat_max:
		return {"state": self, "fired": false, "weapon": null} # overheated — release fire and let it cool

	var new_state := _clone()
	new_state.gauges[selected_index] = gauges[selected_index] - weapon.gauge_cost_per_shot
	new_state.cooldown = 1.0 / weapon.fire_rate
	if weapon.heat_max > 0.0:
		new_state.heats[selected_index] = minf(heats[selected_index] + weapon.heat_per_shot, weapon.heat_max)
	return {"state": new_state, "fired": true, "weapon": weapon}

## Continuous alternative to fired(), for effect_type == "beam" weapons only.
## Instead of a one-time gauge_cost_per_shot gated by a per-shot cooldown,
## a beam drains gauge_cost_per_shot as a PER-SECOND rate for as long as
## it's called (i.e. as long as the fire button is held) and simply stops
## being "active" once the gauge runs dry — no cooldown, no discrete shot.
## Returns {"state": WeaponSystemState, "active": bool}.
func beam_tick(delta: float) -> Dictionary:
	var weapon := selected_weapon()
	var cost := weapon.gauge_cost_per_shot * delta
	if gauges[selected_index] < cost:
		return {"state": self, "active": false}
	var new_state := _clone()
	new_state.gauges[selected_index] = gauges[selected_index] - cost
	return {"state": new_state, "active": true}

func _clone() -> WeaponSystemState:
	var copy := WeaponSystemState.new(kit, selected_index)
	copy.gauges = gauges.duplicate()
	copy.heats = heats.duplicate()
	copy.cooldown = cooldown
	return copy
