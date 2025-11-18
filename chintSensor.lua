-- chintSensor.lua

--[[ Implements receiving measurements from the Chint sensor.
Returns the function that receives the measurement data in a loop
Usage: copas.addthread(require("chintSensor"))
--]]




--- The UDP port to listen for incoming sensor data:
local gSensorPort = 5556





--- Maps the incoming sensor names into DB sensor names
local gSensorNameMap =
{
	chint_positive_total_active_energy = "energyTotal",
	chint_positive_active_energy_A     = "energyA",
	chint_positive_active_energy_B     = "energyB",
	chint_positive_active_energy_C     = "energyC",
	chint_combined_active_power = "powerTotal",
	chint_active_power_A        = "powerA",
	chint_active_power_B        = "powerB",
	chint_active_power_C        = "powerC",
}





local db = require("db")
local socket = require("socket")
local copas = require("copas")





-- Aggregation state
local currentBucketTs = nil
local currentData = {}





--- Commits one wide row to DB
local function commitBucket()
	if (currentBucketTs and (next(currentData) ~= nil)) then
		db.saveSingleElectricityMeasurement(currentBucketTs, currentData)
	end
end





--- Processes one incoming measurement - aggregates into 5-second buckets
local function processMeasurement(aSensorName, aSensorValue)
	local now = os.time()
	local bucketTs = now - (now % 5)
	if (not(currentBucketTs) or (bucketTs ~= currentBucketTs)) then
		commitBucket()
		currentBucketTs = bucketTs
		currentData = {}
	end
	local dbField = gSensorNameMap[aSensorName]
	if (dbField) then
		currentData[dbField] = aSensorValue
	end
end





--- Receives incoming measurements from the Chint sensor
-- Assumes it is run from a separate copas thread
local function receiveLoop()
	-- UDP listener setup
	local listener = socket.udp()
	listener:setsockname("*", gSensorPort)
	listener:settimeout(0)
	listener = copas.wrap(listener)
	print("[chint] Listening for data on UDP port " .. gSensorPort)

	-- receive loop
	while not(copas.exiting()) do
		local msg, ip, port = listener:receivefrom()

		if (msg) then
			if (
				(#msg > 3) and
				(msg:sub(1, 2) == "SU") and
				(msg:byte(3) == 0)
			) then
				local payload = msg:sub(4)
				local sensorName, sensorValueStr = payload:match("([^\t]*)\t(.*)")

				if (sensorName and sensorValueStr) then
					local sensorValue = tonumber(sensorValueStr)
					if (sensorValue) then
						processMeasurement(sensorName, sensorValue)
					end
				end
			end
		end
	end

	-- flush on exit
	commitBucket()
	print("[chint] Finished")
end




return {
	start = function()
		copas.addthread(receiveLoop)
	end,
	sensorNameMap = gSensorNameMap,
}
