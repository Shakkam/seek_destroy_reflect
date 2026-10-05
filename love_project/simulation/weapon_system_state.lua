-- Ported from godot_project/simulation/weapon_system_state.gd — pure,
-- deterministic weapon/gauge state for one ship. No engine references.
--
-- Gauges are per-weapon. Gauges start EMPTY — Stories 1.6 (miss fills
-- opponent's gauge) and 1.7 (successful return fills your own gauge, with
-- a trick-shot bonus) are implemented below.
--
-- kit/gauges/heats are 1-indexed Lua arrays internally, but selected_index
-- and the `index` parameter of with_gauge_added() stay 0-based to match
-- the Godot source and the rest of this port.

local weapon_system_state = {}

weapon_system_state.RETURN_GAUGE_FILL = 10.0 -- Story 1.7 — standard fill per successful return, no lift
weapon_system_state.RETURN_GAUGE_FILL_MAX_LIFT = 15.0 -- Story 1.7 — fill at a fully-charged (100%) lift return
weapon_system_state.MISS_GAUGE_FILL = 50.0 -- Story 1.6 — playtest-tuned down from a "full charge"

-- "Systeme des 5 balles" (2026-08-11 brainstorm, built 2026-08-13): one pip
-- per opponent miss, consumed entirely when the ultra triggers. Named
-- "Ultra" not "Super" — collides with the GDD's existing "arme 'super'"
-- weapon-tier naming otherwise.
weapon_system_state.ULTRA_METER_MAX = 5

function weapon_system_state.new(kit, start_selected)
	local gauges, heats = {}, {}
	for i = 1, #kit do
		gauges[i] = 0.0
		heats[i] = 0.0
	end
	return {
		kit = kit,
		gauges = gauges,
		heats = heats,
		selected_index = start_selected or 0,
		cooldown = 0.0,
		ultra_pips = 0,
	}
end

local function clone(state)
	local new_state = weapon_system_state.new(state.kit, state.selected_index)
	for i = 1, #state.kit do
		new_state.gauges[i] = state.gauges[i]
		new_state.heats[i] = state.heats[i]
	end
	new_state.cooldown = state.cooldown
	new_state.ultra_pips = state.ultra_pips
	return new_state
end

function weapon_system_state.selected_weapon(state)
	return state.kit[state.selected_index + 1]
end

function weapon_system_state.with_selection(state, index)
	local new_state = clone(state)
	local size = #state.kit
	new_state.selected_index = ((index % size) + size) % size
	return new_state
end

-- Fills a weapon's gauge (defaults to the currently selected weapon),
-- clamped to that weapon's max. Used for both Story 1.6 (miss fills the
-- opponent) and Story 1.7 (successful return fills your own gauge).
function weapon_system_state.with_gauge_added(state, amount, index)
	local target_index = index ~= nil and index or state.selected_index
	local new_state = clone(state)
	local slot = target_index + 1
	new_state.gauges[slot] = math.min(state.gauges[slot] + amount, state.kit[slot].gauge_max)
	return new_state
end

function weapon_system_state.with_cooldown_ticked(state, delta)
	local new_state = clone(state)
	new_state.cooldown = math.max(state.cooldown - delta, 0.0)
	return new_state
end

-- +1 pip, capped at ULTRA_METER_MAX — one call per opponent miss.
function weapon_system_state.with_ultra_pip_added(state)
	local new_state = clone(state)
	new_state.ultra_pips = math.min(state.ultra_pips + 1, weapon_system_state.ULTRA_METER_MAX)
	return new_state
end

function weapon_system_state.ultra_ready(state)
	return state.ultra_pips >= weapon_system_state.ULTRA_METER_MAX
end

-- Spends the whole meter — called the instant the ultra triggers, so a
-- held/repeated trigger input can never fire it twice off one fill.
function weapon_system_state.with_ultra_consumed(state)
	local new_state = clone(state)
	new_state.ultra_pips = 0
	return new_state
end

-- Heat gauge: only drains while NOT actively firing, so any pause —
-- however short — always helps a little instead of being wasted.
function weapon_system_state.with_heat_ticked(state, delta, is_firing)
	if is_firing then
		return state -- heat only changes via fired()'s own increment while actively shooting
	end
	local weapon = weapon_system_state.selected_weapon(state)
	local slot = state.selected_index + 1
	if (weapon.heat_cooldown_rate or 0.0) <= 0.0 or state.heats[slot] <= 0.0 then
		return state
	end
	local new_state = clone(state)
	new_state.heats[slot] = math.max(state.heats[slot] - weapon.heat_cooldown_rate * delta, 0.0)
	return new_state
end

-- Attempts to fire the currently selected weapon.
-- Returns { state = weapon_system_state, fired = bool, weapon = weapon_data|nil }
function weapon_system_state.fired(state)
	local weapon = weapon_system_state.selected_weapon(state)
	local slot = state.selected_index + 1
	if state.cooldown > 0.0 or state.gauges[slot] < weapon.gauge_cost_per_shot then
		return { state = state, fired = false, weapon = nil }
	end
	if (weapon.heat_max or 0.0) > 0.0 and state.heats[slot] >= weapon.heat_max then
		return { state = state, fired = false, weapon = nil } -- overheated — release fire and let it cool
	end

	local new_state = clone(state)
	new_state.gauges[slot] = state.gauges[slot] - weapon.gauge_cost_per_shot
	new_state.cooldown = 1.0 / weapon.fire_rate
	if (weapon.heat_max or 0.0) > 0.0 then
		new_state.heats[slot] = math.min(state.heats[slot] + weapon.heat_per_shot, weapon.heat_max)
	end
	return { state = new_state, fired = true, weapon = weapon }
end

return weapon_system_state
