-- test-rawDataExportPerf.lua

--[[
This is a test for measuring the performance of various strategies to build the large rawDataExport output

Results observed:
- LuaJit is about 5 times faster in these benchmarks
- String-concat is the fastest in all three of LuaJit, Lua5.1 and ZBS
- ZBS's LuaJit is 10 times slower than OS LuaJit for some reason.
--]]





local perf = require("perf")




local tostring = tostring





-- Generate fake rawData
local N = 17000
local rawData = {}
for i = 1, N do
	rawData[i] = {
		timeStamp = i,
		powerA = i * 0.1,
		powerB = i * 0.2,
		powerC = i * 0.3,
		powerTotal = i * 0.6,
		energyA = i * 0.4,
		energyB = i * 0.5,
		energyC = i * 0.6,
		energyTotal = i * 1.5,
	}
end

-- 1. string.format
collectgarbage("collect")
local timer = perf.newTimer()
local body1 = {}
for i = 1, N do
	local r = rawData[i]
	body1[i] = string.format(
		"{ timeStamp = %s, powerA = %s, powerB = %s, powerC = %s, powerTotal = %s, energyA = %s, energyB = %s, energyC = %s, energyTotal = %s},\n",
		tostring(r.timeStamp), tostring(r.powerA), tostring(r.powerB), tostring(r.powerC), tostring(r.powerTotal),
		tostring(r.energyA), tostring(r.energyB), tostring(r.energyC), tostring(r.energyTotal)
	)
end
local s1 = table.concat(body1)
timer("string.format")
collectgarbage("collect")
timer("gc")

-- 2. string concatenation with ..
local body2 = {}
for i = 1, N do
	local r = rawData[i]
	body2[i] =
		"{ timeStamp = " .. tostring(r.timeStamp) ..
		", powerA = " .. tostring(r.powerA) ..
		", powerB = " .. tostring(r.powerB) ..
		", powerC = " .. tostring(r.powerC) ..
		", powerTotal = " .. tostring(r.powerTotal) ..
		", energyA = " .. tostring(r.energyA) ..
		", energyB = " .. tostring(r.energyB) ..
		", energyC = " .. tostring(r.energyC) ..
		", energyTotal = " .. tostring(r.energyTotal) ..
		"},\n"
end
local s2 = table.concat(body2)
timer("string-concat")
collectgarbage("collect")
timer("gc")

-- 3. per-row table.concat
local body3 = {}
for i = 1, N do
	local r = rawData[i]
	local parts = {
		"{ timeStamp = ", tostring(r.timeStamp),
		", powerA = ", tostring(r.powerA),
		", powerB = ", tostring(r.powerB),
		", powerC = ", tostring(r.powerC),
		", powerTotal = ", tostring(r.powerTotal),
		", energyA = ", tostring(r.energyA),
		", energyB = ", tostring(r.energyB),
		", energyC = ", tostring(r.energyC),
		", energyTotal = ", tostring(r.energyTotal),
		"},\n"
	}
	body3[i] = table.concat(parts)
end
local s3 = table.concat(body3)
timer("per-row table.concat")
collectgarbage("collect")
timer("gc")

-- 4. reusable inner table approach
local body4 = {}
local parts = {
	"{ timeStamp = ",
	"",
	", powerA = ",
	"",
	", powerB = ",
	"",
	", powerC = ",
	"",
	", powerTotal = ",
	"",
	", energyA = ",
	"",
	", energyB = ",
	"",
	", energyC = ",
	"",
	", energyTotal = ",
	"",
	"},\n"
} -- reusable table
for i = 1, N do
	local r = rawData[i]
	parts[2]  = tostring(r.timeStamp)
	parts[4]  = tostring(r.powerA)
	parts[6]  = tostring(r.powerB)
	parts[8]  = tostring(r.powerC)
	parts[10] = tostring(r.powerTotal)
	parts[12] = tostring(r.energyA)
	parts[14] = tostring(r.energyB)
	parts[16] = tostring(r.energyC)
	parts[18] = tostring(r.energyTotal)
	body4[i] = table.concat(parts)
end
local s4 = table.concat(body4)
timer("reusable table concat")
collectgarbage("collect")
timer("gc")

-- Verify all results are identical
assert(s1 == s2 and s2 == s3 and s3 == s4)
