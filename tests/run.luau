-- Unit tests for the pure game-rule modules in src/shared.
-- Run from the happy-pets folder with:  lune run tests/run
--
-- The modules use Roblox-style `require(script.Parent.X)`, so this runner
-- loads them with a small fake `script` and Lune's Roblox datatypes.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any
local process = require("@lune/process")

local SHARED = "src/shared/"
local cache: { [string]: any } = {}

local function loadModule(name: string): any
	if cache[name] ~= nil then
		return cache[name]
	end
	local source = fs.readFile(SHARED .. name .. ".luau")
	local parent = setmetatable({}, {
		__index = function(_, child)
			return { __module = child }
		end,
	})
	local env = setmetatable({
		script = { Parent = parent, Name = name },
		require = function(target: any)
			return loadModule(target.__module)
		end,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
	}, { __index = _G })
	local fn = luau.load(source, { debugName = name, environment = env })
	local result = fn()
	cache[name] = result
	return result
end

local Config = loadModule("Config")
local Rng = loadModule("Rng")
local Economy = loadModule("Economy")
local Placement = loadModule("Placement")
local PetRules = loadModule("PetRules")
local SaveSchema = loadModule("SaveSchema")

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end

local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2)
	end
end

local function truthy(v: any, msg: string?)
	if not v then
		error(msg or "expected a truthy value", 2)
	end
end

local NOW = 1_800_000_000

---------------------------------------------------------------------------

test("Rng is deterministic and in range", function()
	local a, b = Rng.new(42), Rng.new(42)
	for _ = 1, 100 do
		local x = a:Range(1, 6)
		eq(x, b:Range(1, 6))
		truthy(x >= 1 and x <= 6)
		local f = a:Float()
		b:Float()
		truthy(f >= 0 and f < 1)
	end
	eq(Rng.Hash("a", 1), Rng.Hash("a", 1))
	truthy(Rng.Hash("a", 1) ~= Rng.Hash("a", 2))
end)

