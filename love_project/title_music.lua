local assets = require("assets")

-- Ported from nodes/title_music.gd — promoted out of title_screen.lua into
-- its own always-on module (this port's stand-in for a Godot autoload) so
-- the theme survives screen switches instead of dying with title_screen
-- the instant the player leaves it (the exact problem the 2026-08-18 Godot
-- fix solved). love_project has no persistent autoload node to lean on, so
-- title_music.update() is driven globally from main.lua's love.update()
-- every frame instead of an autoload's own _process()/signal callback.

local title_music = {}

local source = assets.title_music
local listeners = {}
local active = false -- true from start() until stop() — distinguishes "the
-- source just naturally finished, replay it" from "stop() was called on
-- purpose, leave it stopped" when update() sees isPlaying() go false.

-- Emitted every time playback (re)starts from 0 — the initial start() AND
-- every subsequent loop-back (mirrors title_music.gd's `looped` signal).
-- Registered once, at module load — NOT per screen-enter, since this
-- module (like every require()'d module here) is a singleton that outlives
-- any single title_screen visit.
function title_music.on_loop(callback)
	table.insert(listeners, callback)
end

local function replay()
	source:stop()
	source:play()
	for _, callback in ipairs(listeners) do
		callback()
	end
end

-- Safe to call every time a screen that wants the theme running is
-- entered (fresh launch, or navigating back to the title) — always
-- (re)starts from 0, exactly like title_music.gd's own start().
function title_music.start()
	active = true
	replay()
end

function title_music.stop()
	active = false
	if source:isPlaying() then
		source:stop()
	end
end

-- Polled every frame: a plain (non-looping) Source naturally goes silent
-- when it reaches the end — replaying it here is this port's equivalent of
-- title_music.gd's `_player.finished.connect(_replay)`.
function title_music.update(dt)
	if active and not source:isPlaying() then
		replay()
	end
end

return title_music
