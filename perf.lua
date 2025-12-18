-- perf.lua

--[[
Implements helper functions for measuring performance.

Timer usage:
local timer = perf.newTimer("timerName")
op1()
timer("op1")
op2()
timer("op2")
--]]





local socket = require("socket")





local M =
{
	isTimerSilenced = {}  -- Dict table of timerName -> true for all timers that should not produce any output
}





--- Creates a new timer (a function that reports the elapsed time upon each subsequent call)
-- The name is used for silencing timers across the app globally in runtime
function M.newTimer(aName)
	-- If the timer is disabled, return an empty timer
	if (M.isTimerSilenced[aName]) then
		return function() end
	end

	local t0 = socket.gettime()
	local last = t0

	return function(aLabel)
		local now = socket.gettime()
		local delta = (now - last) * 1000
		local total = (now - t0) * 1000
		last = now

		if (aLabel) then
			print(string.format(
				"[perf] %-50s %+7.2f ms (total %7.2f ms)",
				aLabel, delta, total
			))
		end
	end
end




function M.silenceTimer(aName)
	M.isTimerSilenced[aName] = true
end





function M.unsilenceTimer(aName)
	M.isTimerSilenced[aName] = false
end





return M