test("new save is valid and has starter furniture placed legally", function()
	local data = SaveSchema.Default(NOW)
	eq(data.coins, Config.Start.Coins)
	eq(#data.rooms, 1)
	eq(#data.rooms[1].furniture, #Config.Start.Furniture)
	local placed = {}
	for _, f in data.rooms[1].furniture do
		truthy(Placement.Validate(placed, f.item, f.cx, f.cz, f.rot), "starter " .. f.item .. " overlaps")
		table.insert(placed, f)
	end
end)

test("save round-trips and repairs corruption", function()
	local data = SaveSchema.Default(NOW)
	data.pets.p99 = PetRules.NewPet("p99", "Cat", { color = "Orange", pattern = "Tabby", eyes = "Green" }, "Mittens", "F", "Adult", NOW, "living")
	local loaded, repairs = SaveSchema.Load(data, NOW)
	eq(#repairs, 0)
	eq(loaded.pets.p99.name, "Mittens")
	eq(loaded.pets.p99.pattern, "Tabby")

	local broken = {
		coins = -50,
		level = "seven",
		pets = { bad = { species = "Dragon" }, p1 = { species = "Dog", color = "Neon", needs = { Food = 999 } } },
		inventory = { kibble = 3, nonsense = 4 },
		rooms = { { id = "living", furniture = { { uid = "f1", item = "pet_bed", cx = 50, cz = 0, rot = 0 } } } },
	}
	local fixed, rep = SaveSchema.Load(broken, NOW)
	eq(fixed.coins, 0)
	eq(fixed.level, 1)
	eq(fixed.pets.bad, nil)
	eq(fixed.pets.p1.color, "Golden")
	eq(fixed.pets.p1.needs.Food, 100)
	eq(fixed.inventory.kibble, 3)
	eq(fixed.inventory.nonsense, nil)
	eq(fixed.inventory.pet_bed, 1, "out-of-room furniture returns to inventory")
	truthy(#rep > 0)

	local fromNothing = SaveSchema.Load(nil, NOW)
	eq(fromNothing.coins, Config.Start.Coins)
	local fromString = SaveSchema.Load("garbage", NOW)
	eq(fromString.level, 1)
end)

test("settings default on and survive a reload", function()
	local data = SaveSchema.Default(NOW)
	eq(data.settings.sound, true)
	eq(data.settings.music, true)
	data.settings.music = false
	local loaded = SaveSchema.Load(data, NOW)
	eq(loaded.settings.music, false)
	eq(loaded.settings.sound, true)
	-- Saves from before the music setting existed get music on.
	eq(SaveSchema.Load({ settings = { sound = false } }, NOW).settings.music, true)
end)

test("audio config covers every species", function()
	for species in Config.Species do
		local sounds = Config.Audio.Pets[species]
		truthy(sounds, species .. " has a sound set")
		for _, kind in Config.Audio.PetKinds do
			truthy(typeof(sounds[kind]) == "table", species .. "." .. kind)
		end
	end
end)

test("spending never goes negative", function()
	local data = SaveSchema.Default(NOW)
	data.coins = 30
	eq(Economy.Spend(data, 50), false)
	eq(data.coins, 30)
	eq(Economy.Spend(data, -10), false)
	eq(Economy.Spend(data, 0 / 0), false)
	eq(Economy.Spend(data, 30), true)
	eq(data.coins, 0)
end)

test("XP levels up and pays a reward", function()
	local data = SaveSchema.Default(NOW)
	local start = data.coins
	local reached, bonus = Economy.AddXP(data, Config.XPToNext(1) + 5)
	eq(data.level, 2)
	eq(data.xp, 5)
	eq(#reached, 1)
	eq(bonus, Config.LevelReward(2))
	eq(data.coins, start + bonus)
	-- A huge gain crosses several levels at once.
	local r2 = Economy.AddXP(data, 10000)
	truthy(#r2 > 1)
end)

test("inventory take/add", function()
	local data = SaveSchema.Default(NOW)
	data.inventory = {}
	eq(Economy.TakeItem(data, "kibble", 1), false)
	Economy.AddItem(data, "kibble", 2)
	eq(Economy.TakeItem(data, "kibble", 1), true)
	eq(Economy.TakeItem(data, "kibble", 1), true)
	eq(data.inventory.kibble, nil)
end)

test("placement rejects overlap and out of bounds, rugs layer separately", function()
	local furniture = { { uid = "a", item = "pet_bed", cx = 2, cz = 2, rot = 0 } }
	eq((Placement.Validate(furniture, "sofa", 3, 3, 0)), false)
	eq((Placement.Validate(furniture, "sofa", 4, 2, 0)), true)
	eq((Placement.Validate(furniture, "sofa", Placement.Cols - 2, 0, 0)), false)
	eq((Placement.Validate(furniture, "sofa", Placement.Cols - 1, 0, 1)), true, "rotated sofa is 1 wide")
	eq((Placement.Validate(furniture, "sofa", 1.5, 0, 0)), false)
	eq((Placement.Validate(furniture, "sofa", 4, 2, 5)), false)
	eq((Placement.Validate(furniture, "rug_round", 1, 1, 0)), true, "rug under a bed is fine")
	-- Moving an item onto its own spot is fine.
	eq((Placement.Validate(furniture, "pet_bed", 2, 2, 0, "a")), true)
	eq((Placement.Validate(furniture, "kibble", 0, 0, 0)), false)
end)

test("cell <-> local conversion round-trips", function()
	for _, rot in { 0, 1 } do
		for cx = 0, Placement.Cols - 3 do
			local x, z = Placement.CellToLocal("sofa", cx, 4, rot)
			local bx, bz = Placement.LocalToCell("sofa", x, z, rot)
			eq(bx, cx)
			eq(bz, 4)
		end
	end
end)

test("needs decay over time and a tired pet sleeps then wakes", function()
	local pet = PetRules.NewPet("p1", "Cat", { color = "Orange", pattern = "Solid", eyes = "Green" }, "Tom", "M", "Adult", NOW, "living")
	local env = { comfort = 0, litter = false, hasBed = true }
	PetRules.Simulate(pet, 600, env)
	truthy(pet.needs.Food < 80)
	truthy(pet.needs.Energy < 90)
	pet.needs.Energy = 11
	PetRules.Simulate(pet, 600, env)
	eq(pet.sleeping, true, "falls asleep when tired")
	PetRules.Simulate(pet, 3600, env)
	eq(pet.sleeping, false, "wakes once rested")
	eq(pet.needs.Energy >= 85, true)
end)

test("a long absence is forgiving", function()
	local pet = PetRules.NewPet("p1", "Dog", { color = "Golden", pattern = "Solid", eyes = "Brown" }, "Rex", "M", "Adult", NOW, "living")
	PetRules.Simulate(pet, Config.MaxOfflineHours * 3600, { comfort = 0, litter = false, hasBed = false })
	eq(pet.needs.Health >= Config.Decay.HealthMin, true)
	for _, need in Config.Needs do
		truthy(pet.needs[need] >= 0 and pet.needs[need] <= 100)
	end
end)

test("comfort slows fun loss", function()
	local a = PetRules.NewPet("a", "Cat", { color = "Orange", pattern = "Solid", eyes = "Green" }, "A", "M", "Adult", NOW, "living")
	local b = PetRules.NewPet("b", "Cat", { color = "Orange", pattern = "Solid", eyes = "Green" }, "B", "M", "Adult", NOW, "living")
	PetRules.Simulate(a, 1200, { comfort = 0, litter = false, hasBed = false })
	PetRules.Simulate(b, 1200, { comfort = 20, litter = true, hasBed = false })
	truthy(b.needs.Fun > a.needs.Fun)
	truthy(b.needs.Clean > a.needs.Clean)
end)

test("babies grow up with care or time", function()
	local pet = PetRules.NewPet("p", "Cat", { color = "Orange", pattern = "Solid", eyes = "Green" }, "Bean", "F", "Baby", NOW, "living")
	eq(PetRules.Grow(pet, NOW + 10), false)
	pet.careCount = Config.Growth.AdultAfterCare
	eq(PetRules.Grow(pet, NOW + 10), true)
	eq(pet.stage, "Adult")
	local pet2 = PetRules.NewPet("q", "Cat", { color = "Orange", pattern = "Solid", eyes = "Green" }, "Bean", "F", "Baby", NOW, "living")
	eq(PetRules.Grow(pet2, NOW + Config.Growth.AdultAfterSeconds), true)
end)

test("breeding rules", function()
	local look = { color = "Orange", pattern = "Tabby", eyes = "Green" }
	local m = PetRules.NewPet("m", "Cat", look, "M", "M", "Adult", NOW, "living")
	local f = PetRules.NewPet("f", "Cat", { color = "Black", pattern = "Solid", eyes = "Amber" }, "F", "F", "Adult", NOW, "living")
	local d = PetRules.NewPet("d", "Dog", { color = "Golden", pattern = "Solid", eyes = "Brown" }, "D", "F", "Adult", NOW, "living")
	eq((PetRules.CanBreed(m, f, NOW)), true)
	eq((PetRules.CanBreed(m, m, NOW)), false)
	eq((PetRules.CanBreed(m, d, NOW)), false)
	f.lastBredAt = NOW - 10
	eq((PetRules.CanBreed(m, f, NOW)), false, "cooldown")
	f.lastBredAt = 0
	f.stage = "Baby"
	eq((PetRules.CanBreed(m, f, NOW)), false, "babies can't breed")
	f.stage = "Adult"

	-- Same seed, same baby; traits are valid for the species.
	local def = Config.Species.Cat
	local seen = {}
	for seed = 1, 300 do
		local a1 = PetRules.Inherit(m, f, seed)
		local a2 = PetRules.Inherit(m, f, seed)
		eq(a1.color, a2.color)
		eq(a1.pattern, a2.pattern)
		truthy(table.find(def.Colors, a1.color) or table.find(def.RareColors, a1.color))
		truthy(table.find(def.Patterns, a1.pattern) or table.find(def.RarePatterns, a1.pattern))
		seen[a1.color] = true
	end
	truthy(seen.Orange and seen.Black, "both parents' colours appear")
end)

test("adoption candidates are reproducible and priced", function()
	local seed = PetRules.AdoptionSeed(123, 20000, 0)
	local a = PetRules.AdoptionCandidates(seed, "Cat")
	local b = PetRules.AdoptionCandidates(seed, "Cat")
	eq(#a, Config.Adoption.PerSpecies)
	for i = 1, #a do
		eq(a[i].look.color, b[i].look.color)
		eq(a[i].price, PetRules.AdoptPrice("Cat", a[i].look))
	end
	local other = PetRules.AdoptionCandidates(PetRules.AdoptionSeed(123, 20000, 1), "Cat")
	local differs = false
	for i = 1, #a do
		differs = differs or a[i].look.color ~= other[i].look.color or a[i].look.pattern ~= other[i].look.pattern
	end
	truthy(differs, "reroll changes the list")
end)

test("pet names are cleaned", function()
	eq(PetRules.CleanName("  Mr   Whiskers "), "Mr Whiskers")
	eq(PetRules.CleanName(""), nil)
	eq(PetRules.CleanName("   "), nil)
	eq(PetRules.CleanName(string.rep("a", 21)), nil)
	eq(PetRules.CleanName("<b>hi</b>"), nil)
	eq(PetRules.CleanName(42), nil)
	eq(PetRules.CleanName("O'Malley-2!"), "O'Malley-2!")
end)

test("capacity and room space", function()
	local data = SaveSchema.Default(NOW)
	eq(Economy.PetCapacity(data), Config.Rooms[1].Capacity)
	for i = 1, Config.Rooms[1].Capacity do
		data.pets["p" .. i] = PetRules.NewPet("p" .. i, "Cat", { color = "Orange", pattern = "Solid", eyes = "Green" }, "C", "M", "Adult", NOW, "living")
	end
	eq(Economy.RoomWithSpace(data), nil)
	table.insert(data.rooms, SaveSchema.NewRoom(Config.Rooms[2]))
	eq(Economy.RoomWithSpace(data), "bedroom")
end)

test("every item and species is well formed", function()
	for id, item in Config.Items do
		truthy(item.Name and item.Price and item.Level and item.Tab, id)
		truthy(table.find(Config.ShopTabs, item.Tab), id .. " tab")
		if item.Kind == "Furniture" then
			truthy(item.Footprint and item.Footprint[1] >= 1 and item.Footprint[2] >= 1, id)
		else
			truthy(item.Action and item.Effects, id)
		end
	end
	for id, s in Config.Species do
		truthy(table.find(Config.SpeciesOrder, id), id)
		truthy(Config.Items[s.Favorite], id .. " favourite food")
		for _, c in s.Colors do
			truthy(Config.Colors[c], c)
		end
		for _, c in s.RareColors do
			truthy(Config.Colors[c], c)
		end
		for _, e in s.Eyes do
			truthy(Config.EyeColors[e], e)
		end
		for _, e in s.RareEyes do
			truthy(Config.EyeColors[e], e)
		end
	end
	for _, room in Config.Rooms do
		truthy(Config.WallpaperById(room.Wallpaper) and Config.FloorById(room.Floor), room.Id)
	end
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
