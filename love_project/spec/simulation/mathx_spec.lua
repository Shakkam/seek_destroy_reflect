local mathx = require("simulation.mathx")

describe("mathx", function()
	it("clampf() clamps into [lo, hi]", function()
		assert.are.equal(5.0, mathx.clampf(10.0, 0.0, 5.0))
		assert.are.equal(0.0, mathx.clampf(-10.0, 0.0, 5.0))
		assert.are.equal(3.0, mathx.clampf(3.0, 0.0, 5.0))
	end)

	it("signf() returns -1/0/1", function()
		assert.are.equal(1.0, mathx.signf(4.0))
		assert.are.equal(-1.0, mathx.signf(-4.0))
		assert.are.equal(0.0, mathx.signf(0.0))
	end)

	it("move_toward() steps toward the target without overshooting", function()
		assert.are.equal(5.0, mathx.move_toward(0.0, 10.0, 5.0))
		assert.are.equal(10.0, mathx.move_toward(8.0, 10.0, 5.0)) -- clamps at the target
		assert.are.equal(-5.0, mathx.move_toward(0.0, -10.0, 5.0))
	end)

	it("lerp() interpolates linearly", function()
		assert.are.equal(5.0, mathx.lerp(0.0, 10.0, 0.5))
		assert.are.equal(0.0, mathx.lerp(0.0, 10.0, 0.0))
		assert.are.equal(10.0, mathx.lerp(0.0, 10.0, 1.0))
		assert.are.equal(15.0, mathx.lerp(10.0, 15.0, 1.0)) -- Story 1.7's own gauge-fill-by-lift formula shape
	end)

	it("deg_to_rad() matches math.rad()", function()
		assert.is_true(math.abs(mathx.deg_to_rad(180.0) - math.pi) < 1e-9)
	end)
end)
