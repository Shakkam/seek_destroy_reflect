-- Minimal homemade timer utility (see the port spec, section 3 & 7 —
-- "Decision a prendre avec l'ami: lib tierce [flux/hump.timer] ou fait-
-- main". This Phase 2 shell picks the homemade option to validate the
-- pattern with zero new dependencies. Swappable for hump.timer later
-- without touching callers, since the call surface (after/update) is
-- deliberately tiny.
--
-- NOT part of simulation/ — this reads wall-clock dt from love.update(),
-- which simulation/ code must never do (project-context.md, Regle absolue
-- n1). Lives at the LÖVE-integration layer, same tier as screen_manager.lua.

local timer = {}

local pending = {}

function timer.after(seconds, callback)
	table.insert(pending, { remaining = seconds, callback = callback })
end

function timer.update(dt)
	local i = 1
	while i <= #pending do
		local entry = pending[i]
		entry.remaining = entry.remaining - dt
		if entry.remaining <= 0.0 then
			table.remove(pending, i)
			entry.callback()
		else
			i = i + 1
		end
	end
end

function timer.clear()
	pending = {}
end

return timer
