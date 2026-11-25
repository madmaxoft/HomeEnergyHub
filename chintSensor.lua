-- chintSensor.lua

--[[ Implements receiving measurements from the Chint sensor.
Returns the function that receives the measurement data in a loop
Usage: require("chintSensor").start()
--]]




local log = require("logger").log





--- The UDP port to listen for incoming sensor data:
local gSensorPort = 5556

--- Global flag used for terminating the listeners
local gShouldTerminate = false





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
local aggregator = require("aggregator")





-- Aggregation state
local currentBucketTs = nil
local currentData = {}





--- Commits one wide row to DB
local function commitBucket()
	if (currentBucketTs and (next(currentData) ~= nil)) then
		db.saveSingleElectricityMeasurement(currentBucketTs, currentData)
		aggregator.updateLastAggregate()
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
local function receiveLoop(aListener)
	assert(aListener ~= nil)

	-- receive loop
	while not(copas.exiting() or gShouldTerminate) do
		local msg, ip, port = aListener:receivefrom()

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

	-- Close the socket:
	aListener:close()

	log("chint", "Finished")
end




return {
	--- Starts the sensor listening
	-- Returns true on success, raises an error on failure
	start = function()
		local listener = assert(socket.udp())
		assert(listener:setsockname("*", gSensorPort))
		assert(listener:settimeout(0))
		listener = assert(copas.wrap(listener))
		log("chint", "Listening for data on UDP port %d", gSensorPort)
		copas.addnamedthread("chintSensor", function() receiveLoop(listener) end)
	end,

	stop = function()
		log("chint", "Stopping")
		gShouldTerminate = true
		local wakeupSocket = assert(socket.udp())
		wakeupSocket:sendto("SHUTDOWN", "127.0.0.1", gSensorPort)
		wakeupSocket:close()
	end,
	sensorNameMap = gSensorNameMap,
}
