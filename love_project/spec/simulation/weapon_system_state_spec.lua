local weapon_data = require("simulation.weapon_data")
local weapon_system_state = require("simulation.weapon_system_state")

describe("weapon_system_state", function()
	it("new() starts every gauge/heat at 0 and the ultra meter empty", function()
		local laser = weapon_data.new({ id = "laser", fire_rate = 1.25, gauge_max = 100.0, gauge_cost_per_shot = 100.0 })
		local state = weapon_system_state.new({ laser })
		assert.are.equal(0.0, state.gauges[1])
		assert.are.equal(0.0, state.heats[1])
		assert.are.equal(0, state.ultra_pips)
		assert.is_false(weapon_system_state.ultra_ready(state))
	end)

	it("fired() is gated by gauge cost and sets a cooldown from fire_rate", function()
		local weapon = weapon_data.new({ fire_rate = 5.0, gauge_max = 100.0, gauge_cost_per_shot = 10.0 })
		local state = weapon_system_state.new({ weapon })
		local blocked = weapon_system_state.fired(state)
		assert.is_false(blocked.fired) -- empty gauge

		state = weapon_system_state.with_gauge_added(state, weapon.gauge_max)
		local result = weapon_system_state.fired(state)
		assert.is_true(result.fired)
		assert.are.equal(1.0 / weapon.fire_rate, result.state.cooldown)

		local immediate_refire = weapon_system_state.fired(result.state)
		assert.is_false(immediate_refire.fired) -- still on cooldown
	end)

	it("with_cooldown_ticked() counts the cooldown down to zero, never negative", function()
		local weapon = weapon_data.new({ fire_rate = 2.0, gauge_max = 10.0, gauge_cost_per_shot = 10.0 })
		local state = weapon_system_state.new({ weapon })
		state = weapon_system_state.with_gauge_added(state, weapon.gauge_max)
		state = weapon_system_state.fired(state).state
		state = weapon_system_state.with_cooldown_ticked(state, 10.0) -- way more than the 0.5s cooldown
		assert.are.equal(0.0, state.cooldown)
	end)

	-- 2026-08-09 heat gauge redesign: only drains while NOT actively firing.
	it("heat blocks firing once heat_max is reached, and only drains while not firing", function()
		local weapon = weapon_data.new({
			fire_rate = 100.0,
			gauge_max = 1000.0,
			gauge_cost_per_shot = 1.0,
			heat_max = 10.0,
			heat_per_shot = 10.0,
			heat_cooldown_rate = 5.0,
		})
		local state = weapon_system_state.new({ weapon })
		state = weapon_system_state.with_gauge_added(state, weapon.gauge_max)
		local result = weapon_system_state.fired(state)
		assert.is_true(result.fired)
		state = weapon_system_state.with_cooldown_ticked(result.state, 1.0) -- clear the fire-rate cooldown
		local overheated = weapon_system_state.fired(state)
		assert.is_false(overheated.fired) -- heat is maxed out

		local ticked_while_firing = weapon_system_state.with_heat_ticked(state, 1.0, true)
		assert.are.equal(state.heats[1], ticked_while_firing.heats[1]) -- no drain while firing

		local ticked_while_idle = weapon_system_state.with_heat_ticked(state, 1.0, false)
		assert.is_true(ticked_while_idle.heats[1] < state.heats[1])
	end)

	it("with_ultra_pip_added() caps at ULTRA_METER_MAX and with_ultra_consumed() zeroes it", function()
		local weapon = weapon_data.new({})
		local state = weapon_system_state.new({ weapon })
		for _ = 1, weapon_system_state.ULTRA_METER_MAX + 3 do
			state = weapon_system_state.with_ultra_pip_added(state)
		end
		assert.are.equal(weapon_system_state.ULTRA_METER_MAX, state.ultra_pips)
		assert.is_true(weapon_system_state.ultra_ready(state))

		state = weapon_system_state.with_ultra_consumed(state)
		assert.are.equal(0, state.ultra_pips)
		assert.is_false(weapon_system_state.ultra_ready(state))
	end)

	it("with_selection() wraps both above and below the kit's bounds", function()
		local kit = { weapon_data.new({ id = "a" }), weapon_data.new({ id = "b" }), weapon_data.new({ id = "c" }) }
		local state = weapon_system_state.new(kit, 0)
		local wrapped_up = weapon_system_state.with_selection(state, 3)
		assert.are.equal(0, wrapped_up.selected_index)
		local wrapped_down = weapon_system_state.with_selection(state, -1)
		assert.are.equal(2, wrapped_down.selected_index)
	end)

	it("does not mutate the original state (immutability)", function()
		local weapon = weapon_data.new({ gauge_max = 100.0 })
		local state = weapon_system_state.new({ weapon })
		local after = weapon_system_state.with_gauge_added(state, 50.0)
		assert.are.equal(0.0, state.gauges[1])
		assert.are.equal(50.0, after.gauges[1])
	end)
end)
