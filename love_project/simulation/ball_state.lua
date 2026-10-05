local Vector2 = require("simulation.vector2")
local mathx = require("simulation.mathx")

-- Ported from godot_project/simulation/ball_state.gd — pure, deterministic
-- ball simulation state. No engine references — see project-context.md,
-- "Frontiere simulation/rendu" (Regle absolue n1). The ball never deals
-- damage — it is purely a resource-catch mechanic (GDD).
--
-- Functional style throughout (per the port spec's own recommendation,
-- section 7): a ball_state is a plain table, and every function here takes
-- one as its first argument and returns a NEW table rather than mutating it.

local ball_state = {}

ball_state.BASE_SPEED = 418.0 -- +10% (2026-08-01 playtest feedback: felt a bit slow to start)
-- 2026-10-05 ("tout plus gros" pass, a friend's playtest relayed by Camil —
-- Camil's own scoping: +50%, every mode, ball/paddles/shots/speed-ramp but
-- explicitly NOT damage/HP) — radius and the per-rally speed increment both
-- bumped x1.5. MAX_SPEED is NEW: a long rally's speed used to grow
-- forever, unbounded — bumping the increment without a ceiling would make
-- a long rally eventually unreturnable/unreadable, so this caps it at a
-- clean 2x the base serve speed (returned() below clamps to it).
ball_state.RADIUS = 10.0 * 1.5
ball_state.SPEED_INCREMENT_PER_RETURN = 18.0 * 1.5 -- Story 1.3 — ball speeds up slightly each rally exchange
ball_state.MAX_SPEED = ball_state.BASE_SPEED * 2.0
ball_state.SPIN_STRENGTH = 2.0 -- rad/s of curvature at full (100%) lift charge
ball_state.SPIN_DECAY = 1.0 -- rad/s^2 — spin fades out over the flight instead of curving forever
ball_state.MAX_SPIN_ANGLE_FROM_HORIZONTAL_RAD = mathx.deg_to_rad(70.0) -- 2026-08-14 bug fix: clamp keeps at least 20 degrees of margin from straight-up/down at all times

