-- utils.lua

--[[
Implements various utility functions used throughout the app
--]]





local socket = require("socket")
local copas = require("copas")
local ltn12 = require("ltn12")
local http = require("socket.http")





local M =
{
	shouldUseBlockingHttp = false,  -- Set to true from clients to force blocking instead of copas-enabled http
}





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





--- Returns true if the specified two tables have the same content (despite potentially being different instances)
-- Note that this is ONLY intended for simple tables only, where keys are strings or numbers,
-- and values are strings, numbers or tables
function M.areTablesSame(aTable1, aTable2)
	for k, v in pairs(aTable1) do
		local v2 = aTable2[k]
		if (type(v) ~= type(v2)) then
			if not(v2) then
				return false, tostring(k) .. ": Missing from 2nd table"
			end
			return false, tostring(k) .. ": Type mismatch"
		end
		if (type(v) == "table") then
			local areSame, msg = M.areTablesSame(v, v2)
			if not(areSame) then
				return false, tostring(k) .. "." .. msg
			end
		elseif (v ~= v2) then
			return false, tostring(k) .. ": Value mismatch"
		end
	end
	for k, v in pairs(aTable2) do
		if not(aTable1[k]) then
			return false, tostring(k) .. ": Missing from 1st table"
		end
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





--- Extracts the body from the full HTTP response (status line, headers, body)
-- Mainly used in conjunction with M.httpRequest()
function M.httpExtractBody(aFullHttpResponse)
	assert(type(aFullHttpResponse) == "string")

	return string.match(aFullHttpResponse, "^.-\r\n\r\n(.*)$")
end





--- Simple HTTP request that potentially uses Copas to avoid blocking.
-- Returns true, responseHttpCode, responseHeaders and responseBody on success.
-- On error, returns nil and error message
-- If M.shouldUseBlockingHttp is set, uses a blocking TCP socket instead of copas-enabled socket
function M.httpRequest(aUrl, aHttpVerb, aContent)
	assert(type(aUrl) == "string")
	assert(type(aHttpVerb) == "string")
	aContent = aContent or ""
	assert(type(aContent) == "string")

	local resp = {}
	local req =
	{
		url = aUrl,
		method = aHttpVerb,
		sink = ltn12.sink.table(resp),
		create = function()
			if (M.shouldUseBlockingHttp) then
				return socket.tcp()
			else
				return copas.wrap(socket.tcp())
			end
		end,
		source = ltn12.source.string(aContent),
		headers =
		{
			["Content-Length"] = tostring(#aContent),
			["Connection"] = "close"
		}
	}
	local isSuccess, responseHttpCode, responseHeaders = http.request(req)
	return isSuccess, responseHttpCode, responseHeaders, table.concat(resp)
end





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





--- Returns the data string interpreted as Lua
-- Used to load tables from strings
-- Uses a sandbox to load the data
-- Returns nil and error message on failure
function M.loadDataString(aText)
	if not(aText) then
		return nil, "nil data"
	end
	assert(type(aText) == "string")

	-- Wrap in 'return' so the chunk evaluates to a value
	local chunkText = "return " .. aText

	-- Load the string within a sandbox:
	local chunk, err
	if (_VERSION == "Lua 5.1") then
		chunk, err = loadstring(chunkText)
	else
		chunk, err = load(chunkText, "sandbox", "t", {})
	end
	if not(chunk) then
		return nil, err
	end
	if (_VERSION == "Lua 5.1") then
		setfenv(chunk, {})
	end
	local isOK, result = pcall(chunk)
	if not(isOK) then
		return nil, result
	end

	return result
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





--- Parses a "HHH:MM", "HHHMM" or "MM" string into a number of minutes
-- NOTE: "100" means "1:00", "330" means "3:30" in this parser, for user input convenience
-- Returns nil and error message on failure
function M.parseMinutes(aMinutesStr)
	if not(aMinutesStr) then
		return nil, "Invalid minutes input"
	end
	assert(type(aMinutesStr) == "string")
	if (aMinutesStr:len() > 2) then
		local hoursStr, minutesStr = aMinutesStr:match("(%d+):?(%d%d)")
		if not(hoursStr and minutesStr) then
			return nil, "Cannot parse hours and minutes"
		end
		local hours = tonumber(hoursStr)
		local minutes = tonumber(minutesStr)
		if not(hours and minutes) then
			return nil, "Cannot parse hours and minutes into numbers"
		end
		return hours * 60 + minutes
	end
	local minutes = tonumber(aMinutesStr)
	if not(minutes) then
		return nil, "Cannot parse number of minutes"
	end
	return minutes
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




--- Recursively serializes the specified table into a (dense) string
function M.serializeTable(aTable)
	assert(type(aTable) == "table")

	-- Print the table members, sorted by key:
	local res = {}
	local n = 0
	for k, v in pairs(aTable) do
		if (type(v) == "table") then
			n = n + 1
			local keyRep
			if (type(k) == "number") then
				keyRep = tostring(k)
			else
				keyRep = string.format("%q", k)
			end
			res[n] = string.format("[%s]={%s},", tostring(keyRep), M.serializeTable(v))
		else
			n = n + 1
			res[n] = string.format("%s=%s,", tostring(k), tostring(v))
		end
	end

	return table.concat(res)
end





--- Convers a timestamp to a string representation YYYY-MM-DD
function M.timeStampToYmd(aTimeStamp)
	return os.date("%Y-%m-%d", aTimeStamp)
end





return M
