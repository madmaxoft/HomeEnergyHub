-- remoteMetersImport.lua

--[[
Imports data from a remote server running remoteMetersServer.lua

Usage:
	lua remoteMetersImport.lua <remoteHost[:port]> [<startTimeStamp> [<endTimeStamp>] ]
Imports the remote data starting at startTimeStamp and ending at endTimeStamp.
Timestamps may be specified as unixtime integers, as ISO YYYY-MM-DD hh:mm::ss strings or as offset in
days ("2d") or hours ("48h") from now.
Needs to be run from the main app folder, since it loads app components.
--]]





local socket = require("socket")
local lzlib = require("zlib")
local db = require("db")
local utils = require("utils")




--- The timestamp of the bucket currently being processed
local gCurrentBucketTs = nil

--- The current bucket being accumulated
local gCurrentData = {}

--- Statistics: Total number of committed buckets
local gNumCommittedBuckets = 0

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

--- The total number of lines that we received from the remote and processed
local gTotalLinesProcessed = 0





--- Prints the formatted string
local function printStr(aFormat, ...)
	print(string.format(aFormat, ...))
end





--- Commits one wide row to DB
local function commitBucket()
	if (gCurrentBucketTs and (next(gCurrentData) ~= nil)) then
		db.saveSingleElectricityMeasurement(gCurrentBucketTs, gCurrentData)
		gNumCommittedBuckets = gNumCommittedBuckets + 1
	end
end





--- Processes one incoming measurement - aggregates into 5-second buckets
local function addMeasurement(aTimeStamp, aSensorName, aSensorValue)
	local bucketTs = aTimeStamp - (aTimeStamp % 5)
	if (not(gCurrentBucketTs) or (bucketTs ~= gCurrentBucketTs)) then
		commitBucket()
		gCurrentBucketTs = bucketTs
		gCurrentData = {}
	end
	local dbField = gSensorNameMap[aSensorName]
	if (dbField) then
		gCurrentData[dbField] = aSensorValue
	end
end





--- Returns the remote host and port parsed from the specified string
-- If there's no port specified, returns the default port
local function parseRemote(aRemoteStr)
	assert(type(aRemoteStr) == "string")

	local host, port = aRemoteStr:match("(.+):(%d+)")
	if not(host and port) then
		return aRemoteStr, 5501
	end
	port = assert(tonumber(port))
	return host, port
end





--- Parses the offset string (given as parameter to the script) and returns the number of seconds representing the offset
-- Raises an error if parsing fails
local function parseOffset(aOffsetStr)
	assert(type(aOffsetStr) == "string")

	local num, units = aOffsetStr:match("(%d+)([hHdD])")
	if not(num and units) then
		error("Failed to parse offset from \"".. aOffsetStr .. "\".")
	end
	num = assert(tonumber(num))
	local multiplier = ((units == "d") or (units == "D")) and (24 * 60 * 60) or (60 * 60)
	return num * multiplier
end





--- Processes the response to a single "data" response
-- aSocket is the client socket that has just read the "data" header.
local function processDataResponse(aSocket)
	assert(aSocket ~= nil)
	assert(aSocket.receive ~= nil)

	-- Read the data length header:
	local len, msg = aSocket:receive("*l")
	if not(len) then
		error("Failed to receive data length: " .. tostring(msg))
	end
	len = assert(tonumber(len))

	-- Read and decompress the data:
	local rawData, msg = aSocket:receive(tonumber(len))
	if not(rawData) then
		error("Failed to receive raw data: " .. tostring(msg))
	end
	printStr("Received %d bytes of remote data", string.len(rawData))
	local inflatedData = assert(lzlib.inflate()(rawData))

	-- Process each line in the decompressed data:
	local lastTimestamp
	for line in string.gmatch(inflatedData, "[^\n]+") do
		gTotalLinesProcessed = gTotalLinesProcessed + 1
		local timestamp, sensorName, sensorValue = line:match("^(%d+)\t([^\t]+)\t([^\t]+)$")
		timestamp = tonumber(timestamp)
		sensorValue = tonumber(sensorValue)
		assert(timestamp, "Invalid data line: " .. line)
		addMeasurement(timestamp, sensorName, sensorValue)
		lastTimestamp = timestamp
	end
	if (lastTimestamp ~= nil) then
		printStr(
			"Last timestamp processed in this batch: %d (%s)",
			lastTimestamp, os.date("!%Y-%m-%d %H:%M:%S", lastTimestamp)
		)
	end
end





--- Imports the data from the remote host
local function importFromRemote(aRemoteHost, aRemotePort, aStartTS, aEndTS)
	assert(type(aRemoteHost) == "string")
	assert(type(aRemotePort) == "number")
	assert(type(aStartTS) == "number")
	assert(type(aEndTS) == "number")

	printStr("Importing from host %s, port %d, range %d .. %d (%s .. %s)",
		aRemoteHost, aRemotePort,
		aStartTS, aEndTS,
		os.date("!%Y-%m-%d %H:%M:%S", aStartTS), os.date("!%Y-%m-%d %H:%M:%S", aEndTS)
	)

	-- Connect to the remote server:
	local skt = assert(socket.tcp())
	skt:settimeout(3)
	assert(skt:connect(aRemoteHost, aRemotePort))
	local handshake = assert(skt:receive("*l"))
	if not(handshake == "remoteMetersServer") then
		error("Remote is not a remoteMetersServer, handshake failed: " .. tostring(handshake))
	end
	skt:send("remoteMetersClient\r\n")

	-- Request the range:
	skt:send(string.format("export\r\n%d\r\n%d\r\n", aStartTS, aEndTS))

	-- Read the response:
	while (true) do
		local resp, msg = skt:receive("*l")
		if not(resp) then
			error("Failed to receive response: " .. tostring(msg))
		end
		if (resp == "data") then
			db.withinTransaction(function()
				processDataResponse(skt)
			end)
		elseif (resp == "finished") then
			return
		else
			error("Received an unknown response: " .. tostring(resp))
		end
	end
end





--- Main entrypoint:
local args = {...}
local remoteHost, remotePort = parseRemote(args[1] or "localhost:5551")
local startTS = utils.parseTimeStamp(args[2] or "5d")
local endTS = utils.parseTimeStamp(args[3] or "0h")

importFromRemote(remoteHost, remotePort, startTS, endTS)

printStr("Finished, committed %d buckets, processed %d data lines", gNumCommittedBuckets, gTotalLinesProcessed)