-- 2026-10-05 (a friend's playtest, relayed by Camil: "le rebond sur la
-- raquette est frustrant, il ne depend pas de l'angle de rebond mais de la
-- vitesse de deplacement de la raquette [...] il n'y a que 3 directions...
-- LE truc a changer, c'est le rebond sur la raquette qui doit dependre de
-- ou la balle rebondit sur la raquette. La direction/vitesse de la
-- raquette peut influer sur le rebond mais ca doit rester secondaire.") —
-- see returned()'s `contact_offset` branch. WHERE the ball hits the
-- paddle (-1 top edge, 0 center, +1 bottom edge) now drives up to this
-- many degrees of bounce angle; the held aim direction only nudges a
-- little further on top of that. MAX_TOTAL keeps the same vertical-margin
-- safety the spin clamp above already uses, so a corner hit + full aim
-- still can't produce a near-unreturnable near-vertical shot.
ball_state.MAX_PADDLE_BOUNCE_ANGLE_RAD = mathx.deg_to_rad(60.0) -- 2026-10-05 playtest: "l'angle est trop prononce sur les bords, enleve 5 degres" (was 65)
ball_state.AIM_BOUNCE_ANGLE_RAD = mathx.deg_to_rad(15.0)
ball_state.MAX_TOTAL_BOUNCE_ANGLE_RAD = mathx.deg_to_rad(75.0)

function ball_state.new(position, velocity, spin, rally_count)
	return {
		position = position,
		velocity = velocity,
		spin = spin or 0.0,
		rally_count = rally_count or 0,
	}
end

-- Keeps a spin-curved velocity from getting too close to a straight
-- vertical path (see MAX_SPIN_ANGLE_FROM_HORIZONTAL_RAD): rescales toward a
-- minimum horizontal component while preserving speed and both axes'
-- signs, so the curve still reads as a curve but never spins the ball into
-- an unreturnable near-vertical (or reversed) shot.
local function clamp_from_vertical(state, v)
	local speed = v:length()
	if speed < 0.01 then
		return v
	end
	local min_abs_x = speed * math.cos(ball_state.MAX_SPIN_ANGLE_FROM_HORIZONTAL_RAD)
	if math.abs(v.x) >= min_abs_x then
		return v
	end
	local x_sign = v.x ~= 0.0 and mathx.signf(v.x) or mathx.signf(state.velocity.x)
	if x_sign == 0.0 then
		x_sign = 1.0
	end
	local y_sign = v.y ~= 0.0 and mathx.signf(v.y) or 1.0
	local clamped_x = min_abs_x * x_sign
	local clamped_y = math.sqrt(math.max(speed * speed - clamped_x * clamped_x, 0.0)) * y_sign
	return Vector2.new(clamped_x, clamped_y)
end

function ball_state.update(state, delta)
	local new_velocity = state.velocity
	if state.spin ~= 0.0 then
		new_velocity = clamp_from_vertical(state, state.velocity:rotated(state.spin * delta))
	end
	local new_spin = mathx.move_toward(state.spin, 0.0, ball_state.SPIN_DECAY * delta)
	return ball_state.new(state.position + new_velocity * delta, new_velocity, new_spin, state.rally_count)
end

function ball_state.bounced_off_wall(state, clamped_y)
	return ball_state.new(
		Vector2.new(state.position.x, clamped_y),
		Vector2.new(state.velocity.x, -state.velocity.y),
		state.spin,
		state.rally_count
	)
end

-- Breakout mini-jeu (2026-08-18): the horizontal mirror of
-- bounced_off_wall's vertical one. Opt-in, never used by the normal 2-ship
-- game (there, reaching either side unreturned is a miss/score event, not
-- a wall).
function ball_state.bounced_off_side_wall(state, clamped_x)
	return ball_state.new(
		Vector2.new(clamped_x, state.position.y),
		Vector2.new(-state.velocity.x, state.velocity.y),
		state.spin,
		state.rally_count
	)
end

-- Epic 4, Story 4.5 — "hazard_zones" twist: reflects velocity off a
-- circular obstacle's surface normal (same speed, new direction).
function ball_state.bounced_off_hazard(state, hazard_center)
	local normal = (state.position - hazard_center):normalized()
	if normal:length() < 0.01 then
		normal = Vector2.RIGHT -- degenerate case: ball position exactly on the hazard's center
	end
	return ball_state.new(state.position, state.velocity:bounce(normal), state.spin, state.rally_count)
end

-- Player-initiated return.
-- aim_direction: raw directional input at the moment of contact
-- (Vector2.ZERO if none held).
-- lift_charge: 0.0-1.0, how charged the lift/spin was.
-- outgoing_side: +1 to send the ball right, -1 to send it left.
-- speed_increment: how much faster each successive return makes the ball,
-- defaulting to the normal match's own SPEED_INCREMENT_PER_RETURN.
-- contact_offset: -1..1, where the ball hit the paddle (top edge to bottom
-- edge) at the moment of contact — nil for a non-paddle bounce (turrets),
-- which keeps the old aim-or-mirror behavior untouched. See the 2026-10-05
-- doc comment above MAX_PADDLE_BOUNCE_ANGLE_RAD for why this exists.
function ball_state.returned(state, aim_direction, lift_charge, outgoing_side, speed_increment, contact_offset)
	speed_increment = speed_increment or ball_state.SPEED_INCREMENT_PER_RETURN
	local dir
	if contact_offset ~= nil then
		local offset = mathx.clampf(contact_offset, -1.0, 1.0)
		local aim_y = aim_direction:length() > 0.01 and mathx.clampf(aim_direction.y, -1.0, 1.0) or 0.0
		local angle = offset * ball_state.MAX_PADDLE_BOUNCE_ANGLE_RAD + aim_y * ball_state.AIM_BOUNCE_ANGLE_RAD
		angle = mathx.clampf(angle, -ball_state.MAX_TOTAL_BOUNCE_ANGLE_RAD, ball_state.MAX_TOTAL_BOUNCE_ANGLE_RAD)
		dir = Vector2.new(math.cos(angle) * outgoing_side, math.sin(angle))
	elseif aim_direction:length() > 0.01 then
		dir = Vector2.new(outgoing_side, mathx.clampf(aim_direction.y, -1.0, 1.0)):normalized()
	else
		-- No aim input -> default straightforward reflection: a true mirror
		-- bounce off the paddle, exact opposite horizontal angle, vertical
		-- direction preserved (not flattened to a straight horizontal shot).
		local mirrored = Vector2.new(-state.velocity.x, state.velocity.y)
		dir = mirrored:length() > 0.01 and mirrored:normalized() or Vector2.new(outgoing_side, 0.0)
	end

	local new_spin = ball_state.SPIN_STRENGTH * lift_charge
	if outgoing_side < 0 then
		new_spin = -new_spin
	end

	local new_rally_count = state.rally_count + 1
	local speed = math.min(ball_state.BASE_SPEED + speed_increment * new_rally_count, ball_state.MAX_SPEED)
	return ball_state.new(state.position, dir * speed, new_spin, new_rally_count)
end

return ball_state
