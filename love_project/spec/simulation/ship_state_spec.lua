local Vector2 = require("simulation.vector2")
local Rect2 = require("simulation.rect2")
local ship_state = require("simulation.ship_state")

describe("ship_state", function()
	local bounds = Rect2.new(0, 0, 1280, 720)
	local frontier_x = 640.0

	it("new() defaults hp to START_HP", function()
		local state = ship_state.new(Vector2.new(100, 300), 0, Vector2.new(14, 28))
		assert.are.equal(ship_state.START_HP, state.hp)
	end)

	it("update() moves at SPEED * delta along the input direction", function()
		local state = ship_state.new(Vector2.new(100, 300), 0, Vector2.new(14, 28))
		local after = ship_state.update(state, Vector2.new(0, 1), 0.5, bounds, frontier_x)
		assert.is_true(math.abs(after.position.y - (300 + ship_state.SPEED * 0.5)) < 1e-4)
	end)

	it("update() never lets side 0 cross the neutral zone into side 1's territory", function()
		local state = ship_state.new(Vector2.new(600, 300), 0, Vector2.new(14, 28))
		local after = ship_state.update(state, Vector2.new(1, 0), 5.0, bounds, frontier_x)
		local max_x = frontier_x - ship_state.NEUTRAL_ZONE_HALF_WIDTH - state.half_extents.x
		assert.is_true(after.position.x <= max_x + 1e-4)
	end)

	it("update() never lets side 1 cross the neutral zone into side 0's territory", function()
		local state = ship_state.new(Vector2.new(680, 300), 1, Vector2.new(14, 28))
		local after = ship_state.update(state, Vector2.new(-1, 0), 5.0, bounds, frontier_x)
		local min_x = frontier_x + ship_state.NEUTRAL_ZONE_HALF_WIDTH + state.half_extents.x
		assert.is_true(after.position.x >= min_x - 1e-4)
	end)

	it("update() clamps a normalized-length-1+ input direction (diagonal input doesn't move faster)", function()
		local state = ship_state.new(Vector2.new(300, 300), 0, Vector2.new(14, 28))
		local after = ship_state.update(state, Vector2.new(1, 1), 0.1, bounds, frontier_x)
		local displacement = after.position:distance_to(state.position)
		assert.is_true(math.abs(displacement - ship_state.SPEED * 0.1) < 1e-3)
	end)

	it("damaged() reduces hp but never below zero", function()
		local state = ship_state.new(Vector2.new(0, 0), 0, Vector2.new(14, 28), 10.0)
		local after = ship_state.damaged(state, 999.0)
		assert.are.equal(0.0, after.hp)
	end)

	it("healed() adds hp but never above max_hp (Spreader's passive)", function()
		local state = ship_state.new(Vector2.new(0, 0), 0, Vector2.new(14, 28), 95.0)
		local after = ship_state.healed(state, 50.0, 100.0)
		assert.are.equal(100.0, after.hp)
	end)

	it("knocked_back() shoves the ship but clamps to the same bounds as normal movement (Lourd's heavy_push)", function()
		local state = ship_state.new(Vector2.new(600, 300), 0, Vector2.new(14, 28))
		local after = ship_state.knocked_back(state, Vector2.new(500, 0), bounds, frontier_x)
		local max_x = frontier_x - ship_state.NEUTRAL_ZONE_HALF_WIDTH - state.half_extents.x
		assert.is_true(after.position.x <= max_x + 1e-4)
	end)

	it("does not mutate the original state (immutability)", function()
		local state = ship_state.new(Vector2.new(100, 300), 0, Vector2.new(14, 28))
		local after = ship_state.damaged(state, 10.0)
		assert.are.equal(ship_state.START_HP, state.hp)
		assert.are.equal(ship_state.START_HP - 10.0, after.hp)
	end)
end)
