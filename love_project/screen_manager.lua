-- Tiny screen/state-machine manager (see the port spec, section 3): each
-- screen is a Lua module exposing enter(...)/update(dt)/draw()/
-- keypressed(key). love.update/love.draw/love.keypressed in main.lua only
-- ever delegate to whichever screen is current — LÖVE's stand-in for
-- Godot's scene tree + change_scene_to_file().

local screen_manager = {}

local current_screen = nil

function screen_manager.switch_to(screen, ...)
	current_screen = screen
	if current_screen.enter then
		current_screen.enter(...)
	end
end

function screen_manager.update(dt)
	if current_screen and current_screen.update then
		current_screen.update(dt)
	end
end

function screen_manager.draw()
	if current_screen and current_screen.draw then
		current_screen.draw()
	end
end

function screen_manager.keypressed(key)
	if current_screen and current_screen.keypressed then
		current_screen.keypressed(key)
	end
end

-- 2026-09-27 (Camil: "il faut pouvoir jouer avec des manettes") — every
-- screen's own keypressed(key) only ever handles "escape" (and a couple of
-- dev-cheat letters) — there is no separate gamepad-menu-navigation system
-- to build here. Translating the gamepad's "B" button into the same
-- "escape" keypress every screen already understands covers back/cancel
-- everywhere with no per-screen changes at all.
function screen_manager.gamepadpressed(joystick, button)
	if not (current_screen and current_screen.keypressed) then
		return
	end
	if button == "b" then
		current_screen.keypressed("escape")
	elseif button == "a" then
		-- The one keypressed() handler that reacts to "space"/"return"
		-- (match_arena.lua's campaign match-over continue prompt) — every
		-- other discrete menu action in this project is polled, not
		-- keypressed-based, so this single translation is a safe, generic
		-- gamepad-confirm without risking a misfire anywhere else.
		current_screen.keypressed("space")
	end
end

return screen_manager
