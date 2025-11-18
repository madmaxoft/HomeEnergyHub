-- db.lua
-- Database access module

local sqlite3 = require("lsqlite3")

local db = {}
local dbFile = "homeEnergyHub.sqlite"
local conn = nil





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





--- Returns the energy deltas for a given bucket using raw data, and the min / max power
-- Returns a dict-table of energyTotal, energyA, energyB, energyC numbers representing the kWh consumed,
-- minPowerTotal, minPowerA, ... representing the minimum power (W),
-- maxPowerTotal, maxPowerA, ... representing the maximum power (W)
-- within the specified timestamp window
-- Returns nil if not enough data to determine the energy
function db.getBucketEnergyAndPower(aStartTs, aEndTs)
	-- Helper: linear interpolation for all energy values
	local function interpolateEnergy(aBefore, aAfter, aTs)
		if (aBefore.timeStamp == aAfter.timeStamp) then
			return {
				energyTotal = aBefore.energyTotal,
				energyA = aBefore.energyA,
				energyB = aBefore.energyB,
				energyC = aBefore.energyC
			}
		end
		local factor = (aTs - aBefore.timeStamp) / (aAfter.timeStamp - aBefore.timeStamp)
		return {
			energyTotal = (aAfter.energyTotal - aBefore.energyTotal) * factor + aBefore.energyTotal,
			energyA = (aAfter.energyA - aBefore.energyA) * factor + aBefore.energyA,
			energyB = (aAfter.energyB - aBefore.energyB) * factor + aBefore.energyB,
			energyC = (aAfter.energyC - aBefore.energyC) * factor + aBefore.energyC
		}
	end

	-- Get nearest raw row <= start
	local sqlBeforeStart = [[
		SELECT * FROM ElectricityConsumption
		WHERE timeStamp <= ? AND energyTotal IS NOT NULL AND energyA IS NOT NULL AND energyB IS NOT NULL AND energyC IS NOT NULL
		ORDER BY timeStamp DESC
		LIMIT 1
	]]
	local rowsBeforeStart = db.getArrayFromQuery(sqlBeforeStart, {aStartTs}, "getBucketEnergy start before")
	local rowBeforeStart = (rowsBeforeStart and #rowsBeforeStart > 0) and rowsBeforeStart[1] or nil

	-- Get nearest raw row >= start
	local sqlAfterStart = [[
		SELECT * FROM ElectricityConsumption
		WHERE timeStamp >= ? AND energyTotal IS NOT NULL AND energyA IS NOT NULL AND energyB IS NOT NULL AND energyC IS NOT NULL
		ORDER BY timeStamp ASC
		LIMIT 1
	]]
	local rowsAfterStart = db.getArrayFromQuery(sqlAfterStart, {aStartTs}, "getBucketEnergy start after")
	local rowAfterStart = (rowsAfterStart and #rowsAfterStart > 0) and rowsAfterStart[1] or nil

	if (not(rowBeforeStart) or not(rowAfterStart)) then
		return nil
	end
	local startEnergy = interpolateEnergy(rowBeforeStart, rowAfterStart, aStartTs)

	-- Get nearest raw row <= end:
	local sqlBeforeEnd = [[
		SELECT * FROM ElectricityConsumption
		WHERE timeStamp <= ? AND energyTotal IS NOT NULL AND energyA IS NOT NULL AND energyB IS NOT NULL AND energyC IS NOT NULL
		ORDER BY timeStamp DESC
		LIMIT 1
	]]
	local rowsBeforeEnd = db.getArrayFromQuery(sqlBeforeEnd, {aEndTs}, "getBucketEnergy end before")
	local rowBeforeEnd = (rowsBeforeEnd and #rowsBeforeEnd > 0) and rowsBeforeEnd[1] or nil

	-- Get nearest raw row >= end:
	local sqlAfterEnd = [[
		SELECT * FROM ElectricityConsumption
		WHERE timeStamp >= ? AND energyTotal IS NOT NULL AND energyA IS NOT NULL AND energyB IS NOT NULL AND energyC IS NOT NULL
		ORDER BY timeStamp ASC
		LIMIT 1
	]]
	local rowsAfterEnd = db.getArrayFromQuery(sqlAfterEnd, {aEndTs}, "getBucketEnergy end after")
	local rowAfterEnd = (rowsAfterEnd and #rowsAfterEnd > 0) and rowsAfterEnd[1] or nil

	if (not(rowBeforeEnd) or not(rowAfterEnd)) then
		return nil
	end
	local endEnergy = interpolateEnergy(rowBeforeEnd, rowAfterEnd, aEndTs)

	-- Calculate the delta:
	local function delta(vEnd, vStart)
		if (not(vEnd) or not(vStart)) then
			return 0
		end
		local d = vEnd - vStart
		return (d >= 0) and d or 0  -- optionally handle wrap/reset
	end

	local rows = db.getArrayFromQuery([[
		SELECT
			MIN(powerA)  AS minPowerA,
			MAX(powerA)  AS maxPowerA,
			MIN(powerB)  AS minPowerB,
			MAX(powerB)  AS maxPowerB,
			MIN(powerC)  AS minPowerC,
			MAX(powerC)  AS maxPowerC,
			MIN(powerTotal) AS minPowerTotal,
			MAX(powerTotal) AS maxPowerTotal
		FROM ElectricityConsumption
		WHERE (timeStamp >= ?) AND (timeStamp < ?);
	]], {aStartTs, aEndTs}, "getBucketEnergyAndPower.minmax")
	assert(type(rows) == "table")
	assert(type(rows[1]) == "table")
	local row = rows[1]

	row.energyTotal = delta(endEnergy.energyTotal, startEnergy.energyTotal)
	row.energyA = delta(endEnergy.energyA, startEnergy.energyA)
	row.energyB = delta(endEnergy.energyB, startEnergy.energyB)
	row.energyC = delta(endEnergy.energyC, startEnergy.energyC)
	return row
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
