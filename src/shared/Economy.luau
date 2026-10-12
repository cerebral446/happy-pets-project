-- Coins, XP, levels and unlock rules. Pure functions on the save data table,
-- with no Roblox APIs, so they run in the tests too.

local Config = require(script.Parent.Config)

local Economy = {}

function Economy.DayIndex(now: number): number
	return now // 86400
end

function Economy.CanAfford(data: any, price: number): boolean
	return price >= 0 and data.coins >= price
end

-- Deducts `price` if the player can afford it. Never leaves a negative balance.
function Economy.Spend(data: any, price: number): boolean
	if price ~= price or price < 0 or data.coins < price then
		return false
	end
	data.coins -= price
	return true
end

function Economy.AddCoins(data: any, amount: number)
	if amount > 0 then
		data.coins += math.floor(amount)
	end
end

-- Adds XP and processes level-ups. Returns the list of levels reached and the
-- coins those level-ups awarded.
function Economy.AddXP(data: any, amount: number): ({ number }, number)
	local reached = {}
	local bonus = 0
	if amount <= 0 then
		return reached, bonus
	end
	data.xp += math.floor(amount)
	while data.level < Config.MaxLevel and data.xp >= Config.XPToNext(data.level) do
		data.xp -= Config.XPToNext(data.level)
		data.level += 1
		local reward = Config.LevelReward(data.level)
		data.coins += reward
		bonus += reward
		table.insert(reached, data.level)
	end
	if data.level >= Config.MaxLevel then
		data.xp = math.min(data.xp, Config.XPToNext(data.level))
	end
	return reached, bonus
end

-- Everything that unlocks exactly at `level`, as display names.
function Economy.UnlocksAt(level: number): { string }
	local list = {}
	for _, id in Config.SpeciesOrder do
		local s = Config.Species[id]
		if s.Level == level then
			table.insert(list, "Adopt " .. s.Name .. "s")
		end
	end
	for _, room in Config.Rooms do
		if room.Level == level and room.Price > 0 then
			table.insert(list, room.Name)
		end
	end
	local items = {}
	for _, item in Config.Items do
		if item.Level == level then
			table.insert(items, item.Name)
		end
	end
	for _, w in Config.Wallpapers do
		if w.Level == level and w.Price > 0 then
			table.insert(items, w.Name .. " wallpaper")
		end
	end
	for _, f in Config.Floors do
		if f.Level == level and f.Price > 0 then
			table.insert(items, f.Name .. " floor")
		end
	end
	table.sort(items)
	for _, name in items do
		table.insert(list, name)
	end
	return list
end

-- Total pets the player's unlocked rooms can hold.
function Economy.PetCapacity(data: any): number
	local total = 0
	for _, room in data.rooms do
		local def = Config.RoomById(room.id)
		if def then
			total += def.Capacity
		end
	end
	return total
end

function Economy.PetCount(data: any): number
	local n = 0
	for _ in data.pets do
		n += 1
	end
	return n
end

function Economy.PetsInRoom(data: any, roomId: string): number
	local n = 0
	for _, pet in data.pets do
		if pet.room == roomId then
			n += 1
		end
	end
	return n
end

-- First unlocked room with a free space, or nil.
function Economy.RoomWithSpace(data: any, preferred: string?): string?
	if preferred then
		local def = Config.RoomById(preferred)
		if def and Economy.HasRoom(data, preferred) and Economy.PetsInRoom(data, preferred) < def.Capacity then
			return preferred
		end
	end
	for _, room in data.rooms do
		local def = Config.RoomById(room.id)
		if def and Economy.PetsInRoom(data, room.id) < def.Capacity then
			return room.id
		end
	end
	return nil
end

function Economy.HasRoom(data: any, roomId: string): boolean
	for _, room in data.rooms do
		if room.id == roomId then
			return true
		end
	end
	return false
end

function Economy.GetRoom(data: any, roomId: string): any
	for _, room in data.rooms do
		if room.id == roomId then
			return room
		end
	end
	return nil
end

-- The next room that can be bought, if any.
function Economy.NextRoom(data: any): any
	for _, def in Config.Rooms do
		if not Economy.HasRoom(data, def.Id) then
			return def
		end
	end
	return nil
end

function Economy.InventoryCount(data: any, itemId: string): number
	return data.inventory[itemId] or 0
end

function Economy.AddItem(data: any, itemId: string, count: number)
	data.inventory[itemId] = (data.inventory[itemId] or 0) + count
end

function Economy.TakeItem(data: any, itemId: string, count: number): boolean
	local have = data.inventory[itemId] or 0
	if have < count then
		return false
	end
	if have == count then
		data.inventory[itemId] = nil
	else
		data.inventory[itemId] = have - count
	end
	return true
end

function Economy.OwnsStyle(data: any, kind: string, styleId: string): boolean
	local def = if kind == "Wallpaper" then Config.WallpaperById(styleId) else Config.FloorById(styleId)
	if not def then
		return false
	end
	if def.Price == 0 then
		return true
	end
	return data.styles[styleId] == true
end

-- Gift and visit rewards scale gently with level.
function Economy.GiftCoins(data: any): number
	return Config.Gift.Coins + Config.Gift.CoinsPerLevel * (data.level - 1)
end

function Economy.DailyCoins(data: any): number
	return Config.Daily.Coins + Config.Daily.PerLevel * (data.level - 1)
end

return Economy
