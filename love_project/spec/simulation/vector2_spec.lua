local Vector2 = require("simulation.vector2")

describe("vector2", function()
	it("adds, subtracts, and scales without mutating the operands", function()
		local a = Vector2.new(1, 2)
		local b = Vector2.new(3, 4)
		local sum = a + b
		assert.are.equal(4, sum.x)
		assert.are.equal(6, sum.y)
		assert.are.equal(1, a.x) -- a untouched
		local scaled = a * 2
		assert.are.equal(2, scaled.x)
		assert.are.equal(4, scaled.y)
	end)

	it("rotated() rotates by the given angle in radians", function()
		local v = Vector2.new(1, 0)
		local rotated = v:rotated(math.pi / 2.0)
		assert.is_true(rotated:is_equal_approx(Vector2.new(0, 1), 1e-4))
	end)

	it("bounce() reflects off a normal, preserving speed (matches Godot's Vector2.bounce)", function()
		local v = Vector2.new(1, -1)
		local normal = Vector2.new(0, 1)
		local bounced = v:bounce(normal)
		assert.is_true(bounced:is_equal_approx(Vector2.new(1, 1), 1e-4))
		assert.is_true(math.abs(bounced:length() - v:length()) < 1e-4)
	end)

	it("normalized() of the zero vector returns zero rather than dividing by zero", function()
		local zero = Vector2.new(0, 0)
		assert.is_true(zero:normalized():is_equal_approx(Vector2.new(0, 0)))
	end)

	it("angle() matches atan2(y, x) semantics", function()
		assert.is_true(math.abs(Vector2.new(0, 1):angle() - math.pi / 2.0) < 1e-4)
		assert.is_true(math.abs(Vector2.new(-1, 0):angle() - math.pi) < 1e-4)
	end)
end)
