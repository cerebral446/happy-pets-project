-- Loading and saving player data with a DataStore.
--
-- If DataStores are unavailable (Studio without "Enable Studio Access to API
-- Services", or an unpublished place) the game still runs with a fresh save
-- that isn't kept, and the client shows "Not saving".
--
-- A light session lock stops two servers from writing the same save at once
-- when a player hops between servers quickly.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SaveSchema = require(Shared:WaitForChild("SaveSchema"))

local DataService = {}

local LOCK_SECONDS = 90

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[HappyPets] DataStores unavailable, progress won't be saved:", result)
	end
end

local function key(userId: number): string
	return "player_" .. userId
end

local function retry<T>(attempts: number, fn: () -> T): (boolean, T | string)
	local lastErr: any = nil
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if i < attempts then
			task.wait(1.5 * i)
		end
	end
	return false, tostring(lastErr)
end

-- Returns the player's data and whether it will be saved.
function DataService.Load(player: Player): (any, boolean)
	local now = os.time()
	if not store then
		return SaveSchema.Default(now), false
	end
	local raw: any = nil
	local jobId = game.JobId
	-- Claim the save. If another server holds a fresh lock, wait for it to
	-- finish saving (it releases on leave) before taking over.
	for attempt = 1, 6 do
		local blocked = false
		local ok, err = retry(3, function()
			return (store :: DataStore):UpdateAsync(key(player.UserId), function(old)
				if typeof(old) == "table" and typeof(old.session) == "table" then
					local s = old.session
					if s.job ~= jobId and typeof(s.at) == "number" and os.time() - s.at < LOCK_SECONDS and attempt < 6 then
						blocked = true
						raw = old
						return nil
					end
				end
				raw = old
				if typeof(old) == "table" then
					old.session = { job = jobId, at = os.time() }
					return old
				end
				return nil
			end)
		end)
		if not ok then
			warn("[HappyPets] Couldn't load data for", player.Name, err)
			return SaveSchema.Default(now), false
		end
		if not blocked then
			break
		end
		task.wait(5)
		if not player.Parent then
			return SaveSchema.Default(now), false
		end
	end
	local data, repairs = SaveSchema.Load(raw, now)
	if #repairs > 0 then
		warn("[HappyPets] Repaired save for", player.Name, table.concat(repairs, "; "))
	end
	return data, true
end

-- Writes the data. `release` drops the session lock (on leave).
function DataService.Save(player: Player, data: any, release: boolean): boolean
	if not store then
		return false
	end
	data.lastSeen = os.time()
	local jobId = game.JobId
	local ok, err = retry(3, function()
		return (store :: DataStore):UpdateAsync(key(player.UserId), function(old)
			-- Another server took over (we lost the lock): don't overwrite it.
			if typeof(old) == "table" and typeof(old.session) == "table" and old.session.job ~= jobId and os.time() - (old.session.at or 0) < LOCK_SECONDS then
				return nil
			end
			local copy = table.clone(data)
			copy.session = if release then nil else { job = jobId, at = os.time() }
			return copy
		end)
	end)
	if not ok then
		warn("[HappyPets] Save failed for", player.Name, err)
	end
	return ok
end

-- Deletes the save (used by "Reset save").
function DataService.Reset(player: Player): boolean
	if not store then
		return true
	end
	local ok = retry(3, function()
		return (store :: DataStore):RemoveAsync(key(player.UserId))
	end)
	return ok
end

function DataService.Available(): boolean
	return store ~= nil
end

return DataService
