local Vector2 = require("simulation.vector2")
local mathx = require("simulation.mathx")

-- Ported from godot_project/simulation/ship_state.gd — pure, deterministic
-- ship simulation state. No references to a scene tree or wall-clock time
-- — see project-context.md, "Frontiere simulation/rendu" (Regle absolue n1).
--
-- NOTE (carried over from the Godot source): `hp` here is a lightweight
-- counter, not the full best-of-3-rounds match resolution — see
-- match_state.lua for that.

local ship_state = {}

ship_state.SPEED = 420.0 -- px/s — "relativement rapide, mais pas ultra" (GDD)
ship_state.START_HP = 100.0

-- Neutral zone (2026-08-01): a band straddling the frontier that ships can
-- never physically enter — not just a visual, an actual movement boundary.
-- Single source of truth: ball_node's LÖVE-side port will reuse this same
-- constant so its own "no collision resolution here" zone always matches
-- where ships can be.
ship_state.NEUTRAL_ZONE_HALF_WIDTH = 30.0 -- widened 2026-08-01 (playtest feedback: still felt too tight)

function ship_state.new(position, side, half_extents, hp)
	return {
		position = position,
		side = side,
		half_extents = half_extents,
		hp = hp == nil and ship_state.START_HP or hp,
	}
end

local function clamp_to_half(state, pos, bounds, frontier_x)
	local min_x = bounds.position.x + state.half_extents.x
	local max_x = bounds.position.x + bounds.size.x - state.half_extents.x
	local min_y = bounds.position.y + state.half_extents.y
	local max_y = bounds.position.y + bounds.size.y - state.half_extents.y
	local clamped_x, clamped_y = pos.x, pos.y
	clamped_y = mathx.clampf(clamped_y, min_y, max_y)
	if state.side == 0 then
		clamped_x = mathx.clampf(clamped_x, min_x, frontier_x - ship_state.NEUTRAL_ZONE_HALF_WIDTH - state.half_extents.x)
	else
		clamped_x = mathx.clampf(clamped_x, frontier_x + ship_state.NEUTRAL_ZONE_HALF_WIDTH + state.half_extents.x, max_x)
	end
	return Vector2.new(clamped_x, clamped_y)
end

-- update(state, input_direction, delta, bounds, frontier_x, speed_multiplier) -> new_state
-- delta is passed explicitly (fixed physics tick) — never read from a
-- wall-clock inside simulation code.
function ship_state.update(state, input_direction, delta, bounds, frontier_x, speed_multiplier)
	speed_multiplier = speed_multiplier or 1.0
	local move = input_direction
	if move:length() > 1.0 then
		move = move:normalized()
	end
	local new_position = state.position + move * (ship_state.SPEED * speed_multiplier * delta)
	new_position = clamp_to_half(state, new_position, bounds, frontier_x)
	return ship_state.new(new_position, state.side, state.half_extents, state.hp)
end

function ship_state.damaged(state, amount)
	return ship_state.new(state.position, state.side, state.half_extents, math.max(state.hp - amount, 0.0))
end

-- Epic 4 reward system (2026-08-16) — Spreader's passive: a small HP regen
-- tick, the mirror image of damaged(). max_hp is passed in rather than
-- stored on ship_state itself (this has no notion of a cap — the ship's
-- own max_hp_override owns that, same reason update() takes bounds as a
-- parameter instead of storing them).
function ship_state.healed(state, amount, max_hp)
	return ship_state.new(state.position, state.side, state.half_extents, math.min(state.hp + amount, max_hp))
end

-- Lourd's "heavy_push" rule (2026-08-09) — an instantaneous positional
-- shove (e.g. from a fully-charged lift return reaching the opponent),
-- clamped to the same movement bounds as normal movement so it can never
-- push a ship out of the arena or across the neutral zone.
function ship_state.knocked_back(state, offset, bounds, frontier_x)
	local new_position = clamp_to_half(state, state.position + offset, bounds, frontier_x)
	return ship_state.new(new_position, state.side, state.half_extents, state.hp)
end

return ship_state
