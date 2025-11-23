-- db.lua
-- Database access module

local sqlite3 = require("lsqlite3")

local db = {}
local dbFile = "homeEnergyHub.sqlite"
local conn = nil





--- Dict-table of aggregationSeconds -> table name containing the aggregated data
local gElectricityConsumptionAggregationToTableName = {
	[5] = "ElectricityConsumption",
	[60] = "ElectricityConsumptionAggregate1min",
	[15 * 60] = "ElectricityConsumptionAggregate15min",
	[24 * 60 * 60] = "ElectricityConsumptionAggregateDay",
}





--- Helper dict-table of columnName -> true for all valid columns for all aggregation tables
local gElectricityConsumptionAggregationValidColumns = {
	maxPowerA = true,
	maxPowerB = true,
	maxPowerC = true,
	maxPowerTotal = true,
	minPowerA = true,
	minPowerB = true,
	minPowerC = true,
	minPowerTotal = true,
	avgPowerA = true,
	avgPowerB = true,
	avgPowerC = true,
	avgPowerTotal = true,
}





--- Dict-table of aggregationSeconds -> columnName -> true for all valid columns
local gElectricityConsumptionAggregationValidColumnNames = {
	[5] = {
		powerA = true,
		powerB = true,
		powerC = true,
		powerTotal = true,
	},
	[60]           = gElectricityConsumptionAggregationValidColumns,
	[15 * 60]      = gElectricityConsumptionAggregationValidColumns,
	[24 * 60 * 60] = gElectricityConsumptionAggregationValidColumns,
}





--- Ensures an open DB connection
local function ensureDb()
	if not(conn) then
		conn = sqlite3.open(dbFile)
		conn:busy_timeout(1000)
	end
	return conn
end





--- Checks SQLite result codes and throws errors
local function checkSql(aConn, aResult, aContext)
	if (
		(aResult ~= sqlite3.OK) and
		(aResult ~= sqlite3.DONE) and
		(aResult ~= sqlite3.ROW)
	) then
		error(string.format("SQLite error in %s: %s", aContext or "unknown", aConn:errmsg()))
	end
end





--- Closes the DB connection
function db.close()
	if (conn) then
		conn:close()
		conn = nil
	end
end





--- Ensures DB schema exists and upgrades if needed
function db.createSchema()
	db.close()
	require("dbUpgrade").upgradeIfNeeded(dbFile)

	ensureDb()
end





--- Creates a backup of the DB file
-- Can only be called when the DB is closed, either before it is open for the first time, or after calling db.close()
function db.backup()
	assert(not(conn))  -- Is DB closed?

	require("dbUpgrade").backupDbFile(dbFile)
end





