-- test-savings.lua

--[[
Implements tests for the functions in the savings handler.
The tests run in a single-threaded environment that is easier to debug.
--]]





local savings = require("Handlers.savings")





local function testEnergyStatusCalc()
	local week = {}
	local tsDay1 = 86400
	for i = 1, 7 do
		week[i] = { timeStamp = tsDay1 + (i - 1) * 86400, energyTotal = i * 100, }
	end
	week.n = 7
	assert(savings.energyStatusAt(week, tsDay1 - 100) == 100)  -- Pre-data: return the earliest value
	assert(savings.energyStatusAt(week, tsDay1) == 100)  -- At the data start
	assert(savings.energyStatusAt(week, tsDay1 + 86400) == 200)  -- At an exact data point
	assert(savings.energyStatusAt(week, tsDay1 + 43200) == 150)  -- In between two data points
	assert(savings.energyStatusAt(week, tsDay1 + 6 * 86400) == 700)  -- At the data end
	for i = 1, 7 do
		local reported = savings.energyStatusAt(week, tsDay1 + (i - 1) * 86400)
		local expected = i * 100
		assert(reported == expected, string.format("Failed an exact match for day %d, exp %f, got %f", i, expected, reported))
	end
	assert(savings.energyStatusAt(week, tsDay1 + 6 * 86400) == 700)  -- At the data end
	assert(savings.energyStatusAt(week, tsDay1 + 6 * 86401) == 700)  -- Beyond the data end
end





testEnergyStatusCalc()
