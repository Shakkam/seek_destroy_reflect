local twist_data = require("simulation.twist_data")

describe("twist_data", function()
	it("new() defaults to twist_type 'none'", function()
		local t = twist_data.new()
		assert.are.equal("none", t.twist_type)
	end)

	it("the organizer boss's escalation defaults match the 3-phase design", function()
		local t = twist_data.new()
		assert.are.equal(2.5, t.boss_size_multiplier)
		assert.are.equal(2.2, t.boss_hp_multiplier)
		assert.are.equal(0.65, t.boss_phase2_hp_fraction)
		assert.are.equal(0.30, t.boss_phase3_hp_fraction)
	end)

	it("hazard_zones config overrides only the fields it needs", function()
		local t = twist_data.new({ twist_type = "hazard_zones", hazard_count = 3 })
		assert.are.equal("hazard_zones", t.twist_type)
		assert.are.equal(3, t.hazard_count)
		assert.are.equal(24.0, t.hazard_radius) -- untouched default
	end)
end)
