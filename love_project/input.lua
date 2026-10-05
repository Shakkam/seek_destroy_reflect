-- Gamepad support (2026-09-27, Camil: "il faut pouvoir jouer avec des
-- manettes"). Nothing in this project reads love.joystick.* anywhere else —
-- this module is the one place that does, so every screen goes through it
-- instead of hand-rolling its own love.joystick calls.
--
-- Two usage shapes:
--   - "solo" helpers (menus, the campaign map, the solo mini-jeux): always
--     read keyboard OR the FIRST connected gamepad (device 1) — there's
--     only ever one person driving these screens.
--   - `input.is_down(binding, joystick)` for the 2-player screens
--     (character_select.lua/match_arena.lua), which already have their own
--     P1_CONTROLS/P2_CONTROLS tables keyed by scancode(s) — `binding` is
--     exactly one of those table entries (a scancode string, or a list of
--     scancode strings) plus an optional `button` field naming the gamepad
--     button, and `joystick` is THAT player's own device (see
--     input.get_joystick()).

local input = {}

local DEADZONE = 0.5

function input.get_joystick(player_index)
	return love.joystick.getJoysticks()[player_index]
end

-- True if `scancodes` (a single scancode string, or an array of them) is
-- currently held on the keyboard.
local function keyboard_down(scancodes)
	if scancodes == nil then
		return false
	end
	if type(scancodes) == "string" then
		return love.keyboard.isScancodeDown(scancodes)
	end
	for _, sc in ipairs(scancodes) do
		if love.keyboard.isScancodeDown(sc) then
			return true
		end
	end
	return false
end

-- True if `buttons` (a single SDL gamepad button name, or an array of them)
-- is currently held on `joystick`. Wrapped in a nil-safe check — a
-- disconnected/absent joystick just reads as "nothing held", never an error.
local function gamepad_button_down(joystick, buttons)
	if joystick == nil or buttons == nil or not joystick:isConnected() then
		return false
	end
	if type(buttons) == "string" then
		return joystick:isGamepadDown(buttons)
	end
	for _, b in ipairs(buttons) do
		if joystick:isGamepadDown(b) then
			return true
		end
	end
	return false
end

-- Public one-off gamepad button check (a single button name, or a list of
-- them) — for call sites that just want "is this button held on this
-- player's device", without going through a whole CONTROLS-table binding.
input.button_down = gamepad_button_down

-- Left-stick deflection past DEADZONE in the given direction, as a
-- fallback/complement to the D-pad for movement.
local function stick_direction_down(joystick, direction)
	if joystick == nil or not joystick:isConnected() then
		return false
	end
	if direction == "up" then
		return joystick:getGamepadAxis("lefty") < -DEADZONE
	elseif direction == "down" then
		return joystick:getGamepadAxis("lefty") > DEADZONE
	elseif direction == "left" then
		return joystick:getGamepadAxis("leftx") < -DEADZONE
	elseif direction == "right" then
		return joystick:getGamepadAxis("leftx") > DEADZONE
	end
	return false
end

local DPAD_BUTTON_BY_DIRECTION = { up = "dpup", down = "dpdown", left = "dpleft", right = "dpright" }

-- D-pad OR left stick, either one held counts.
function input.direction_down(joystick, direction)
	return gamepad_button_down(joystick, DPAD_BUTTON_BY_DIRECTION[direction]) or stick_direction_down(joystick, direction)
end

-- Generic check for a 2-player CONTROLS-table entry: `binding.keys` (a
-- scancode or list, matching every existing CONTROLS table's own shape)
-- OR `binding.button` (a gamepad button name or list) on `joystick`.
function input.is_down(binding, joystick)
	if binding == nil then
		return false
	end
	return keyboard_down(binding.keys) or gamepad_button_down(joystick, binding.button)
end

-- ---- Solo helpers: keyboard + the first connected gamepad (device 1) ----

function input.solo_up()
	return love.keyboard.isScancodeDown("w") or love.keyboard.isScancodeDown("up") or input.direction_down(input.get_joystick(1), "up")
end

function input.solo_down()
	return love.keyboard.isScancodeDown("s") or love.keyboard.isScancodeDown("down") or input.direction_down(input.get_joystick(1), "down")
end

function input.solo_left()
	return love.keyboard.isScancodeDown("a") or love.keyboard.isScancodeDown("left") or input.direction_down(input.get_joystick(1), "left")
end

function input.solo_right()
	return love.keyboard.isScancodeDown("d") or love.keyboard.isScancodeDown("right") or input.direction_down(input.get_joystick(1), "right")
end

function input.solo_confirm()
	return love.keyboard.isScancodeDown("space") or love.keyboard.isScancodeDown("return") or gamepad_button_down(input.get_joystick(1), "a")
end

function input.solo_escape()
	return love.keyboard.isScancodeDown("escape") or gamepad_button_down(input.get_joystick(1), "b")
end

function input.solo_fire()
	return love.keyboard.isScancodeDown("space") or gamepad_button_down(input.get_joystick(1), { "a", "x" })
end

function input.solo_lift()
	return love.keyboard.isScancodeDown("lshift") or love.keyboard.isScancodeDown("rshift") or gamepad_button_down(input.get_joystick(1), { "leftshoulder", "rightshoulder" })
end

return input
