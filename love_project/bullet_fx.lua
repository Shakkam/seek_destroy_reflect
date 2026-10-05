-- Decorative per-bullet particle effects shared by match_arena.lua and the
-- three mini-jeu screens (breakout/gradius/space_invaders). Purely visual and
-- stateless: every particle is recomputed each frame from the bullet itself +
-- the clock, so there is no list to spawn/cull and no gameplay effect.
-- Call draw() right AFTER drawing the bullet's own sprite.
local Vector2 = require("simulation.vector2")

local bullet_fx = {}

-- Traqueur's missiles (normal and charged shot, versus and mini-jeux alike):
-- a rocket-exhaust plume behind the tail — hot white-yellow near the nozzle,
-- orange then red-grey smoke farther back, fanning out and flickering.
local function draw_missile_plume(bullet, image)
	local scale = bullet.visual_scale or 1.0
	local speed = bullet.velocity:length()
	if speed <= 1.0 then
		return
	end
	local back = bullet.velocity * (-1.0 / speed)
	local side_dir = Vector2.new(-back.y, back.x)
	local tail = image:getWidth() * scale * 0.5
	local frame = math.floor(love.timer.getTime() * 30.0)
	for k = 0, 17 do
		local f = k / 17.0
		local h = math.sin(frame * 12.9898 + k * 78.233 + bullet.position.y * 0.01) * 43758.5453
		local jitter = (h - math.floor(h)) - 0.5
		local dist = tail + f * 70.0 * scale
		local px = bullet.position.x + back.x * dist + side_dir.x * jitter * (3.0 + f * 16.0)
		local py = bullet.position.y + back.y * dist + side_dir.y * jitter * (3.0 + f * 16.0)
		if f < 0.35 then
			love.graphics.setColor(1.0, 0.95, 0.6, 1.0)
		elseif f < 0.7 then
			love.graphics.setColor(1.0, 0.55, 0.15, 0.95)
		else
			love.graphics.setColor(0.7, 0.45, 0.35, 0.7 * (1.0 - f) / 0.3)
		end
		love.graphics.circle("fill", px, py, (6.5 - 3.5 * f) * (0.7 + 0.3 * scale))
	end
	love.graphics.setColor(1, 1, 1)
end

-- Spreader's Ultra "Pluie de Bonbons": the falling fans spin very fast, so
-- faint yellow motes trail behind the blades along the spin (plus a ring and
-- a short wake above) to make that speed readable.
local function draw_fan_motes(bullet, image)
	local scale = bullet.visual_scale or 1.0
	local r = math.max(image:getWidth(), image:getHeight()) * scale * 0.5
	for k = 1, 16 do
		local ang = (bullet.rotation or 0.0) - k * 0.28
		local rr = r * (0.55 + 0.6 * ((k * 5) % 4) / 4.0)
		love.graphics.setColor(1.0, 0.95, 0.3, 0.75 * (1.0 - k / 17.0))
		love.graphics.circle("fill", bullet.position.x + math.cos(ang) * rr, bullet.position.y + math.sin(ang) * rr, 4.5 - k * 0.2)
	end
	love.graphics.setColor(1.0, 0.95, 0.4, 0.4)
	love.graphics.setLineWidth(2.0)
	love.graphics.circle("line", bullet.position.x, bullet.position.y, r * 0.95)
	for k = 1, 6 do
		love.graphics.setColor(1.0, 0.95, 0.35, 0.5 * (1.0 - k / 7.0))
		love.graphics.circle("fill", bullet.position.x + math.sin((bullet.rotation or 0.0) * 3.0 + k) * r * 0.5, bullet.position.y - k * r * 0.55, 4.0 - k * 0.4)
	end
	love.graphics.setLineWidth(1.0)
	love.graphics.setColor(1, 1, 1)
end

function bullet_fx.draw(bullet, image)
	if bullet.weapon_id == "ultra_pluie_de_bonbons" then
		draw_fan_motes(bullet, image)
	elseif bullet.weapon_id == "ultra_la_meute" or bullet.weapon_id == "homing_missile" then
		draw_missile_plume(bullet, image)
	end
end

return bullet_fx
