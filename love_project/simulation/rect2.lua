-- Minimal Rect2 value type (position + size, both Vector2), mirroring the
-- subset of Godot's Rect2 API used by simulation/ (ship_state.gd's movement
-- bounds). See vector2.lua for the immutability/Lua-version-portability
-- conventions this follows.

local Vector2 = require("simulation.vector2")

local Rect2 = {}

function Rect2.new(x, y, w, h)
	return {
		position = Vector2.new(x, y),
		size = Vector2.new(w, h),
	}
end

function Rect2.has_point(rect, point)
	return point.x >= rect.position.x and point.x <= rect.position.x + rect.size.x
		and point.y >= rect.position.y and point.y <= rect.position.y + rect.size.y
end

return Rect2
