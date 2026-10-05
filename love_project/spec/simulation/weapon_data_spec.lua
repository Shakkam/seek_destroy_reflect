local weapon_data = require("simulation.weapon_data")

describe("weapon_data", function()
	it("new() with no overrides matches WeaponData's Godot resource defaults", function()
		local w = weapon_data.new()
		assert.are.equal("", w.id)
		assert.are.equal(2.0, w.damage)
		assert.are.equal(5.0, w.fire_rate)
		assert.are.equal(100.0, w.gauge_max)
		assert.are.equal(10.0, w.gauge_cost_per_shot)
		assert.is_false(w.is_heavy)
		assert.are.equal("damage", w.effect_type)
		assert.are.equal(620.0, w.projectile_speed)
		assert.are.equal(1, w.projectile_count)
	end)

	-- Mirrors smoke_test.gd's _test_laser_pulse() field expectations, ported
	-- to the data-table shape (laser.tres itself isn't ported until the
	-- data/ folder's own migration phase).
	it("overrides only replace the fields given, keeping every other default (laser.tres-equivalent shape)", function()
		local laser = weapon_data.new({
			id = "laser",
			effect_type = "beam",
			beam_range = 1400.0,
			beam_duration = 0.5,
			fire_rate = 1.25, -- 1 / 0.8
			charged_beam_duration = 3.0,
			charged_beam_thickness_multiplier = 2.0,
			charge_fire_slow_multiplier = 0.6,
		})
		assert.are.equal("beam", laser.effect_type)
		assert.is_true(laser.beam_range > 1200.0)
		assert.is_true(math.abs(laser.beam_duration - 0.5) < 1e-4)
		assert.is_true(math.abs(1.0 / laser.fire_rate - 0.8) < 1e-4)
		assert.is_true(math.abs(laser.charged_beam_duration - 3.0) < 1e-4)
		assert.is_true(math.abs(laser.charged_beam_thickness_multiplier - 2.0) < 1e-4)
		assert.is_true(laser.charge_fire_slow_multiplier < 1.0 and laser.charge_fire_slow_multiplier > 0.0)
		-- fields not overridden keep their default
		assert.are.equal(2.0, laser.damage)
	end)
end)
