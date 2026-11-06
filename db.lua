-- db.lua
-- Database access module

local sqlite3 = require("lsqlite3")
local perf = require("perf")
local lldb = require("lowLevelDB")
local dbUpgrade = require("dbUpgrade")
local log = require("logger").log





local db = {}
local gDB = nil





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





--- Initializes the module, opens the DB, attaches secondary DB files
local function initialize()
	assert(gDB == nil)

	gDB = sqlite3.open("homeEnergyHub.sqlite")
	gDB:busy_timeout(1000)
	lldb.checkSql(gDB, gDB:execute("PRAGMA foreign_keys = ON;"), "initialize.fkon")
	lldb.checkSql(gDB, gDB:execute("ATTACH \"aggregated.sqlite\" as aggr"), "initialize.attach")
	lldb.checkSql(gDB, gDB:execute("ATTACH \"userData.sqlite\" as UserData"), "initialize.attach")

	-- Upgrade, if needed:
	dbUpgrade.upgradeIfNeeded(gDB)

	log("db", "DB init done.")
end





--- Adds a new dayType with the all-day 100 % multiplier
-- Returns the new dayType
function db.addNewTariffPlanDayType(aDayType)
	lldb.executeBoundSql(gDB, [[
		INSERT INTO TariffPlanDayTypeSchedules
		(dayType, startMinute, endMinute, multiplier)
		SELECT COALESCE(MAX(dayType), -1) + 1, 0, 1440, 1
		FROM TariffPlanDayTypeSchedules;
	]], {}, "addTariffPlanDayType")
	local res = lldb.arrayFromQuery(gDB, "SELECT MAX(dayType) as m FROM TariffPlanDayTypeSchedules", {}, "addNewTariffPlanDayType.getMax")
	return res[1].m
end





--- Adds a new TariffPlan ExceptionDate, or overwrites an existing one
function db.addNewTariffPlanExceptionDate(aExceptionDateYmd, aDayType)
	assert(type(aExceptionDateYmd) == "string")
	assert(type(aDayType) == "number")

	lldb.executeBoundSql(gDB, [[
		INSERT INTO TariffPlanExceptionDates
		(exceptionDateYmd, dayType)
		VALUES (?, ?)
		ON CONFLICT DO UPDATE SET dayType = excluded.dayType
	]], {aExceptionDateYmd, aDayType}, "addNewTariffPlanExceptionDate")
end





--- Returns the next bucket to process for the specified aggregation table, if progress is saved.
-- Returns nil if no progress is stored
function db.aggregationProgress(aTableName)
	assert(type(aTableName) == "string")

	local rows = lldb.arrayFromQuery(gDB, [[
		SELECT nextBucket
		FROM aggr.AggregationProgress
		WHERE tableName = ?
	]], {aTableName}, "aggregationProgress")

	return rows[1] and rows[1].nextBucket
end





--- Returns an array-table of all config values, as {identifier = "", dbValue = ""} items
-- Returns an empty array on empty DB.
-- Returns nil and error message on error.
function db.allConfigValues()
	return lldb.arrayFromQuery(gDB, "SELECT * FROM UserData.Config", {}, "allConfigValues")
end





