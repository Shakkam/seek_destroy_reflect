-- Small shared drawing helpers for the real-art pass (Phase 7). Not part
-- of simulation/ (this is pure rendering) and not worth threading through
-- every screen's own copy — a handful of one-line wrappers around
-- love.graphics.draw, safe to share.

local draw_utils = {}

-- Draws `image` centered at (x, y), stretched (non-uniformly, if needed)
-- to exactly fill a target_w x target_h box — matches the footprint a
-- collision half_extents box already has, which is what ships/turrets
-- need (the hitbox is the source of truth, the sprite just fills it).
function draw_utils.draw_stretched(image, x, y, target_w, target_h, flip_h, rotation)
	local iw, ih = image:getDimensions()
	local sx = target_w / iw
	local sy = target_h / ih
	if flip_h then
		sx = -sx
	end
	love.graphics.draw(image, x, y, rotation or 0.0, sx, sy, iw / 2.0, ih / 2.0)
end

-- Draws `image` centered at (x, y) at its own native size times a uniform
-- `scale` factor — the pattern used for the ball and every weapon
-- projectile in the Godot source (BALL_SPRITE_SCALE, ProjectileNode's
-- visual_scale): art size is an independent art-direction knob, not tied
-- to the physics hitbox the way ships/turrets are.
function draw_utils.draw_scaled(image, x, y, scale, flip_h, rotation)
	local iw, ih = image:getDimensions()
	local sx = flip_h and -scale or scale
	love.graphics.draw(image, x, y, rotation or 0.0, sx, scale, iw / 2.0, ih / 2.0)
end

-- Covers a box of size (box_w, box_h) top-left at (x, y) with `image`,
-- PRESERVING aspect ratio (scaled up until it fills the box on both axes,
-- overflow cropped, centered) — mirrors a Godot TextureRect with
-- stretch_mode = STRETCH_KEEP_ASPECT_COVERED + expand_mode = EXPAND_IGNORE_
-- SIZE, which is exactly how MatchArena.tscn's real Background art is set
-- up. Used for the arena background, which resizes live with the
-- shrinking_arena/drifting_neutral_zone twists.
function draw_utils.draw_cover(image, x, y, box_w, box_h)
	local iw, ih = image:getDimensions()
	local scale = math.max(box_w / iw, box_h / ih)
	local draw_w, draw_h = iw * scale, ih * scale
	local draw_x = x + (box_w - draw_w) / 2.0
	local draw_y = y + (box_h - draw_h) / 2.0
	love.graphics.setScissor(x, y, box_w, box_h)
	love.graphics.draw(image, draw_x, draw_y, 0.0, scale, scale)
	love.graphics.setScissor()
end

-- Fits `image` inside a box of size (box_w, box_h) top-left at (x, y),
-- PRESERVING aspect ratio and centering within the box, with `inset` px
-- of margin — mirrors character_select_node.gd's own _draw_texture_fit(),
-- used for portrait/full-body art where stretching would look wrong.
function draw_utils.draw_fit_inside(image, x, y, box_w, box_h, inset)
	inset = inset or 0.0
	local iw, ih = image:getDimensions()
	local avail_w, avail_h = box_w - inset * 2.0, box_h - inset * 2.0
	local scale = math.min(avail_w / iw, avail_h / ih)
	local draw_w, draw_h = iw * scale, ih * scale
	local draw_x = x + inset + (avail_w - draw_w) / 2.0
	local draw_y = y + inset + (avail_h - draw_h) / 2.0
	love.graphics.draw(image, draw_x, draw_y, 0.0, scale, scale)
end

return draw_utils
