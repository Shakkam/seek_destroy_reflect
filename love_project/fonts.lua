-- Small cached-Font registry. 2026-09-13 bug report (Camil, screenshot):
-- the title screen read as "tout flou" — every oversized text in this port
-- was LÖVE's tiny default font (love.graphics.getFont()) stretched up via
-- print/printf's sx/sy scale factors (the same trick used throughout this
-- codebase for anything bigger than the default ~12px, e.g. character_
-- select.lua's placeholder initials). Scaling a small rasterized glyph up
-- is blur by construction — a real Font object rasterized AT the target
-- size (love.graphics.newFont(size), LÖVE's bundled vector font) is crisp
-- instead. Cached per size so repeated fonts.get(40) calls across frames
-- don't reallocate a Font every time.

local fonts = {}
local cache = {}

-- Captured once at load time, before anything calls setFont() — every
-- OTHER screen in this port never calls setFont at all, implicitly relying
-- on this being whatever's current. A screen that does set a custom Font
-- (title_screen.lua) must restore this when it's done drawing, or every
-- screen drawn afterward silently inherits the wrong font.
fonts.default = love.graphics.getFont()

function fonts.get(size)
	local font = cache[size]
	if not font then
		font = love.graphics.newFont(size)
		cache[size] = font
	end
	return font
end

return fonts
