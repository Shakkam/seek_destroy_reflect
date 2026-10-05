-- Small portable stand-ins for the Godot built-in math functions
-- simulation/*.gd relies on (deg_to_rad, clampf, signf, move_toward).
-- See vector2.lua for the Lua-version-portability rationale.

local mathx = {}

function mathx.deg_to_rad(deg)
	return deg * math.pi / 180.0
end

function mathx.clampf(value, lo, hi)
	if value < lo then
		return lo
	end
	if value > hi then
		return hi
	end
	return value
end

function mathx.signf(value)
	if value > 0.0 then
		return 1.0
	end
	if value < 0.0 then
		return -1.0
	end
	return 0.0
end

function mathx.move_toward(from, to, delta)
	if math.abs(to - from) <= delta then
		return to
	end
	return from + mathx.signf(to - from) * delta
end

function mathx.lerp(from, to, t)
	return from + (to - from) * t
end

function mathx.is_equal_approx(a, b, epsilon)
	epsilon = epsilon or 1e-4
	return math.abs(a - b) <= epsilon
end

return mathx
