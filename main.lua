-- main.lua

-- Implements the main app entrypoint





-- Abort if running on Lua 5.1 (without LuaJIT):
-- Lua 5.1 cannot yield across an xpcall(), thus hindering our HTTP handler error handling
if ((_VERSION == "Lua 5.1") and not(jit)) then
	error("This application requires Lua 5.2+ or LuaJIT")
end





-- Compatibility between plain LuaJIT and LuaJIT as used while developing in ZeroBrane Studio:
package.path = "./?/init.lua;" .. package.path  -- Allow loading packages from subfolders with an init script
table.unpack = table.unpack or unpack





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
	local luaVersionArg = ""
	local luaVersion = string.match(_VERSION, ".- (%d.%d)")
	if (luaVersion) then
		luaVersionArg = " --lua-version=" .. luaVersion
	end
	error(string.format(
		"Cannot load module %s: %s\n\n" ..
		"You can install it using the following LuaRocks command:\n" ..
		"sudo luarocks install %s%s",
		aModuleName, tostring(m),
		aLuaRocksRockName, luaVersionArg
	))
end





-- Load all the required LuaRocks, in their dependency order:
local lfs       = requireWithHelp("lfs",       "luafilesystem")
local socket    = requireWithHelp("socket",    "luasocket")
local copas     = requireWithHelp("copas",     "copas")
local sqlite    = requireWithHelp("lsqlite3",  "lsqlite3")
local lxp       = requireWithHelp("lxp",       "luaexpat")
local etlua     = requireWithHelp("etlua",     "etlua")
local lzlib     = requireWithHelp("zlib",      "lua-zlib")
local multipart = requireWithHelp("multipart", "multipart")

-- Load the app modules:
local log = require("logger").log
require("svgGraph")
require("Templates")
local db = require("db")
local router = require("router")
local chintSensor = require("chintSensor")
local aggregator = require("aggregator")
local config = require("config")
local requestTracker = require("requestTracker")
local httpRequest = require("httpRequest")
local httpResponse = require("httpResponse")





config.registerDefinitions(
{
	{
		identifier = "http.port",
		description = "The port on which the main app HTTP server listens on. Must be free on the local system.",
		category = "HTTP",
		valueType = "number",
		default = 5500,
		validator = function(aValue)
			aValue = tonumber(aValue)
			if not(aValue) then
				return nil, "Not a number"
			end
			if ((aValue < 0) or (aValue > 65535)) then
				return nil, "Out of range; valid range is 0 - 65536."
			end
			return true
		end,
		isRestartRequired = true,
	},
})
config.loadAll()





--- Handles a single connected client, possibly with keep-alive:
local function clientLoop(aSocket)
	copas.mainServerClients = copas.mainServerClients or {}
	copas.mainServerClients[aSocket] = true
	while true do
		local req, err = httpRequest.createFromSocket(aSocket)
		if not req then
			break
		end
		requestTracker.beginRequest()
		local resp = httpResponse.new(req)
		router.handleRequest(req, resp)
		resp:finish()
		req:discardUnreadBody()
		requestTracker.endRequest()
		if not(req:shouldKeepAlive(resp)) then
			break
		end
	end
	copas.mainServerClients[aSocket] = false
	aSocket:close()
end





--- Starts the Copas HTTP server
local function startServer()
	local port = config.get("http.port")
	local serverSocket = assert(socket.bind("*", port))
	log("main", "Server running on http://localhost:" .. port .. "/")

	copas.mainServerSocket = serverSocket
	copas.addserver(serverSocket,
		function(aSocket)
			clientLoop(copas.wrap(aSocket))
		end,
		nil,
		"mainServerSocket"
	)

	copas.loop()
	log("main", "Server loop terminated.")
end





--- Starts receiving data from the sensors
local function startSensors()
	chintSensor.start()
end





--- Start everything:
log("main", "Starting up...")
startSensors()
aggregator.start()
startServer()

log("main", "Finished.")