--- Closes the DB connection
function db.close()
	if (gDB) then
		gDB:close()
		gDB = nil
	end
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

	local rowsBeforeStart = lldb.arrayFromQuery(gDB, sqlBefore, {aStartTs}, "getBucketEnergyAndPower energy start before")
	local rowsAfterStart  = lldb.arrayFromQuery(gDB, sqlAfter,  {aStartTs}, "getBucketEnergyAndPower energy start after")
	local rowsBeforeEnd   = lldb.arrayFromQuery(gDB, sqlBefore, {aEndTs},   "getBucketEnergyAndPower energy end before")
	local rowsAfterEnd    = lldb.arrayFromQuery(gDB, sqlAfter,  {aEndTs},   "getBucketEnergyAndPower energy end after")

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
	local rows = lldb.arrayFromQuery(gDB, [[
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





--- Returns an array-table of statistics for days in the specified range
-- Each item has the day timeStamp, count of records and sum of timestamps (quick-n-dirty hash)
function db.getElectricityConsumptionDailyStats(aFromTimeStamp, aToTimeStamp)
	local SECONDS_PER_DAY = 24 * 60 * 60
	local startDayTS = aFromTimeStamp - aFromTimeStamp % SECONDS_PER_DAY
	local endDayTS = (aToTimeStamp + SECONDS_PER_DAY - 1) - (aToTimeStamp + SECONDS_PER_DAY - 1) % SECONDS_PER_DAY

	local res = {}
	local n = 0
	for dayTS = startDayTS, endDayTS, SECONDS_PER_DAY do
		local row = lldb.arrayFromQuery(gDB, [[
			SELECT COUNT(*) AS cnt, SUM(timeStamp) as sumTs
			FROM ElectricityConsumption
			WHERE (timeStamp >= ?) AND (timeStamp < ?)
		]], {dayTS, dayTS + SECONDS_PER_DAY}, "getElectricityConsumptionDailyStats")
		if (row and row[1]) then
			n = n + 1
			res[n] = {timeStamp = dayTS, count = row[1].cnt, sum = row[1].sumTs}
		end
	end
	res.n = n
	return res
end





--- Returns the start and end timestamps of the raw data in ElectricityConsumption table
-- Returns nil if no data at all
function db.electricityConsumptionDataRange()
	local row = lldb.arrayFromQuery(gDB, [[
		SELECT
			(SELECT timeStamp FROM ElectricityConsumption ORDER BY timeStamp ASC LIMIT 1) AS minTimeStamp,
			(SELECT timeStamp FROM ElectricityConsumption ORDER BY timeStamp DESC LIMIT 1) AS maxTimeStamp;
	]], {}, "electricityConsumptionDataRange")
	if not(row and row[1]) then
		return nil
	end
	return row[1].minTimeStamp, row[1].maxTimeStamp
end





--- Returns all the rows from ElectricityConsumption table in the specified interval
function db.getElectricityConsumptionRawData(aStartTimeStamp, aEndTimeStamp)
	assert(type(aStartTimeStamp) == "number")
	assert(type(aEndTimeStamp) == "number")

	return lldb.arrayFromQuery(gDB, [[
		SELECT * FROM ElectricityConsumption
		WHERE (timeStamp >= ?) AND (timeStamp < ?)
	]], {aStartTimeStamp, aEndTimeStamp}, "getElectricityConsumptionRawData")
end





--- Returns array-table of {timeStamp = ..., value = ...} in between the specified timestamps, for creating a power graph.
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

	return lldb.arrayFromQuery(gDB, [[
		SELECT timeStamp, ]] .. aColumnName .. [[ as value
		FROM ]] .. tableName .. [[
		WHERE timeStamp >= ? AND timeStamp <= ?
	]], {startTs, endTs}, "getGraphPowerColumnData")
end





--- Returns a single number representing the latest timestamp in the ElectricityConsumption table
-- Returns nil if no data in the table
function db.getLastElectricityConsumptionMeasurementTimestamp()
	local res = lldb.arrayFromQuery(gDB, "SELECT MAX(timeStamp) as maxTimeStamp FROM ElectricityConsumption", {}, "getLastElectricityConsumptionMeasurementTimestamp")
	if (not(res) or (res.n ~= 1)) then
		return nil
	end
	return res[1].maxTimeStamp
end





--- Returns the latest DB row in the ElectricityConsumption table
-- Returns nil if no data in the table
function db.getLatestElectricityConsumptionMeasurement()
	local res = lldb.arrayFromQuery(gDB, [[
		SELECT timeStamp, powerTotal, powerA, powerB, powerC, energyTotal, energyA, energyB, energyC
		FROM ElectricityConsumption
		ORDER BY timeStamp DESC LIMIT 1
	]], {}, "getLastElectricityConsumption")
	if (not(res) or (res.n < 1)) then
		return nil
	end
	return res[1]
end





--- Returns the tariff plan daytype schedules in an array-table
function db.getTariffPlanDayTypeSchedules()
	return lldb.arrayFromQuery(gDB, "SELECT * FROM TariffPlanDayTypeSchedules", {}, "getTariffPlanDayTypeSchedules")
end





--- Returns the tariff plan exceptionDates in an array-table
function db.getTariffPlanExceptionDates()
	return lldb.arrayFromQuery(gDB, "SELECT * FROM TariffPlanExceptionDates", {}, "getTariffPlanExceptionDates")
end





--- Returns the tariff plan seasons in an array-table
function db.getTariffPlanSeasons()
	return lldb.arrayFromQuery(gDB, "SELECT * FROM TariffPlanSeasons", {}, "getTariffPlanSeasons")
end





function db.importElectricityConsumptionRows(aRows)
	assert(gDB)
	assert(type(aRows) == "table")

	lldb.executeBoundSql(gDB, "BEGIN TRANSACTION", {}, "importElectricityConsumption.begin")
	local stmt = gDB:prepare([[
		INSERT OR IGNORE INTO ElectricityConsumption
		(timeStamp, powerTotal, powerA, powerB, powerC, energyTotal, energyA, energyB, energyC)
		VALUES
		(?, ?, ?, ?, ?, ?, ?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement (importElectricityConsumption): " .. gDB:errmsg())
	end
	for _, row in ipairs(aRows) do
		lldb.checkSql(gDB, stmt:bind_values(
			row.timeStamp,
			row.powerTotal,
			row.powerA,
			row.powerB,
			row.powerC,
			row.energyTotal,
			row.energyA,
			row.energyB,
			row.energyC
		), "importElectricityConsumption.bind")
		lldb.checkSql(gDB, stmt:step(), "importElectricityConsumption.step")
		lldb.checkSql(gDB, stmt:reset(), "importElectricityConsumption.reset")
	end
	lldb.checkSql(gDB, stmt:finalize(), "importElectricityConsumption.finalize")
	lldb.executeBoundSql(gDB, "COMMIT TRANSACTION", {}, "importElectricityConsumption.commit")
end





--- Inserts a single aggregated datapoint in the specified aggregation table
function db.insertAggregate(aTableName, aTimeStamp, aAggregatedMeasurement)
	assert(gDB)
	assert(type(aTableName) == "string")
	assert(type(aTimeStamp) == "number")
	assert(type(aAggregatedMeasurement) == "table")

	lldb.executeBoundSql(gDB, [[
		INSERT OR REPLACE INTO aggr.]] .. aTableName .. [[ (
			minPowerTotal, minPowerA, minPowerB, minPowerC,
			maxPowerTotal, maxPowerA, maxPowerB, maxPowerC,
			energyTotal, energyA, energyB, energyC,
			timeStamp
		)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	]], {
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
		aTimeStamp,
	}, "insertAggregate." .. aTableName)
end





--- Loads the energy usage in 15-minute intervals for the specified range
-- The interval starts at aFromTimestamp - aNumDaysBack*days and ends with the day-end at aFromTimestamp
function db.load15MinEnergyUsage(aFromTimestamp, aNumDaysBack)
	assert(gDB)
	assert(type(aFromTimestamp) == "number")
	assert(type(aNumDaysBack) == "number")

	local minTs = aFromTimestamp - aNumDaysBack * 24 * 60 * 60
	return lldb.arrayFromQuery(gDB, [[
		SELECT timeStamp, energyTotal
		FROM ElectricityConsumption
		WHERE (((timeStamp % 900) = 0) AND (timeStamp >= ?) AND (timeStamp <= ?) AND (energyTotal IS NOT NULL))
		ORDER BY timeStamp;
	]], { minTs, aFromTimestamp + 24 * 60 * 60 }, "load15MinEnergyUsage")
end





--- Removes the specified TariffPlan ExceptionDate
function db.removeTariffPlanExceptionDate(aExceptionDateYmd)
	assert(gDB)
	assert(type(aExceptionDateYmd) == "string")

	lldb.executeBoundSql(gDB, [[
		DELETE FROM TariffPlanExceptionDates
		WHERE exceptionDateYmd = ?
	]], {aExceptionDate}, "removeTariffPlanExceptionDate")
end





--- Replaces the TariffPlan schedules in the DB with the specified array-table
function db.replaceTariffPlanSeasons(aSeasons)
	assert(gDB)
	assert(type(aSeasons) == "table")

	lldb.executeBoundSql(gDB, "DELETE FROM TariffPlanSeasons WHERE true", {}, "replaceTariffPlanSeasons.delAll")
	local stmt = gDB:prepare([[
		INSERT INTO TariffPlanSeasons
		(startDateYmd, endDateYmd, workdayDayType, weekendDayType)
		VALUES (?, ?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement (replaceTariffPlanSeasons): " .. gDB:errmsg())
	end
	for _, season in ipairs(aSeasons) do
		lldb.checkSql(gDB, stmt:bind_values(
			season.startDateYmd,
			season.endDateYmd,
			season.workdayDayType,
			season.weekendDayType
		), "replaceTariffPlanSeasons.bind")
		lldb.checkSql(gDB, stmt:step(), "replaceTariffPlanSeasons.step")
		lldb.checkSql(gDB, stmt:reset(), "replaceTariffPlanSeasons.reset")
	end
	lldb.checkSql(gDB, stmt:finalize(), "replaceTariffPlanSeasons.finalize")
end





--- Saves an aggregate and advances its progress cursor atomically
-- aAggregatedMeasurement may be nil if the bucket contains no computable data
function db.saveAggregateBucket(aTableName, aTimeStamp, aAggregatedMeasurement, aIntervalSeconds)
	assert(gDB)
	assert(type(aTableName) == "string")
	assert(type(aTimeStamp) == "number")
	assert((type(aAggregatedMeasurement) == "table") or (aAggregatedMeasurement == nil))
	assert(type(aIntervalSeconds) == "number")

	lldb.checkSql(gDB, gDB:exec("BEGIN TRANSACTION"), "saveAggregateBucket.begin")

	local success, err = pcall(function()
		if (aAggregatedMeasurement) then
			db.insertAggregate(aTableName, aTimeStamp, aAggregatedMeasurement)
		end

		db.setAggregationProgress(aTableName, aTimeStamp - aIntervalSeconds)
	end)

	if not(success) then
		gDB:exec("ROLLBACK")
		error(err)
	end

	lldb.checkSql(gDB, gDB:exec("COMMIT"), "saveAggregateBucket.commit")
end





--- Replaces the TariffPlan dayTypes in the DB with the specified dict-table
function db.replaceTariffPlanDayTypeSchedules(aDayTypeSchedules)
	assert(gDB)
	assert(type(aDayTypeSchedules) == "table")

	lldb.executeBoundSql(gDB, "DELETE FROM TariffPlanDayTypeSchedules WHERE true", {}, "replaceTariffPlanDayTypeSchedules.delAll")
	local stmt = gDB:prepare([[
		INSERT INTO TariffPlanDayTypeSchedules
		(dayType, startMinute, endMinute, multiplier)
		VALUES (?, ?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement (replaceTariffPlanDayTypeSchedules): " .. gDB:errmsg())
	end
	for dayType, slots in pairs(aDayTypeSchedules) do
		for _, slot in ipairs(slots) do
			lldb.checkSql(gDB, stmt:bind_values(
				dayType,
				slot.startMinute,
				slot.endMinute,
				slot.multiplier
			), "replaceTariffPlanDayTypeSchedules.bind")
			lldb.checkSql(gDB, stmt:step(), "replaceTariffPlanDayTypeSchedules.step")
			lldb.checkSql(gDB, stmt:reset(), "replaceTariffPlanDayTypeSchedules.reset")
		end
	end
	lldb.checkSql(gDB, stmt:finalize(), "replaceTariffPlanDayTypeSchedules.finalize")
end





--- Replaces the TariffPlan exceptionDates in the DB with the specified dict-table
function db.replaceTariffPlanExceptionDates(aExceptionDates)
	assert(type(aExceptionDates) == "table")

	lldb.executeBoundSql(gDB, "DELETE FROM TariffPlanExceptionDates WHERE true", {}, "replaceTariffPlanExceptionDates.delAll")
	local stmt = gDB:prepare([[
		INSERT INTO TariffPlanExceptionDates
		(exceptionDateYmd, dayType)
		VALUES (?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare statement (replaceTariffPlanExceptionDates): " .. gDB:errmsg())
	end
	for excDateYmd, def in pairs(aExceptionDates) do
		lldb.checkSql(gDB, stmt:bind_values(
			excDateYmd,
			def.dayType
		), "replaceTariffPlanExceptionDates.bind")
		lldb.checkSql(gDB, stmt:step(), "replaceTariffPlanExceptionDates.step")
		lldb.checkSql(gDB, stmt:reset(), "replaceTariffPlanExceptionDates.reset")
	end
	lldb.checkSql(gDB, stmt:finalize(), "replaceTariffPlanExceptionDates.finalize")
end





--- Saves multiple 5-second buckets of electricity measurement (rows in ElectricityConsumption table)
-- Each aMeasurements[i] is a dict-able of DB column name -> value, with some columns possibly missing, and with a timeStamp
function db.saveMultipleElectricityMeasurements(aMeasurements)
	assert(type(aMeasurements) == "table")

	lldb.checkSql(gDB, gDB:exec("BEGIN TRANSACTION"), "saveMultipleElectricityMeasurements.begin")
	local stmt = gDB:prepare([[
		INSERT OR REPLACE INTO ElectricityConsumption (timeStamp, powerTotal, powerA, powerB, powerC, energyTotal, energyA, energyB, energyC)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	]])
	if not(stmt) then
		error("Failed to prepare the statement for inserting multiple electricity measurements: " .. gDB:errmsg())
	end
	for _, measurement in ipairs(aMeasurements) do
		assert(tonumber(measurement.timeStamp))
		lldb.checkSql(gDB, stmt:bind_values(
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
		lldb.checkSql(gDB, stmt:step(), "saveMultipleElectricityMeasurements.step")
		lldb.checkSql(gDB, stmt:reset(), "saveMultipleElectricityMeasurements.reset")
	end
	lldb.checkSql(gDB, stmt:finalize(), "saveMultipleElectricityMeasurements.finalize")
	lldb.checkSql(gDB, gDB:exec("COMMIT TRANSACTION"), "saveMultipleElectricityMeasurements.commit")
end





--- Saves a single 5-second bucket of electricity measurement (a single row in ElectricityConsumption table)
-- aMeasurement is a dict-table of DB column name -> value, with some columns possibly missing
function db.saveSingleElectricityMeasurement(aTimeStamp, aMeasurement)
	assert(tonumber(aTimeStamp))

	lldb.executeBoundSql(gDB, [[
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





--- Updates the tariff plan schedule for the specified day type
function db.saveTariffPlanDayTypeSchedule(aDayType, aSchedule)
	assert(type(aDayType) == "number")
	assert(type(aSchedule) == "table")
	assert(type(aSchedule[1]) == "table")

	lldb.checkSql(gDB, gDB:exec("BEGIN TRANSACTION"), "saveTariffPlanDayTypeSchedule.begin")
	lldb.executeBoundSql(gDB, "DELETE FROM TariffPlanDayTypeSchedules WHERE dayType = ?", {aDayType}, "saveTariffPlanDayTypeSchedule.delete")
	for _, slot in ipairs(aSchedule) do
		lldb.executeBoundSql(gDB, [[
			INSERT INTO TariffPlanDayTypeSchedules (dayType, startMinute, endMinute, multiplier)
			VALUES (?, ?, ?, ?)
		]], {aDayType, slot.startMinute, slot.endMinute, slot.multiplier}, "saveTariffPlanDayTypeSchedule.insert")
	end
	lldb.checkSql(gDB, gDB:exec("COMMIT TRANSACTION"), "saveTariffPlanDayTypeSchedule.commit")
end





function db.saveTariffPlanSeasons(aSeasons)
	assert(type(aSeasons) == "table")
	assert(type(aSeasons.n) == "number")

	lldb.checkSql(gDB, gDB:exec("BEGIN TRANSACTION"), "saveTariffPlanSeasons.begin")
	lldb.executeBoundSql(gDB, "DELETE FROM TariffPlanSeasons WHERE TRUE", {}, "saveTariffPlanSeasons.delete")
	for _, season in ipairs(aSeasons) do
		lldb.executeBoundSql(gDB, [[
			INSERT INTO TariffPlanSeasons (startDateYmd, endDateYmd, workdayDayType, weekendDayType)
			VALUES (?, ?, ?, ?)
		]], {season.startDateYmd, season.endDateYmd, season.workdayDayType, season.weekendDayType}, "saveTariffPlanSeasons.insert")
	end
	lldb.checkSql(gDB, gDB:exec("COMMIT TRANSACTION"), "saveTariffPlanSeasons.commit")
end





--- Sets the next bucket to process for an aggregation table
function db.setAggregationProgress(aTableName, aNextBucket)
	assert(type(aTableName) == "string")
	assert((type(aNextBucket) == "number") or (aNextBucket == nil))

	lldb.executeBoundSql(gDB, [[
		INSERT OR REPLACE INTO aggr.AggregationProgress (tableName, nextBucket)
		VALUES (?, ?)
	]], {aTableName, aNextBucket}, "setAggregationProgress")
end





initialize()
return db
