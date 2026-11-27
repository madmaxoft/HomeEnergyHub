-- remoteMetersServer.lua

--[[
Implements a small single-client TCP server that provides network access to a local Meters DB
(the narrow-long DB of timestamp-sensorname-value).

It is particularly useful for incremental remote import over a slow network connection

The protocol used is simple line-based protocol. The base structure is this:
Handshake:
	S->C: "remoteMetersServer\r\n"
	C->S: "remoteMetersClient\r\n"
Command loop:
	C->S: "<command>\r\n<optionalData>"
	S->C: "<response>\r\n<optionalData>"

<command> can be "export" or "shutdown". For "export", the optionalData are two lines, each containing
the timestamp of the range to export.
<response> depends on the command. For "export" command, the server replies with several "data" responses,
each contains in optionalData a line with a number - the number of raw bytes following that response, then
the raw data. The raw data is deflated export string in the format "<timestamp>\r\n<sensorname>\r\n<value>\r\n..."
After the last "data" response the server sends a "finished" response with no optionalData to signal that
there is no more export data.


Usage:
	lua /path/to/remoteMetersServer.lua /path/to/Meters.sqlite 12345
		-- or --
	ssh -L 12345:127.0.0.1:12345 remote-host 'lua /path/to/remoteMetersServer.lua /path/to/Meters.sqlite 12345'
		-- and then import locally --
	lua remoteMetersImport.lua 2d
--]]




local sqlite = require("lsqlite3")
local socket = require("socket")
local lzlib = require("zlib")

local args = {...}
local gDBFileName = args[1] or "Meters.sqlite"
local gPort = args[2] or 5551
local gShouldTerminate = false

--- List of sensor names we're actually interested in. Sensors not on this list are not sent.
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




--- Prints the formatted string
local function printStr(aFormat, ...)
	print(string.format(aFormat, ...))
end





local function handleExport(aSocket)
	assert(aSocket ~= nil)
	assert(aSocket.receive ~= nil)

	-- Read the requested range:
	local tsStart, msg = aSocket:receive("*l")
	tsStart = tonumber(tsStart)
	if not(tsStart) then
		printStr("Failed to read start timestamp: %s", tostring(msg))
		aSocket:close()
		return
	end
	local tsEnd, msg = aSocket:receive("*l")
	tsEnd = tonumber(tsEnd)
	if not(tsEnd) then
		printStr("Failed to read end timestamp: %s", tostring(msg))
		aSocket:close()
		return
	end
	printStr(
		"Exporting range %d .. %d (%s .. %s)",
		tsStart, tsEnd,
		os.date("!%Y-%m-%d %H:%M:%S", tsStart), os.date("!%Y-%m-%d %H:%M:%S", tsEnd)
	)

	-- Export the rows:
	while (tsStart < tsEnd) do
		printStr(
			"Querying range %d .. %d (%s .. %s)",
			tsStart, tsEnd,
			os.date("!%Y-%m-%d %H:%M:%S", tsStart), os.date("!%Y-%m-%d %H:%M:%S", tsEnd)
		)
		-- Query the data from the DB, build the data string:
		local stmt, msg, msg2 = gDB:prepare("SELECT * FROM MeterData WHERE (timestamp >= ?) AND (timestamp < ?) ORDER BY timestamp LIMIT 10000")
		if not(stmt) then
			printStr("DB statement creation failed: %s / %s / %s", tostring(msg), tostring(msg2), gDB:errmsg())
			aSocket:close();
			return
		end

		if (stmt:bind_values(tsStart, tsEnd) ~= sqlite.OK) then
			printStr("DB statement bind failed: %s", gDB: errmsg())
			aSocket:close()
			return
		end
		local n = 0
		local rows = {}
		local data = ""
		local totalNum = 0
		local numIgnored = 0
		for row in stmt:nrows() do
			totalNum = totalNum + 1
			if (gSensorNameMap[row.SensorName]) then
				n = n + 1
				rows[n] = tostring(row.Timestamp) .. "\t" .. row.SensorName .. "\t" .. tostring(row.SensorValue)
				if (n == 100) then
					data = data .. table.concat(rows, "\n") .. "\n"
					n = 0
				end
			else
				numIgnored = numIgnored + 1
			end
			if (tonumber(row.Timestamp) > tsStart) then
				tsStart = row.Timestamp
			end
		end
		if (n > 0) then
			data = data .. table.concat(rows, "\n", 1, n)
		end
		stmt:finalize()
		printStr("Out of %d rows, %d were ignored", totalNum, numIgnored)

		-- If no more data, send the "finished" response:
		if (data == "") then
			aSocket:send("finished\r\n")
			printStr("Export finished, sent %d data rows", totalNum)
			return
		end

		-- Send the data chunk:
		local deflated = lzlib.deflate(zlib.BEST_COMPRESSION, 15)(data, "finish")
		if not(aSocket:send(string.format("data\r\n%d\r\n", string.len(deflated)))) then
			return
		end
		if not(aSocket:send(deflated)) then
			return
		end

		-- If the total number of rows is fewer than 10k, we've just read all there was in the DB:
		if (totalNum < 10000) then
			printStr("Processed only %d rows out of 10000, assuming finished.", totalNum)
			aSocket:send("finished\r\n")
			return
		end
	end
	aSocket:send("finished\r\n")
	printStr("Export finished	, sent %d data rows", totalNum)
end





--- Reads requests from the specified socket, sends responses
local function serveClient(aSocket)
	assert(aSocket ~= nil)
	assert(aSocket.getpeername ~= nil)

	-- Handshake:
	printStr("New connection from %s:%d, handshaking", aSocket:getpeername())
	aSocket:send("remoteMetersServer\r\n")
	local clientHello = aSocket:receive("*l")
	if (clientHello ~= "remoteMetersClient") then
		aSocket:close()
		printStr("Connection closed: client hello doesn't match (got %s)", clientHello)
		return
	end

	-- Command parser loop:
	printStr("Handshake complete, listening for commands")
	while (true) do
		local cmd, msg = aSocket:receive("*l")
		if not(cmd) then
			printStr("Socket disconnected: %s", tostring(msg))
			aSocket:close()
			return
		elseif (cmd == "export") then
			handleExport(aSocket)
		elseif (cmd == "shutdown") then
			gShouldTerminate = true
			aSocket:close()
			return
		end
	end
	aSocket:close()
end





-- Open the DB:
gDB = assert(sqlite.open(gDBFileName, sqlite.OPEN_READONLY))
gDB:busy_timeout(3000)

-- Start the server:
local serverSocket = assert(socket.bind("*", gPort))
printStr("Server listening on port %d", gPort)

-- Main loop:
while not(gShouldTerminate) do
	local client = serverSocket:accept()
	client:settimeout(5)
	if (client) then
		serveClient(client)
	end
end
