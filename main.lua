-- main.lua

-- Implements the main app entrypoint





--- Same as Lua's built-in require, but on failure reports to the user a help string
-- containing the specified LuaRocks' rock name to install
local function requireWithHelp(aModuleName, aLuaRocksRockName)
	assert(type(aModuleName) == "string")

	-- Attempt to load the module:
	local isSuccess, m = pcall(require, aModuleName)
	if (isSuccess) then
		return m
	end

	-- Module not found, instruct the user to use LuaRocks to install it:
	if not(aLuaRocksRockName) then
		-- No LuaRocks rock name given, output a generic error message:
		error("Cannot load module " .. aModuleName .. ": " .. tostring(m))
	end
	error(string.format(
		"Cannot load module %s: %s\n\n" ..
		"You can install it using the following LuaRocks command:\n" ..
		"sudo luarocks install %s",
		aModuleName, tostring(m),
		aLuaRocksRockName
	))
end





-- Load all the required rocks, in their dependency order:
local lfs       = requireWithHelp("lfs",       "luafilesystem")
local socket    = requireWithHelp("socket",    "luasocket")
local copas     = requireWithHelp("copas",     "copas")
local sqlite    = requireWithHelp("lsqlite3",  "lsqlite3")
local lxp       = requireWithHelp("lxp",       "luaexpat")
local etlua     = requireWithHelp("etlua",     "etlua")
local lzlib     = requireWithHelp("zlib",      "lua-zlib")
local multipart = requireWithHelp("multipart", "multipart")

-- Load the templates and utils:
print = require("logger")
require("Templates")
local httpResponse = require("httpResponse")
local httpRequest = require("httpRequest")
local db = require("db")
db.createSchema()
local router = require("router")
local chintSensor = require("chintSensor")
local aggregator = require("aggregator")





--- Calls the specified handler safely - if an error is raised, an error page is served
local function dispatchHandler(aClient, aPath, aHeaders, aHandler)
	assert(type(aPath) == "string")
	assert(type(aHeaders) == "table")
	assert(type(aHandler) == "function")

	-- Error handler that adds traceback
	local function onError(aErr)
		return debug.traceback(aErr, 2)
	end

	-- run handler safely
	local isOK, result = xpcall(function()
		return aHandler(aClient, aPath, aHeaders)
	end, onError)

	-- if an exception occurred
	if not(isOK) then
		local errText = result or "Unknown error"
		print("[main] ERROR during request:\n" .. errText)
		httpResponse.sendError(aClient, 500, errText)
	end
end





--- Handles a single HTTP client connection
local function handleRequest(aClient)
	local method, path, headers = httpRequest.readRequestHeaders(aClient)
	if (not(method) or not(path)) then
		return
	end

	local handler = router.match(method, path)
	if (handler) then
		local beginTime = socket.gettime()
		print(string.format("[main] %s Request for path \"%s\".", method, path))
		dispatchHandler(aClient, path, headers, handler)
		local endTime = socket.gettime()
		if (endTime - beginTime >= 0.5) then
			print(string.format("  ^^ Request took %f seconds.", (endTime - beginTime)))
		end
	else
		print(string.format("[main] UNHANDLED: %s Request for path \"%s\".", method, path))
		httpResponse.sendError(aClient, 404, "Not found")
	end
end





--- Starts the Copas HTTP server on port 5500
local function startServer()
	local serverSocket = assert(socket.bind("*", 5500))
	print("[main] Server running on http://localhost:5500/")

	copas.mainServer = serverSocket
	copas.addserver(serverSocket, function(aSocket)
		handleRequest(copas.wrap(aSocket))
	end)
end





--- Starts receiving data from the sensors
local function startSensors()
	chintSensor.start()
end





--- Start everything:
startSensors()
aggregator.start(          60, "ElectricityConsumptionAggregate1min")
aggregator.start(     15 * 60, "ElectricityConsumptionAggregate15min")
aggregator.start(24 * 60 * 60, "ElectricityConsumptionAggregateDay")
startServer()

copas.loop()

print("[main] Finished.")
