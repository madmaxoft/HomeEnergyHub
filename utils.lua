-- utils.lua

--[[
Implements various utility functions used throughout the app
--]]





local M = {}





--- Dict-table of month -> max valid day number
local gMaxMonthDay =
{
	31,
	29,
	31,
	30,
	31,
	30,
	31,
	31,
	30,
	31,
	30,
	31,
}





--- Returns whether the specified year is a leap year
function M.isLeapYear(aYear)
	if ((aYear % 4) ~= 0) then
		return false
	end
	if ((aYear % 100) == 0) then
		return ((aYear % 400) == 0)
	end
	return true
end





--- Returns true if the specified YMD combination is a valid date
function M.isValidYmd(aYear, aMonth, aDay)
	assert(type(aYear) == "number")
	assert(type(aMonth) == "number")
	assert(type(aDay) == "number")
	if (
		(aYear < 1971) or (aYear > 10000) or
		(aMonth < 1) or (aMonth > 12) or
		(aDay < 1) or (aDay > gMaxMonthDay[aMonth]) or
		((aMonth == 2) and (aDay == 29) and not(M.isLeapYear(aYear)))
	) then
		return false
	end
	return true
end





--- Returns true if the specified date string is a valid YYYY-MM-DD date representation
function M.checkYmdDate(aDateStr)
	assert(type(aDateStr) == "string")

	local y, m, d = string.match(aDateStr, "(%d+)%-(%d+)%-(%d+)")
	if not(y and m and d) then
		return nil, "Cannot parse the YMD string"
	end
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not(y and m and d) then
		return nil, "Cannot convert YMD to numbers"
	end
	if not(M.isValidYmd(y, m, d)) then
		return nil, "YMD out of range"
	end
	return true
end





--- Returns the YMD representation of the day following the specified date.
-- Returns nil and optional error message if the specified date is not valid
function M.nextDayYmd(aDateStr)
	assert(type(aDateStr) == "string")

	-- Parse and check:
	local y, m, d = string.match(aDateStr, "(%d+)%-(%d+)%-(%d+)")
	if not(y and m and d) then
		return nil, "Cannot parse the YMD string"
	end
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not(y and m and d) then
		return nil, "Cannot convert YMD to numbers"
	end
	if not(M.isValidYmd(y, m, d)) then
		return nil, "YMD out of range"
	end

	-- Calculate:
	if (
		(d == gMaxMonthDay[m]) or  -- Last day of the month
		((m == 2) and (d == 28) and not(M.isLeapYear(y)))  -- Last February of a non-leap year
	) then
		if (m == 12) then
			return string.format("%d-01-01", y + 1)
		end
		return string.format("%d-%02d-01", y, m + 1)
	end
	return string.format("%d-%02d-%02d", y, m, d + 1)
end





--- Returns the YMD representation of the day preceding the specified date.
-- Returns nil and optional error message if the specified date is not valid
function M.prevDayYmd(aDateStr)
	assert(type(aDateStr) == "string")

	-- Parse and check:
	local y, m, d = string.match(aDateStr, "(%d+)%-(%d+)%-(%d+)")
	if not(y and m and d) then
		return nil, "Cannot parse the YMD string"
	end
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not(y and m and d) then
		return nil, "Cannot convert YMD to numbers"
	end
	if not(M.isValidYmd(y, m, d)) then
		return nil, "YMD out of range"
	end

	-- Calculate:
	if (d > 1) then
		return string.format("%d-%02d-%02d", y, m, d - 1)
	end
	if (m == 1) then
		return string.format("%d-12-31", y - 1)
	end
	-- Rollover to the previous month's last day:
	if (m == 3) then
		if (M.isLeapYear(y)) then
			return string.format("%d-02-29", y)
		end
		return string.format("%d-02-28", y)
	end
	return string.format("%d-%02d-%02d", y, m - 1, gMaxMonthDay[m - 1])
end





--- Recursively prints the specified table
function M.printTable(aTable, aIndent)
	assert(type(aTable) == "table")
	aIndent = aIndent or ""
	assert(type(aIndent) == "string")

	-- Gather all keys for sorting:
	local keys = {}
	local n = 0
	for k, v in pairs(aTable) do
		n = n + 1
		keys[n] = k
	end
	table.sort(keys, function (aKey1, aKey2)
		local tk1 = type(aKey1)
		local tk2 = type(aKey2)
		if (tk1 == "number") then
			if (tk2 == "number") then
				return (aKey1 < aKey2)
			end
			return true  -- Numbers are smaller than anything else
		end
		if (tk2 == "number") then
			return false  -- Numbers are smaller than anything else
		end
		return (tostring(aKey1) < tostring(aKey2))
	end)

	-- Print the table members, sorted by key:
	for _, k in ipairs(keys) do
		local v = aTable[k]
		if (type(v) == "table") then
			print(string.format("%s%s = {", aIndent, tostring(k)))
			M.printTable(v, aIndent .. "  ")
			print(string.format("%s},", aIndent))
		elseif (type(v) == "number") then
			print(string.format("%s%s = %s,  -- %s", aIndent, tostring(k), tostring(v), os.date("%Y-%m-%d %H:%M:%S", v)))
		else
			print(string.format("%s%s = %s,", aIndent, tostring(k), tostring(v)))
		end
	end
end




return M
