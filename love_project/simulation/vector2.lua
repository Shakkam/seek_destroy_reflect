-- Minimal 2D vector value type, mirroring the subset of Godot's Vector2 API
-- actually used by the simulation/ layer (see the Godot project's
-- simulation/*.gd). Immutable: every operation returns a NEW Vector2
-- rather than mutating self or its operands — same convention as the rest
-- of simulation/ (project-context.md, Regle absolue n1), even though a
-- math vector is not itself "simulation state".
--
-- Deliberately avoids any Lua 5.4-only syntax/stdlib (see the port spec,
-- section 1: LÖVE's own bundled interpreter is LuaJIT/Lua 5.1-compatible,
-- and this module must load under both).

local Vector2 = {}
Vector2.__index = Vector2

function Vector2.new(x, y)
	return setmetatable({ x = x or 0.0, y = y or 0.0 }, Vector2)
end

function Vector2.__add(a, b)
	return Vector2.new(a.x + b.x, a.y + b.y)
end

function Vector2.__sub(a, b)
	return Vector2.new(a.x - b.x, a.y - b.y)
end

-- v * scalar, scalar * v, or componentwise v * v.
function Vector2.__mul(a, b)
	if type(a) == "number" then
		return Vector2.new(a * b.x, a * b.y)
	elseif type(b) == "number" then
		return Vector2.new(a.x * b, a.y * b)
	else
		return Vector2.new(a.x * b.x, a.y * b.y)
	end
end

function Vector2.__unm(a)
	return Vector2.new(-a.x, -a.y)
end

function Vector2.__eq(a, b)
	return a.x == b.x and a.y == b.y
end

function Vector2.__tostring(a)
	return string.format("(%g, %g)", a.x, a.y)
end

function Vector2:length()
	return math.sqrt(self.x * self.x + self.y * self.y)
end

function Vector2:length_squared()
	return self.x * self.x + self.y * self.y
end

function Vector2:normalized()
	local len = self:length()
	if len < 1e-9 then
		return Vector2.new(0.0, 0.0)
	end
	return Vector2.new(self.x / len, self.y / len)
end

function Vector2:dot(other)
	return self.x * other.x + self.y * other.y
end

function Vector2:distance_to(other)
	return (self - other):length()
end

-- atan2(y, x) written out by hand rather than via Lua 5.4's two-argument
-- math.atan(y, x) — that form doesn't exist in LuaJIT/Lua 5.1, which is
-- what LÖVE embeds (see the port spec's compatibility note). Single-arg
-- math.atan() is portable across every Lua version this project targets.
function Vector2:angle()
	local x, y = self.x, self.y
	if x > 0.0 then
		return math.atan(y / x)
	elseif x < 0.0 and y >= 0.0 then
		return math.atan(y / x) + math.pi
	elseif x < 0.0 and y < 0.0 then
		return math.atan(y / x) - math.pi
	elseif x == 0.0 and y > 0.0 then
		return math.pi / 2.0
	elseif x == 0.0 and y < 0.0 then
		return -math.pi / 2.0
	end
	return 0.0
end

function Vector2:rotated(angle_rad)
	local c, s = math.cos(angle_rad), math.sin(angle_rad)
	return Vector2.new(self.x * c - self.y * s, self.x * s + self.y * c)
end

-- Reflects self off a plane orthogonal to `normal` — matches Godot's
-- Vector2.bounce(): v - 2 * (v . n) * n.
function Vector2:bounce(normal)
	local d = self:dot(normal)
	return self - normal * (2.0 * d)
end

function Vector2:is_equal_approx(other, epsilon)
	epsilon = epsilon or 1e-4
	return math.abs(self.x - other.x) <= epsilon and math.abs(self.y - other.y) <= epsilon
end

Vector2.ZERO = Vector2.new(0.0, 0.0)
Vector2.RIGHT = Vector2.new(1.0, 0.0)

return Vector2