--- Executes the specified statement, binding the specified values to it.
-- aDescription is used for error logging.
function db.execBoundStatement(aSql, aValuesToBind, aDescription)
	local c = ensureDb()
	local stmt = c:prepare(aSql)
	if not(stmt) then
		error("Failed to prepare statement (" .. aDescription .. "): " .. c:errmsg())
	end
	checkSql(c, stmt:bind_values(table.unpack(aValuesToBind, 1, aValuesToBind.n or #aValuesToBind)), aDescription .. ".bind")
	checkSql(c, stmt:step(), aDescription .. ".step")
	checkSql(c, stmt:finalize(), aDescription .. ".finalize")
end





--- Runs the specified SQL query, binding the specified values to it, and returns the results as an array-table of dict-tables
-- aDescription is used for error logging.
function db.getArrayFromQuery(aSql, aValuesToBind, aDescription)
	assert(type(aSql) == "string")
	assert(type(aValuesToBind) == "table" or not(aValuesToBind))
	if not(aDescription) then
		aDescription = debug.getinfo(1, 'S').source
	end

	local c = ensureDb()
	local stmt = c:prepare(aSql)
	if not(stmt) then
		error("Failed to prepare statement (" .. aDescription .. "): " .. c:errmsg())
	end
	if ((aValuesToBind) and (aValuesToBind[1])) then
		checkSql(c, stmt:bind_values(table.unpack(aValuesToBind)), aDescription .. ".bind")
	end
	local result = {}
	local n = 0
	for row in stmt:nrows() do
		n = n + 1
		result[n] = row
	end
	result.n = n
	checkSql(c, stmt:finalize(), aDescription .. ".finalize")

	return result
end





--- Returns the energy deltas (for any available phases) and min/max power for a bucket
-- Returns a dict-table containing:
--   energyTotal, energyA, energyB, energyC   (only if computable; otherwise nil)
--   minPowerTotal, minPowerA, ...            (always present)
-- Returns nil if NO energy values can be computed at all.
function db.getBucketEnergyAndPower(aStartTs, aEndTs)

	--- Helper: interpolate a single numeric field, return nil if cannot interpolate
	local function interpField(beforeVal, afterVal, tBefore, tAfter, tTarget)
		if (not(beforeVal) or not(afterVal)) then
			return nil
		end
		if (tBefore == tAfter) then
			return beforeVal
		end
		local f = (tTarget - tBefore) / (tAfter - tBefore)
		return (afterVal - beforeVal) * f + beforeVal
	end

	--- Helper: interpolate a full energy row (per field)
	local function interpolateEnergy(b, a, tTarget)
		return {
			energyTotal = interpField(b.energyTotal, a.energyTotal, b.timeStamp, a.timeStamp, tTarget),
			energyA     = interpField(b.energyA,     a.energyA,     b.timeStamp, a.timeStamp, tTarget),
			energyB     = interpField(b.energyB,     a.energyB,     b.timeStamp, a.timeStamp, tTarget),
			energyC     = interpField(b.energyC,     a.energyC,     b.timeStamp, a.timeStamp, tTarget),
		}
	end

	-- Query the raw data at interval boundaries:
	local sqlBefore = [[
		SELECT *
		FROM ElectricityConsumption
		WHERE timeStamp <= ?
		ORDER BY timeStamp DESC
		LIMIT 1
	]]

	local sqlAfter = [[
		SELECT *
		FROM ElectricityConsumption
		WHERE timeStamp >= ?
		ORDER BY timeStamp ASC
		LIMIT 1
	]]

	local rowsBeforeStart = db.getArrayFromQuery(sqlBefore, {aStartTs}, "getBucketEnergyAndPower energy start before")
	local rowsAfterStart  = db.getArrayFromQuery(sqlAfter,  {aStartTs}, "getBucketEnergyAndPower energy start after")
	local rowsBeforeEnd   = db.getArrayFromQuery(sqlBefore, {aEndTs},   "getBucketEnergyAndPower energy end before")
	local rowsAfterEnd    = db.getArrayFromQuery(sqlAfter,  {aEndTs},   "getBucketEnergyAndPower energy end after")

	local bStart = rowsBeforeStart[1]
	local aStart = rowsAfterStart[1]
	local bEnd   = rowsBeforeEnd[1]
	local aEnd   = rowsAfterEnd[1]

	if not(bStart and aStart and bEnd and aEnd) then
		-- Absolutely no interpolation possible
		return nil
	end

	-- Interpolate start/end energy per field:
	local energyStart = interpolateEnergy(bStart, aStart, aStartTs)
	local energyEnd   = interpolateEnergy(bEnd,   aEnd,   aEndTs)

	-- Compute deltas only where both start+end are valid
	local function delta(vEnd, vStart)
		if (not(vEnd) or not(vStart)) then
			return nil  -- this phase cannot be computed
		end
		local d = vEnd - vStart
		return (d >= 0) and d or 0
	end

	local energyTotal = delta(energyEnd.energyTotal, energyStart.energyTotal)
	local energyA     = delta(energyEnd.energyA,     energyStart.energyA)
	local energyB     = delta(energyEnd.energyB,     energyStart.energyB)
	local energyC     = delta(energyEnd.energyC,     energyStart.energyC)

	-- If all energies are nil -> return nil
	if not(energyTotal or energyA or energyB or energyC) then
		return nil
	end

	-- Query power min/max (always safe):
	local rows = db.getArrayFromQuery([[
		SELECT
			MIN(powerA)       AS minPowerA,
			MAX(powerA)       AS maxPowerA,
			MIN(powerB)       AS minPowerB,
			MAX(powerB)       AS maxPowerB,
			MIN(powerC)       AS minPowerC,
			MAX(powerC)       AS maxPowerC,
			MIN(powerTotal)   AS minPowerTotal,
			MAX(powerTotal)   AS maxPowerTotal
		FROM ElectricityConsumption
		WHERE timeStamp >= ? AND timeStamp < ?
	]], {aStartTs, aEndTs}, "getBucketEnergyAndPower energy minmax")[1]

	-- Return combined row, including ONLY the energy fields we could compute:
	rows.energyTotal = energyTotal
	rows.energyA     = energyA
	rows.energyB     = energyB
	rows.energyC     = energyC

	return rows
end





--- Returns array-table or {timeStamp, value} in between the specified timestamps, for creating a power graph.
-- The values are queries from a table represented by the aggregation parameter, from the specified column name
-- Returns nil, errorMsg in case of bad parameters. Raises an error on DB errors.
-- Adjusts aStartTs and aEndTs to include values just-before-start and just-after-end to account for
-- them not being exactly on aggregation boundary
function db.getGraphPowerColumnData(aStartTs, aEndTs, aColumnName, aAggregationSec)
	assert(type(aStartTs) == "number")
	assert(type(aEndTs) == "number")
	assert(type(aColumnName) == "string")
	assert(type(aAggregationSec) == "number")

	-- Check the validity of the parameters:
	local tableName = gElectricityConsumptionAggregationToTableName[aAggregationSec]
	if not(tableName) then
		return nil, "Invalid aggregation: " .. aAggregationSec
	end
	if (
		not(gElectricityConsumptionAggregationValidColumnNames[aAggregationSec]) or
		not(gElectricityConsumptionAggregationValidColumnNames[aAggregationSec][aColumnName])
	) then
		return nil, "Invalid column name: " .. aColumnName
	end

	-- Adjust the timestamps by aggregation:
	local startTs = aStartTs - (aStartTs % aAggregationSec)
	local endTs = (aEndTs + aAggregationSec - 1) - ((aEndTs + aAggregationSec - 1) % aAggregationSec)

	return db.getArrayFromQuery([[
		SELECT timeStamp, ]] .. aColumnName .. [[ as value
		FROM ]] .. tableName .. [[
		WHERE timeStamp >= ? AND timeStamp <= ?
	]], {startTs, endTs}, "getGraphPowerColumnData")
end





--- Returns array-table with timeStamp, powerA, powerB, powerC and powerTotal in between the specified
-- timestamps, for creating a power graph.
-- A proper aggregation table is chosen to best represent the data in the graph
function db.getGraphPowerData(aStartTs, aEndTs)
	assert(type(aStartTs) == "number")
	assert(type(aEndTs) == "number")
	assert(aStartTs < aEndTs)

	-- Choose aggregation table:
	local aggTable, aggTableColumns
	local interval = aEndTs - aStartTs
	if (interval <= 10 * 60) then
		aggTable = "ElectricityConsumption" -- raw 5s data
		aggTableColumns = "powerA, powerB, powerC"
	elseif (interval <= 24 * 60 * 60) then
		aggTable = "ElectricityConsumptionAggregate1min"
		aggTableColumns = "maxPowerA AS powerA, maxPowerB AS powerB, maxPowerC AS powerC, maxPowerTotal AS powerTotal"
	elseif (interval <= 31 * 24 * 60 * 60) then
		aggTable = "ElectricityConsumptionAggregate15min"
		aggTableColumns = "avgPowerA AS powerA, avgPowerB AS powerB, avgPowerC AS powerC, avgPowerTotal AS powerTotal"
	else
		aggTable = "ElectricityConsumptionAggregateDay"
		aggTableColumns = "avgPowerA AS powerA, avgPowerB AS powerB, avgPowerC AS powerC, avgPowerTotal AS powerTotal"
	end

	-- Query DB for the interval:
	local sql = [[
		SELECT timeStamp, ]] .. aggTableColumns .. [[
		FROM ]] .. aggTable .. [[
		WHERE timeStamp >= ? AND timeStamp <= ?
		ORDER BY timeStamp ASC
	]]
	return db.getArrayFromQuery(sql, {aStartTs, aEndTs}, "getGraphPowerData")
end





--- Returns a single number representing the latest timestamp in the ElectricityConsumption table
-- Returns nil if no data in the table
function db.getLastElectricityConsumptionMeasurementTimestamp()
	local res = db.getArrayFromQuery("SELECT MAX(timeStamp) as maxTimeStamp FROM ElectricityConsumption", {}, "getLastElectricityConsumptionMeasurementTimestamp")
	if (not(res) or (res.n ~= 1)) then
		return nil
	end
	return res[1].maxTimeStamp
end





--- Returns the latest DB row in the ElectricityConsumption table
-- Returns nil if no data in the table
function db.getLatestElectricityConsumptionMeasurement()
	local res = db.getArrayFromQuery([[
		SELECT timeStamp, powerTotal, powerA, powerB, powerC, energyTotal, energyA, energyB, energyC
		FROM ElectricityConsumption
		ORDER BY timeStamp DESC LIMIT 1
	]], {}, "getLastElectricityConsumption")
	if (not(res) or (res.n < 1)) then
		return nil
	end
	return res[1]
end





--- Returns the timestamp of the latest bucket missing from aTargetTable
-- Uses two-step query to simplify SQL and avoid SQLite CTE quirks
function db.getLatestMissingAggregateBucket(aTargetTable, aIntervalSeconds)
	assert(type(aTargetTable) == "string")
	assert(type(aIntervalSeconds) == "number")

	-- Step 1: get min and max timestamps from raw table
	local rows = db.getArrayFromQuery([[
		SELECT MIN(timeStamp) AS minTs, MAX(timeStamp) AS maxTs
		FROM ElectricityConsumption
	]], {}, "getLatestMissingAggregateBucket min/max")

	if (not rows or not rows[1] or not rows[1].minTs) then
		return nil
	end

	-- Align to interval boundaries
	local startTs = math.floor(rows[1].minTs / aIntervalSeconds) * aIntervalSeconds
	local endTs   = math.floor(rows[1].maxTs / aIntervalSeconds) * aIntervalSeconds
	assert(endTs <= rows[1].maxTs)

	-- Step 2: CTE to generate all aligned buckets and find the latest missing one
	local sql = [[
		WITH RECURSIVE buckets(ts) AS (
			SELECT ? AS ts
			UNION ALL
			SELECT ts - ? FROM buckets WHERE ts >= ?
		)
		SELECT ts
		FROM buckets b
		LEFT JOIN ]] .. aTargetTable .. [[ a
			ON a.timeStamp = b.ts
		WHERE a.timeStamp IS NULL
		ORDER BY ts DESC
		LIMIT 1;
	]]

	local bind = { endTs - aIntervalSeconds, aIntervalSeconds, startTs }

	local missingRows = db.getArrayFromQuery(sql, bind, "getLatestMissingAggregateBucket CTE")
	if (missingRows and missingRows[1]) then
		assert(missingRows[1].ts < endTs)
		return missingRows[1].ts
	end

	return nil
end





--- Returns the tariff plan daytype schedules in an array-table
function db.getTariffPlanDayTypeSchedules()
	return db.getArrayFromQuery("SELECT * FROM TariffPlanDayTypeSchedules", {}, "getTariffPlanDayTypeSchedules")
end





--- Returns the tariff plan exceptionDates in an array-table
function db.getTariffPlanExceptionDates()
	return db.getArrayFromQuery("SELECT * FROM TariffPlanExceptionDates", {}, "getTariffPlanExceptionDates")
end





--- Returns the tariff plan seasons in an array-table
function db.getTariffPlanSeasons()
	return db.getArrayFromQuery("SELECT * FROM TariffPlanSeasons", {}, "getTariffPlanSeasons")
end





function db.insertAggregate(aTableName, aTimeStamp, aAggregatedMeasurement)
	assert(type(aTableName) == "string")
	assert(type(aTimeStamp) == "number")
	assert(type(aAggregatedMeasurement) == "table")

	db.execBoundStatement([[
		INSERT OR REPLACE INTO ]] .. aTableName .. [[ (
			timeStamp,
			avgPowerTotal, avgPowerA, avgPowerB, avgPowerC,
			minPowerTotal, minPowerA, minPowerB, minPowerC,
			maxPowerTotal, maxPowerA, maxPowerB, maxPowerC,
			energyTotal, energyA, energyB, energyC
		)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	]], {
		aTimeStamp,
		aAggregatedMeasurement.avgPowerTotal,
		aAggregatedMeasurement.avgPowerA,
		aAggregatedMeasurement.avgPowerB,
		aAggregatedMeasurement.avgPowerC,
		aAggregatedMeasurement.minPowerTotal,
		aAggregatedMeasurement.minPowerA,
		aAggregatedMeasurement.minPowerB,
		aAggregatedMeasurement.minPowerC,
		aAggregatedMeasurement.maxPowerTotal,
		aAggregatedMeasurement.maxPowerA,
		aAggregatedMeasurement.maxPowerB,
		aAggregatedMeasurement.maxPowerC,
		aAggregatedMeasurement.energyTotal,
		aAggregatedMeasurement.energyA,
		aAggregatedMeasurement.energyB,
		aAggregatedMeasurement.energyC,
		n = 17
	}, "insertAggregate." .. aTableName)
end





--- Saves multiple 5-second buckets of electricity measurement (rows in ElectricityConsumption table)
-- Each aMeasurements[i] is a dict-able of DB column name -> value, with some columns possibly missing, and with a timeStamp
function db.saveMultipleElectricityMeasurements(aMeasurements)
	assert(type(aMeasurements) == "table")

	local c = ensureDb()
	checkSql(c, c:exec("BEGIN TRANSACTION"), "saveMultipleElectricityMeasurements.begin")
	local stmt = c:prepare([[
		INSERT OR REPLACE INTO ElectricityConsumption (timeStamp, powerTotal, powerA, powerB, powerC, energyTotal, energyA, energyB, energyC)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare the statement for inserting multiple electricity measurements: " .. c:errmsg())
	end
	for _, measurement in ipairs(aMeasurements) do
		assert(tonumber(measurement.timeStamp))
		checkSql(c, stmt:bind_values(
			measurement.timeStamp,
			measurement.powerTotal,
			measurement.powerA,
			measurement.powerB,
			measurement.powerC,
			measurement.energyTotal,
			measurement.energyA,
			measurement.energyB,
			measurement.energyC
		), "saveMultipleElectricityMeasurements.bind")
		checkSql(c, stmt:step(), "saveMultipleElectricityMeasurements.step")
		checkSql(c, stmt:reset(), "saveMultipleElectricityMeasurements.reset")
	end
	checkSql(c, stmt:finalize(), "saveMultipleElectricityMeasurements.finalize")
	checkSql(c, c:exec("COMMIT TRANSACTION"), "saveMultipleElectricityMeasurements.commit")
end





--- Saves a single 5-second bucket of electricity measurement (a single row in ElectricityConsumption table)
-- aMeasurement is a dict-table of DB column name -> value, with some columns possibly missing
function db.saveSingleElectricityMeasurement(aTimeStamp, aMeasurement)
	assert(tonumber(aTimeStamp))

	db.execBoundStatement([[
		INSERT OR REPLACE INTO ElectricityConsumption (timeStamp, powerTotal, powerA, powerB, powerC, energyTotal, energyA, energyB, energyC)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	]], {
		aTimeStamp,
		aMeasurement.powerTotal,
		aMeasurement.powerA,
		aMeasurement.powerB,
		aMeasurement.powerC,
		aMeasurement.energyTotal,
		aMeasurement.energyA,
		aMeasurement.energyB,
		aMeasurement.energyC,
		n = 9
	}, "saveSingleElectricityMeasurement")
end





return db
