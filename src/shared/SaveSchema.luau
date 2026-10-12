-- The save file: its default contents, migrations between versions, and a
-- sanitizer that repairs missing or corrupted fields instead of failing.
--
-- Layout (version 1):
--   version, coins, xp, level, createdAt, lastSeen
--   nextId                    counter for pet and furniture ids
--   pets       { [petId]: Pet }            (see PetRules.NewPet)
--   inventory  { [itemId]: count }         unplaced furniture and consumables
--   rooms      { { id, wallpaper, floor, furniture = { {uid, item, cx, cz, rot} } } }
--   styles     { [styleId]: true }         bought wallpapers and floors
--   births     { { id, species, parents = {a, b}, seed, readyAt } }
--   adopt      { day, rerolls, taken = { ["Cat:2"] = true } }
--   daily      { day }                     last daily bonus claimed
--   visits     { day, count, petted = { [key] = true } }
--   settings   { sound, music }
--   stats      { care, adopted, bred, gifts }
--   starterDone                            first free kitten taken

local Config = require(script.Parent.Config)
local Placement = require(script.Parent.Placement)

local SaveSchema = {}

local function newRoom(def: any): any
	return { id = def.Id, wallpaper = def.Wallpaper, floor = def.Floor, furniture = {} }
end

function SaveSchema.NewRoom(def: any): any
	return newRoom(def)
end

function SaveSchema.Default(now: number): any
	local data = {
		version = Config.SaveVersion,
		coins = Config.Start.Coins,
		xp = 0,
		level = 1,
		createdAt = now,
		lastSeen = now,
		nextId = 1,
		pets = {},
		inventory = {},
		rooms = { newRoom(Config.Rooms[1]) },
		styles = {},
		births = {},
		adopt = { day = 0, rerolls = 0, taken = {} },
		daily = { day = 0 },
		visits = { day = 0, count = 0, petted = {} },
		settings = { sound = true, music = true },
		stats = { care = 0, adopted = 0, bred = 0, gifts = 0 },
		starterDone = false,
	}
	for itemId, count in Config.Start.Inventory do
		data.inventory[itemId] = count
	end
	local living = data.rooms[1]
	for _, f in Config.Start.Furniture do
		table.insert(living.furniture, { uid = "f" .. data.nextId, item = f.item, cx = f.cx, cz = f.cz, rot = f.rot })
		data.nextId += 1
	end
	return data
end

-- Migrations from version N to N + 1. Add one for every SaveVersion bump.
local MIGRATIONS: { [number]: (any) -> () } = {
	-- [1] = function(data) data.newField = ...; end,
}

local function num(v: any, default: number, min: number?, max: number?): number
	if typeof(v) ~= "number" or v ~= v then
		return default
	end
	if min then
		v = math.max(min, v)
	end
	if max then
		v = math.min(max, v)
	end
	return v
end

local function tbl(v: any): { [any]: any }
	return if typeof(v) == "table" then v else {}
end

local function sanitizePet(id: string, p: any, now: number): any?
	if typeof(p) ~= "table" or not Config.Species[p.species] then
		return nil
	end
	local def = Config.Species[p.species]
	local function pickValid(v: any, common: { string }, rare: { string }): string
		if typeof(v) == "string" and (table.find(common, v) or table.find(rare, v)) then
			return v
		end
		return common[1]
	end
	local needs = tbl(p.needs)
	local pet = {
		id = id,
		name = if typeof(p.name) == "string" and #p.name > 0 then string.sub(p.name, 1, 20) else "Pet",
		gender = if p.gender == "F" then "F" else "M",
		species = p.species,
		color = pickValid(p.color, def.Colors, def.RareColors),
		pattern = pickValid(p.pattern, def.Patterns, def.RarePatterns),
		eyes = pickValid(p.eyes, def.Eyes, def.RareEyes),
		stage = if p.stage == "Baby" then "Baby" else "Adult",
		bornAt = num(p.bornAt, now),
		careCount = num(p.careCount, 0, 0),
		room = if typeof(p.room) == "string" then p.room else "living",
		x = num(p.x, 0, -Config.Room.Width / 2, Config.Room.Width / 2),
		z = num(p.z, 0, -Config.Room.Depth / 2, Config.Room.Depth / 2),
		needs = {},
		sleeping = p.sleeping == true,
		lastBredAt = num(p.lastBredAt, 0),
		lastGiftAt = num(p.lastGiftAt, now),
		cooldowns = {},
		parents = nil,
	}
	for _, need in Config.Needs do
		pet.needs[need] = num(needs[need], 80, 0, 100)
	end
	for action, t in tbl(p.cooldowns) do
		if typeof(action) == "string" and typeof(t) == "number" then
			pet.cooldowns[action] = t
		end
	end
	if typeof(p.parents) == "table" and typeof(p.parents[1]) == "string" and typeof(p.parents[2]) == "string" then
		pet.parents = { p.parents[1], p.parents[2] }
	end
	return pet
end

