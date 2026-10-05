local screen_manager = require("screen_manager")
local title_screen = require("screens.title_screen")
local title_music = require("title_music")

function love.load()
	math.randomseed(os.time())
	screen_manager.switch_to(title_screen)
end

function love.update(dt)
	-- title_music.gd is a Godot autoload (survives scene changes on its
	-- own); this port has no scene-tree lifetime to lean on, so its LÖVE
	-- equivalent is polled globally here instead of from whichever screen
	-- happens to be active.
	title_music.update(dt)
	screen_manager.update(dt)
end

function love.draw()
	screen_manager.draw()
end

function love.keypressed(key)
	screen_manager.keypressed(key)
end

function love.gamepadpressed(joystick, button)
	screen_manager.gamepadpressed(joystick, button)
end
