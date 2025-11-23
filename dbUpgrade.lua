-- dbUpgrade.lua
-- Handles schema versioning and upgrades for the anime database

local sqlite3 = require("lsqlite3")
local lfs = require("lfs")

local dbUpgrade = {}





--- Upgrade scripts: each entry defines version and SQL to reach it
local upgrades = {
	{
		version = 1,
		script = [[
		CREATE TABLE ElectricityConsumption (
			timeStamp INTEGER PRIMARY KEY,
			powerTotal REAL,
			powerA REAL,
			powerB REAL,
			powerC REAL,
			energyTotal REAL,
			energyA REAL,
			energyB REAL,
			energyC REAL
		);

		CREATE TABLE ElectricityConsumptionAggregate1min (
			timeStamp INTEGER PRIMARY KEY,
			avgPowerTotal REAL,
			avgPowerA REAL,
			avgPowerB REAL,
			avgPowerC REAL,
			minPowerTotal REAL,
			minPowerA REAL,
			minPowerB REAL,
			minPowerC REAL,
			maxPowerTotal REAL,
			maxPowerA REAL,
			maxPowerB REAL,
			maxPowerC REAL,
			energyTotal REAL,
			energyA REAL,
			energyB REAL,
			energyC REAL
		);

		CREATE TABLE ElectricityConsumptionAggregate15min (
			timeStamp INTEGER PRIMARY KEY,
			avgPowerTotal REAL,
			avgPowerA REAL,
			avgPowerB REAL,
			avgPowerC REAL,
			minPowerTotal REAL,
			minPowerA REAL,
			minPowerB REAL,
			minPowerC REAL,
			maxPowerTotal REAL,
			maxPowerA REAL,
			maxPowerB REAL,
			maxPowerC REAL,
			energyTotal REAL,
			energyA REAL,
			energyB REAL,
			energyC REAL
		);

		CREATE TABLE ElectricityConsumptionAggregateDay (
			timeStamp INTEGER PRIMARY KEY,
			avgPowerTotal REAL,
			avgPowerA REAL,
			avgPowerB REAL,
			avgPowerC REAL,
			minPowerTotal REAL,
			minPowerA REAL,
			minPowerB REAL,
			minPowerC REAL,
			maxPowerTotal REAL,
			maxPowerA REAL,
			maxPowerB REAL,
			maxPowerC REAL,
			energyTotal REAL,
			energyA REAL,
			energyB REAL,
			energyC REAL
		);
		]]
	},

	{
		version = 2,
		script = [[
			CREATE TABLE TariffPlanSeasons (
				startDate TEXT NOT NULL,
				endDate TEXT NOT NULL,
				workdayDayType INTEGER NOT NULL,
				weekendDayType INTEGER NOT NULL
			);

			CREATE TABLE TariffPlanDayTypeSchedules (
				dayType INTEGER NOT NULL,
				startMinute INTEGER NOT NULL,
				endMinute INTEGER NOT NULL,
				multiplier REAL NOT NULL
			);

			CREATE TABLE TariffPlanExceptionDates (
				date TEXT NOT NULL PRIMARY KEY,
				dayType INTEGER NOT NULL
			);
		]]
	},
	-- Future upgrades can be added here
}





--- Copies a file in binary mode
local function copyFile(aSrc, aDst)
	local inFile = assert(io.open(aSrc, "rb"))
	local data = inFile:read("*a")
	inFile:close()

	local outFile = assert(io.open(aDst, "wb"))
	outFile:write(data)
	outFile:close()
end




--- Creates a backup copy of the DB file before upgrade
function dbUpgrade.backupDbFile(aDbPath)
	local time = os.time()
	local timeStamp = os.date("%Y%m%d-%H%M%S", time)
	local year = os.date("%Y", time)
	local day = os.date("%Y-%m-%d", time)
	lfs.mkdir("Backups")
	lfs.mkdir("Backups/" .. year)
	lfs.mkdir("Backups/" .. year .. "/" .. day)
	local backupPath = "Backups/" .. year .. "/" .. day .. "/" .. aDbPath:gsub("%.sqlite$", "") .. "-" .. timeStamp .. ".sqlite"
	print("[DB] Creating backup: " .. backupPath)
	copyFile(aDbPath, backupPath)
end




--- Gets current schema version from KeyValue (0 if missing)
local function getSchemaVersion(aConn)
	local version = 0
	local stmt = aConn:prepare("SELECT value FROM KeyValue WHERE key = 'homeEnergyHub-schemaVersion';")
	if (stmt) then
		for row in stmt:nrows() do
			version = tonumber(row.value) or 0
		end
		stmt:finalize()
	end
	return version
end




--- Updates schema version in KeyValue
local function setSchemaVersion(aConn, aVersion)
	local stmt = aConn:prepare("INSERT OR REPLACE INTO KeyValue (key, value) VALUES ('homeEnergyHub-schemaVersion', ?)")
	if not(stmt) then error("Failed to prepare schema version update: " .. aConn:errmsg()) end
	stmt:bind_values(tostring(aVersion))
	stmt:step()
	stmt:finalize()
end




--- Runs all needed upgrades in order
-- If an upgrade is to be done, first creates a backup of the DB file
function dbUpgrade.upgradeIfNeeded(aDbFileName)
	-- Check the schema version in the DB:
	local conn, errCode, errMsg = sqlite3.open(
		string.format("file:%s?immutable=1", aDbFileName),  -- Disable WAL, SHM, locking etc.
		sqlite3.OPEN_READONLY + sqlite3.OPEN_URI
	)
	local current = 0
	if not(conn) then
		if (errCode ~= sqlite3.CANTOPEN) then
			error(string.format("[dbUpgrade] Failed to open DB: %s (%s)",
				tostring(errCode), tostring(errMsg)
			))
		end
		-- Failed to open the DB file because it doesn't exist, continue without making a backup:
		print("[dbUpgrade] DB file doesn't exist, creating from scratch")
		current = -1
	else
		conn:busy_timeout(1000)
		current = getSchemaVersion(conn)
		conn:close()
	end
	local latest = upgrades[#upgrades].version
	if (current > latest) then
		error(string.format(
			"[dbUpgrade] DB schema is from a future version, don't know how to handle it. DB version: %d. My version: %d",
			current, latest
		))
	end
	if (current == latest) then
		print("[dbUpgrade] Schema up to date (v" .. current .. ")")
		return
	end
	if (current >= 0) then
		print("[dbUpgrade] Current schema v" .. current .. ", latest v" .. latest .. " — upgrading...")
	end

	-- Backup the current DB file:
	if (current >= 0) then
		dbUpgrade.backupDbFile(aDbFileName)
	end
	conn = sqlite3.open(aDbFileName)
	conn:busy_timeout(1000)

	-- Ensure KeyValue table exists early for first-time DBs
	conn:exec("CREATE TABLE IF NOT EXISTS KeyValue (key TEXT PRIMARY KEY, value TEXT);")

	-- Run the upgrade scripts:
	for i = 1, #upgrades do
		local u = upgrades[i]
		if (u.version > current) then
			print("[dbUpgrade] Applying upgrade to v" .. u.version .. "...")
			local result = conn:exec(u.script)
			if (result ~= sqlite3.OK) then
				error("DB upgrade to v" .. u.version .. " failed: " .. conn:errmsg())
			end
			setSchemaVersion(conn, u.version)
			print("[dbUpgrade] Schema upgraded to v" .. u.version)
		end
	end
	conn:close()
end

return dbUpgrade