-- Brings any stored value up to the current layout. Never errors: unknown or
-- broken parts are replaced with defaults. Returns the data and a list of
-- repairs made (empty for a healthy save).
function SaveSchema.Load(raw: any, now: number): (any, { string })
	local repairs = {}
	if typeof(raw) ~= "table" then
		return SaveSchema.Default(now), {}
	end
	local version = num(raw.version, 1)
	if version > Config.SaveVersion then
		-- Saved by a newer build; keep what we understand.
		table.insert(repairs, "save from newer version " .. version)
	end
	while version < Config.SaveVersion do
		local migrate = MIGRATIONS[version]
		if migrate then
			migrate(raw)
		end
		version += 1
	end

	local data = SaveSchema.Default(now)
	data.coins = math.floor(num(raw.coins, Config.Start.Coins, 0))
	data.level = math.floor(num(raw.level, 1, 1, Config.MaxLevel))
	data.xp = math.floor(num(raw.xp, 0, 0))
	data.createdAt = num(raw.createdAt, now)
	data.lastSeen = num(raw.lastSeen, now, 0, now)
	data.nextId = math.floor(num(raw.nextId, 1, 1))
	data.starterDone = raw.starterDone == true

	data.inventory = {}
	for itemId, count in tbl(raw.inventory) do
		if Config.Items[itemId] and typeof(count) == "number" and count >= 1 then
			data.inventory[itemId] = math.floor(count)
		end
	end

	-- Rooms: keep known ones in unlock order, always including the first.
	local rawRooms = tbl(raw.rooms)
	local byId = {}
	for _, r in rawRooms do
		if typeof(r) == "table" and typeof(r.id) == "string" then
			byId[r.id] = r
		end
	end
	data.rooms = {}
	local usedIds = {}
	for i, def in Config.Rooms do
		local r = byId[def.Id]
		if not r and i > 1 then
			break
		end
		local room = newRoom(def)
		if r then
			if typeof(r.wallpaper) == "string" and Config.WallpaperById(r.wallpaper) then
				room.wallpaper = r.wallpaper
			end
			if typeof(r.floor) == "string" and Config.FloorById(r.floor) then
				room.floor = r.floor
			end
			for _, f in tbl(r.furniture) do
				if typeof(f) ~= "table" or typeof(f.uid) ~= "string" or usedIds[f.uid] then
					continue
				end
				local rot = num(f.rot, 0, 0, 3)
				local cx, cz = num(f.cx, -1), num(f.cz, -1)
				if Config.Items[f.item] and Placement.Validate(room.furniture, f.item, cx, cz, rot) then
					table.insert(room.furniture, { uid = f.uid, item = f.item, cx = cx, cz = cz, rot = rot })
					usedIds[f.uid] = true
				elseif Config.Items[f.item] and Config.Items[f.item].Kind == "Furniture" then
					-- Doesn't fit any more: return it to the inventory.
					data.inventory[f.item] = (data.inventory[f.item] or 0) + 1
					table.insert(repairs, "returned " .. f.item .. " to inventory")
				end
			end
		end
		table.insert(data.rooms, room)
	end

	data.styles = {}
	for styleId, owned in tbl(raw.styles) do
		if owned == true and (Config.WallpaperById(styleId) or Config.FloorById(styleId)) then
			data.styles[styleId] = true
		end
	end

	data.pets = {}
	for id, p in tbl(raw.pets) do
		if typeof(id) == "string" then
			local pet = sanitizePet(id, p, now)
			if pet then
				local known = false
				for _, room in data.rooms do
					known = known or room.id == pet.room
				end
				if not known then
					pet.room = data.rooms[1].id
				end
				data.pets[id] = pet
			else
				table.insert(repairs, "dropped unreadable pet " .. id)
			end
		end
	end

	data.births = {}
	for _, b in tbl(raw.births) do
		if typeof(b) == "table" and Config.Species[b.species] and typeof(b.id) == "string" then
			table.insert(data.births, {
				id = b.id,
				species = b.species,
				parents = if typeof(b.parents) == "table" then { tostring(b.parents[1]), tostring(b.parents[2]) } else { "", "" },
				look = b.look,
				readyAt = num(b.readyAt, now),
			})
		end
	end
	-- The baby's look is fixed when breeding starts; drop births without one.
	for i = #data.births, 1, -1 do
		local look = data.births[i].look
		if typeof(look) ~= "table" or typeof(look.color) ~= "string" or typeof(look.pattern) ~= "string" or typeof(look.eyes) ~= "string" then
			table.remove(data.births, i)
		end
	end

	local adopt = tbl(raw.adopt)
	data.adopt = { day = num(adopt.day, 0), rerolls = num(adopt.rerolls, 0, 0), taken = {} }
	for key, v in tbl(adopt.taken) do
		if typeof(key) == "string" and v == true then
			data.adopt.taken[key] = true
		end
	end
	data.daily = { day = num(tbl(raw.daily).day, 0) }
	local visits = tbl(raw.visits)
	data.visits = { day = num(visits.day, 0), count = num(visits.count, 0, 0), petted = {} }
	for key, v in tbl(visits.petted) do
		if typeof(key) == "string" and v == true then
			data.visits.petted[key] = true
		end
	end
	data.settings = { sound = tbl(raw.settings).sound ~= false, music = tbl(raw.settings).music ~= false }
	local stats = tbl(raw.stats)
	data.stats = {
		care = num(stats.care, 0, 0),
		adopted = num(stats.adopted, 0, 0),
		bred = num(stats.bred, 0, 0),
		gifts = num(stats.gifts, 0, 0),
	}
	data.version = Config.SaveVersion
	return data, repairs
end

function SaveSchema.NewId(data: any, prefix: string): string
	local id = prefix .. data.nextId
	data.nextId += 1
	return id
end

return SaveSchema
