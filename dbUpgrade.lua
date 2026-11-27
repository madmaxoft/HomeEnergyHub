-- dbUpgrade.lua
-- Handles schema versioning and upgrades for the anime database

local sqlite3 = require("lsqlite3")
local lfs = require("lfs")
local log = require("logger").log
local lldb = require("lowLevelDB")




--- The API returned from this module
local dbUpgrade = {}





--- Upgrade scripts: each entry defines version and SQL to reach it
local upgrades = {
	-- Version 1
	{
		[[
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
		]],
	},

	-- Version 2
	{
		[[
			CREATE TABLE TariffPlanSeasons (
				startDate TEXT NOT NULL,
				endDate TEXT NOT NULL,
				workdayDayType INTEGER NOT NULL,
				weekendDayType INTEGER NOT NULL
			);
		]],
		[[
			CREATE TABLE TariffPlanDayTypeSchedules (
				dayType INTEGER NOT NULL,
				startMinute INTEGER NOT NULL,
				endMinute INTEGER NOT NULL,
				multiplier REAL NOT NULL
			);
		]],
		[[
			CREATE TABLE TariffPlanExceptionDates (
				date TEXT NOT NULL PRIMARY KEY,
				dayType INTEGER NOT NULL
			);
		]],
	},

	-- Version 3
	{
		[[
			ALTER TABLE TariffPlanExceptionDates
			RENAME COLUMN date TO exceptionDate;
		]],
	},

	-- Version 4
	{
		[[
			ALTER TABLE TariffPlanSeasons
			RENAME COLUMN startDate TO startDateYmd;
		]],
		[[
			ALTER TABLE TariffPlanSeasons
			RENAME COLUMN endDate TO endDateYmd;
		]],
		[[
			ALTER TABLE TariffPlanExceptionDates
			RENAME COLUMN exceptionDate TO exceptionDateYmd;
		]],
	},

	-- Version 5
	{
		-- Drop the aggregation data in the main DB and move it into the attached aggregated.sqlite DB file:
		[[
			DROP TABLE IF EXISTS ElectricityConsumptionAggregate1min;
			DROP TABLE IF EXISTS ElectricityConsumptionAggregate15min;
			DROP TABLE IF EXISTS ElectricityConsumptionAggregateDay;
		]],
		[[
			CREATE TABLE aggr.ElectricityConsumptionAggregate1min (
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
		]],
		[[
			CREATE TABLE aggr.ElectricityConsumptionAggregate15min (
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
		]],
		[[
			CREATE TABLE aggr.ElectricityConsumptionAggregateDay (
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
		]],
	},

	-- Version 6
	{
		[[
			CREATE TABLE aggr.AggregationProgress (
				tableName TEXT PRIMARY KEY,
				nextBucket INTEGER
			);
		]],
		[[
			ALTER TABLE aggr.ElectricityConsumptionAggregate1min DROP COLUMN avgPowerTotal;
			ALTER TABLE aggr.ElectricityConsumptionAggregate1min DROP COLUMN avgPowerA;
			ALTER TABLE aggr.ElectricityConsumptionAggregate1min DROP COLUMN avgPowerB;
			ALTER TABLE aggr.ElectricityConsumptionAggregate1min DROP COLUMN avgPowerC;
		]],
		[[
			ALTER TABLE aggr.ElectricityConsumptionAggregate15min DROP COLUMN avgPowerTotal;
			ALTER TABLE aggr.ElectricityConsumptionAggregate15min DROP COLUMN avgPowerA;
			ALTER TABLE aggr.ElectricityConsumptionAggregate15min DROP COLUMN avgPowerB;
			ALTER TABLE aggr.ElectricityConsumptionAggregate15min DROP COLUMN avgPowerC;
		]],
		[[
			ALTER TABLE aggr.ElectricityConsumptionAggregateDay DROP COLUMN avgPowerTotal;
			ALTER TABLE aggr.ElectricityConsumptionAggregateDay DROP COLUMN avgPowerA;
			ALTER TABLE aggr.ElectricityConsumptionAggregateDay DROP COLUMN avgPowerB;
			ALTER TABLE aggr.ElectricityConsumptionAggregateDay DROP COLUMN avgPowerC;
		]],
	},

	-- Version 7
	{
		[[
			CREATE INDEX idx_ElectricityConsumption_timeStamp ON ElectricityConsumption(timeStamp);
		]],
	},

	-- Version 8
	{
		[[
			CREATE TABLE UserData.Config
			(
				identifier TEXT PRIMARY KEY,
				dbValue TEXT NOT NULL
			);
		]],
	},

	-- Version 9
	{
		[[
			DROP TABLE aggr.AggregationProgress;
		]],
	},

	-- Version 10:
	{
		-- Drop the index, it is not needed since timeStamp is already a primary integer key (rowid):
		[[
			DROP INDEX idx_ElectricityConsumption_timeStamp;
		]],
	},
	-- Future upgrades can be added here
}





--- Copies a file in binary mode
-- Raises an error if any IO fails.
local function copyFile(aSrc, aDst)
	local inFile = assert(io.open(aSrc, "rb"))
	local outFile = assert(io.open(aDst, "wb"))

	while (true) do
		local data = inFile:read(1024 * 1024)
		if not(data) then
			break
		end
		assert(outFile:write(data))
	end

	inFile:close()
	outFile:close()
end





--- Creates a backup copy of the DB file before upgrade
function dbUpgrade.backupDbFile(aDbPath)
	local time = os.time()
	local timeStamp = os.date("!%Y%m%d-%H%M%S", time)
	local year = os.date("!%Y", time)
	local day = os.date("!%Y-%m-%d", time)
	lfs.mkdir("Backups")
	lfs.mkdir("Backups/" .. year)
	lfs.mkdir("Backups/" .. year .. "/" .. day)
	local backupPath = "Backups/" .. year .. "/" .. day .. "/" .. aDbPath:gsub("%.sqlite$", "") .. "-" .. timeStamp .. ".sqlite"
	log("dbUpgrade", "Creating backup: " .. backupPath)
	copyFile(aDbPath, backupPath)
end




--- Gets current schema version from KeyValue (0 if missing)
function dbUpgrade.getSchemaVersion(aConn)
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
function dbUpgrade.setSchemaVersion(aConn, aVersion)
	local stmt = aConn:prepare("INSERT OR REPLACE INTO KeyValue (key, value) VALUES ('homeEnergyHub-schemaVersion', ?)")
	if not(stmt) then error("Failed to prepare schema version update: " .. aConn:errmsg()) end
	stmt:bind_values(tostring(aVersion))
	stmt:step()
	stmt:finalize()
end




--- Runs all needed upgrades in order
function dbUpgrade.upgradeIfNeeded(aConn, aDbPath)
	local current = dbUpgrade.getSchemaVersion(aConn)
	local latest = #upgrades

	if (current >= latest) then
		log("dbUpgrade", "Schema up to date (v%d)", current)
		return
	end

	log("dbUpgrade", "Current schema v%d, latest v%d - upgrading...", current, latest)

	-- Ensure KeyValue table exists early for first-time DBs
	lldb.executeSql(aConn, "CREATE TABLE IF NOT EXISTS KeyValue (key TEXT PRIMARY KEY, value TEXT);", "CreateKeyValue")

	for version, upg in ipairs(upgrades) do
		if (version > current) then
			log("dbUpgrade", "Applying upgrade to v%d", version)
			lldb.executeSql(aConn, "BEGIN TRANSACTION", string.format("Upgrade.v%d", version))
			for idx, cmd in ipairs(upg) do
				local t = type(cmd)
				if (t == "string") then
					lldb.executeSql(aConn, cmd, string.format("Upgrade.v%d.%d", version, idx))
				elseif (t == "function") then
					cmd(aConn)
				end
			end
			dbUpgrade.setSchemaVersion(aConn, version)
			lldb.executeSql(aConn, "COMMIT", string.format("Upgrade.v%d", version))
			log("dbUpgrade", "Schema upgraded to v%d", version)
		end
	end
end





return dbUpgrade
