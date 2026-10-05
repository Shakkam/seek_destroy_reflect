local Vector2 = require("simulation.vector2")
local ball_state = require("simulation.ball_state")

describe("ball_state", function()
	it("new() starts with rally_count 0 and the given spin", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(1, 0))
		assert.are.equal(0, state.rally_count)
		assert.are.equal(0.0, state.spin)
	end)

	it("update() integrates position by velocity * delta", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(100, 0))
		local after = ball_state.update(state, 0.5)
		assert.is_true(after.position:is_equal_approx(Vector2.new(50, 0)))
	end)

	it("update() decays spin toward zero over time and curves velocity while spinning", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(100, 0), 2.0)
		local after = ball_state.update(state, 0.1)
		assert.is_true(after.spin < 2.0)
		assert.is_true(math.abs(after.velocity.y) > 0.0) -- no longer pointing purely along +x
	end)

	-- 2026-08-14 bug fix (Camil, screenshot with near-vertical trajectory):
	-- a fully-charged spin must never rotate the ball past
	-- MAX_SPIN_ANGLE_FROM_HORIZONTAL_RAD from horizontal.
	it("a fully-charged spin never rotates the ball closer than 20deg from vertical", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(400, 0), ball_state.SPIN_STRENGTH)
		local min_angle_from_vertical = math.huge
		for _ = 1, 60 do
			state = ball_state.update(state, 1.0 / 60.0)
			local angle_from_horizontal = math.abs(state.velocity:angle())
			local angle_from_vertical = math.abs(math.pi / 2.0 - angle_from_horizontal)
			min_angle_from_vertical = math.min(min_angle_from_vertical, angle_from_vertical)
		end
		assert.is_true(min_angle_from_vertical >= math.rad(19.5))
	end)

	it("bounced_off_wall() flips vertical velocity and snaps to the wall's y", function()
		local state = ball_state.new(Vector2.new(50, 10), Vector2.new(30, 40))
		local after = ball_state.bounced_off_wall(state, 0.0)
		assert.are.equal(0.0, after.position.y)
		assert.are.equal(30.0, after.velocity.x)
		assert.are.equal(-40.0, after.velocity.y)
	end)

	it("bounced_off_side_wall() flips horizontal velocity and snaps to the wall's x (Breakout)", function()
		local state = ball_state.new(Vector2.new(10, 50), Vector2.new(30, 40))
		local after = ball_state.bounced_off_side_wall(state, 100.0)
		assert.are.equal(100.0, after.position.x)
		assert.are.equal(-30.0, after.velocity.x)
		assert.are.equal(40.0, after.velocity.y)
	end)

	it("bounced_off_hazard() reflects off the obstacle's surface normal, preserving speed", function()
		local state = ball_state.new(Vector2.new(100, 0), Vector2.new(200, 0))
		local after = ball_state.bounced_off_hazard(state, Vector2.new(120, 0))
		assert.is_true(after.velocity.x < 0.0)
		assert.is_true(math.abs(after.velocity:length() - state.velocity:length()) < 1e-4)
	end)

	it("returned() with no aim input mirrors the incoming angle and preserves vertical direction", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(-300, 50))
		local after = ball_state.returned(state, Vector2.new(0, 0), 0.0, 1)
		assert.is_true(after.velocity.x > 0.0)
		assert.is_true(after.velocity.y > 0.0)
	end)

	it("returned() speeds up with each successive rally exchange", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(-300, 0), 0.0, 4)
		local after = ball_state.returned(state, Vector2.new(0, 0), 0.0, 1)
		assert.are.equal(5, after.rally_count)
		assert.is_true(after.velocity:length() > ball_state.BASE_SPEED)
	end)

	-- 2026-10-05 "tout plus gros" pass: the per-rally speed increment was
	-- bumped (and the increment itself was always unbounded before this) —
	-- MAX_SPEED is the new safety net so an extremely long rally plateaus
	-- instead of eventually becoming unreturnable/unreadable.
	it("returned() speed never exceeds MAX_SPEED, however long the rally", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(-300, 0), 0.0, 500)
		local after = ball_state.returned(state, Vector2.new(0, 0), 0.0, 1)
		assert.is_true(after.velocity:length() <= ball_state.MAX_SPEED + 1e-6)
	end)

	it("returned() applies spin proportional to lift_charge, sign following outgoing_side", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(-300, 0))
		local right = ball_state.returned(state, Vector2.new(1, 0), 1.0, 1)
		local left = ball_state.returned(state, Vector2.new(-1, 0), 1.0, -1)
		assert.is_true(right.spin > 0.0)
		assert.is_true(left.spin < 0.0)
	end)

	-- 2026-10-05 (a friend's playtest, relayed by Camil: "le rebond sur la
	-- raquette doit dependre de ou la balle rebondit sur la raquette, pas de
	-- la vitesse/direction de la raquette, qui doit rester secondaire").
	it("returned() with contact_offset=0 (paddle center) sends the ball nearly flat", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(-300, 0))
		local after = ball_state.returned(state, Vector2.new(0, 0), 0.0, 1, nil, 0.0)
		assert.is_true(math.abs(after.velocity.y) < 1.0)
	end)

	it("returned() with contact_offset=-1 (top edge) sends the ball steeply upward", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(-300, 0))
		local after = ball_state.returned(state, Vector2.new(0, 0), 0.0, 1, nil, -1.0)
		assert.is_true(after.velocity.y < 0.0)
		local angle_from_horizontal = math.abs(after.velocity:angle())
		assert.is_true(angle_from_horizontal >= ball_state.MAX_PADDLE_BOUNCE_ANGLE_RAD - 0.01)
	end)

	it("returned() with contact_offset=1 (bottom edge) sends the ball steeply downward", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(-300, 0))
		local after = ball_state.returned(state, Vector2.new(0, 0), 0.0, 1, nil, 1.0)
		assert.is_true(after.velocity.y > 0.0)
	end)

	it("returned() treats aim direction as secondary to contact_offset (smaller swing than a paddle-edge hit)", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(-300, 0))
		local center_no_aim = ball_state.returned(state, Vector2.new(0, 0), 0.0, 1, nil, 0.0)
		local center_full_aim = ball_state.returned(state, Vector2.new(0, 1), 0.0, 1, nil, 0.0)
		local edge_no_aim = ball_state.returned(state, Vector2.new(0, 0), 0.0, 1, nil, 1.0)
		local aim_only_angle = math.abs(center_full_aim.velocity:angle() - center_no_aim.velocity:angle())
		local offset_only_angle = math.abs(edge_no_aim.velocity:angle() - center_no_aim.velocity:angle())
		assert.is_true(aim_only_angle < offset_only_angle)
	end)

	it("returned() with contact_offset=nil (turret bounce) keeps the old mirror-or-aim behavior", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(-300, 50))
		local after = ball_state.returned(state, Vector2.new(0, 0), 0.0, 1)
		assert.is_true(after.velocity.x > 0.0)
		assert.is_true(after.velocity.y > 0.0)
	end)

	it("does not mutate the original state (immutability)", function()
		local state = ball_state.new(Vector2.new(0, 0), Vector2.new(100, 0))
		local after = ball_state.update(state, 1.0)
		assert.are_not.equal(state, after)
		assert.is_true(state.position:is_equal_approx(Vector2.new(0, 0)))
	end)
end)
