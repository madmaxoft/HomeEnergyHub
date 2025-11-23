-- utils.lua

--[[
Implements various utility functions used throughout the app
--]]





local M = {}





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
