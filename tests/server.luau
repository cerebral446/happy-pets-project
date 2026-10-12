-- Headless integration test of the server game logic: builds a player's
-- home, then adopts, cares for, decorates, breeds and visits through the
-- real Actions / Plots / PetService modules. Engine-only methods (PivotTo,
-- text filtering, server time) are shimmed with Lune's implementMethod.
-- Run from the happy-pets folder with:  lune run tests/server

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any
local process = require("@lune/process")

local Instance, CFrame = roblox.Instance, roblox.CFrame

---------------------------------------------------------------------------
-- Engine shims
---------------------------------------------------------------------------

local clock = 1_800_000_000
local function waitForChild(self, name)
	local child = self:FindFirstChild(name)
	assert(child, "WaitForChild would hang: " .. self.Name .. "." .. name)
	return child
end
for _, cls in { "Folder", "ReplicatedStorage", "ServerScriptService", "Model", "DataModel", "Workspace" } do
	roblox.implementMethod(cls, "WaitForChild", waitForChild)
end
local function getPivot(self)
	if self.PrimaryPart then
		return self.PrimaryPart.CFrame * self.PrimaryPart.PivotOffset
	end
	return self.WorldPivot
end
roblox.implementMethod("Model", "GetPivot", getPivot)
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	local delta = cf * getPivot(self):Inverse()
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
	if not self.PrimaryPart then
		self.WorldPivot = cf
	end
end)
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return clock
end)
roblox.implementMethod("TextService", "FilterStringAsync", function(_, text)
	return {
		GetNonChatStringForBroadcastAsync = function()
			return if string.find(text, "Badword") then string.rep("#", #text) else text
		end,
	}
end)

local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local shared = Instance.new("Folder")
shared.Name = "Shared"
shared.Parent = game:GetService("ReplicatedStorage")
local sss = game:GetService("ServerScriptService")
for _, entry in { { "src/shared", shared }, { "src/server", sss } } do
	for _, file in fs.readDir(entry[1]) do
		if string.sub(file, -5) == ".luau" and not string.find(file, "%.server%.") then
			local ms = Instance.new("ModuleScript")
			ms.Name = string.sub(file, 1, -6)
			ms:SetAttribute("Path", entry[1] .. "/" .. file)
			ms.Parent = entry[2]
		end
	end
end

local Random = {}
function Random.new(seed)
	local s = seed or 1
	return {
		NextNumber = function(_, a, b)
			s = (s * 1103515245 + 12345) % 2147483648
			return a + (b - a) * (s / 2147483648)
		end,
	}
end

local cache = {}
local function load(ms): any
	if cache[ms] ~= nil then
		return cache[ms]
	end
	local env = setmetatable({
		script = ms,
		require = load,
		game = game,
		workspace = workspace,
		Instance = Instance,
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = CFrame,
		UDim2 = roblox.UDim2,
		UDim = roblox.UDim,
		Enum = roblox.Enum,
		Random = Random,
		os = setmetatable({ time = function() return clock end }, { __index = os }),
	}, { __index = _G })
	local result = luau.load(fs.readFile(ms:GetAttribute("Path")), { debugName = ms.Name, environment = env })()
	cache[ms] = result
	return result
end

local Config = load(shared.Config)
local SaveSchema = load(shared.SaveSchema)
local Plots = load(sss.Plots)
local PetService = load(sss.PetService)
local Actions = load(sss.Actions)

---------------------------------------------------------------------------
-- Test harness
---------------------------------------------------------------------------

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
local function check(cond: any, msg: string)
	if not cond then
		error(msg, 2)
	end
end
local function okResult(r, what: string)
	if not r.ok then
		error(what .. " failed: " .. tostring(r.msg), 2)
	end
	return r
end
local function failResult(r, what: string)
	if r.ok then
		error(what .. " should have failed", 2)
	end
	return r
end

local notifications = {}
local sessions = {}
Actions.Init(function(player, msg)
	table.insert(notifications, { player = player, msg = msg })
end, function(userId)
	for _, s in sessions do
		if s.player.UserId == userId then
			return s
		end
	end
	return nil
end, function(s)
	s.data = SaveSchema.Default(clock)
	Plots.Rebuild(s.plot, s.data)
	s.plot.Pets:ClearAllChildren()
end)

Plots.Init()
local function newPlayer(userId: number, name: string)
	local player = { UserId = userId, Name = name, DisplayName = name }
	local data = SaveSchema.Default(clock)
	local plot = Plots.Create(player, data)
	local s = { player = player, data = data, plot = plot, online = false, dirty = false, busy = false }
	table.insert(sessions, s)
	return s
end

local a = newPlayer(1, "Alice")
local b = newPlayer(2, "Bob")

local function petCountIn(s)
	local n = 0
	for _ in s.data.pets do
		n += 1
	end
	return n
end

test("plots and rooms are built", function()
	check(a.plot.Parent ~= nil and b.plot.Parent ~= nil, "plots parented")
	check(a.plot.Name ~= b.plot.Name, "separate plots")
	for _, def in Config.Rooms do
		local room = a.plot.Rooms:FindFirstChild(def.Id)
		check(room and room:FindFirstChild("Shell"), "room " .. def.Id)
		check(room:GetAttribute("Locked") == (def.Id ~= "living"), "lock state " .. def.Id)
	end
	check(#a.plot.Rooms.living.Furniture:GetChildren() == #Config.Start.Furniture, "starter furniture models")
end)

local kitten
test("starter kitten is free and named", function()
	local list = okResult(Actions.GetAdoption(a, {}), "GetAdoption")
	check(list.starter == true, "starter flag")
	local coins = a.data.coins
	failResult(Actions.Adopt(a, { species = "Cat", index = 1, name = "  ", gender = "F" }), "blank name")
	failResult(Actions.Adopt(a, { species = "Cat", index = 1, name = "Badword", gender = "F" }), "filtered name")
	failResult(Actions.Adopt(a, { species = "Dog", index = 1, name = "Rex", gender = "M" }), "dog at level 1")
	local r = okResult(Actions.Adopt(a, { species = "Cat", index = 1, name = "Mittens", gender = "F" }), "Adopt")
	kitten = a.data.pets[r.petId]
	check(kitten and kitten.name == "Mittens", "pet saved")
	check(a.data.coins == coins, "starter kitten was free")
	check(a.plot.Pets:FindFirstChild(r.petId), "pet model spawned")
	failResult(Actions.Adopt(a, { species = "Cat", index = 1, name = "Again", gender = "F" }), "same pet twice")
end)

test("second cat costs coins", function()
	local coins = a.data.coins
	local list = Actions.GetAdoption(a, {})
	local price = list.species[1].candidates[2].price
	okResult(Actions.Adopt(a, { species = "Cat", index = 2, name = "Tom", gender = "M" }), "Adopt 2")
	check(a.data.coins == coins - price, "charged " .. price)
end)

test("care actions change needs and reward", function()
	kitten.needs.Food = 40
	local xp, coins = a.data.xp + a.data.level * 1000, a.data.coins
	okResult(Actions.Care(a, { petId = kitten.id, action = "UseItem", itemId = "kibble" }), "Feed")
	check(kitten.needs.Food == 75, "food went up by 35, got " .. kitten.needs.Food)
	check(a.data.inventory.kibble == 4, "kibble used")
	check(a.data.xp + a.data.level * 1000 > xp and a.data.coins > coins, "rewarded")
	local model = a.plot.Pets:FindFirstChild(kitten.id)
	check(model:GetAttribute("Action") == "Eat", "eating animation")
	check(model:GetAttribute("ActionTarget") ~= "", "walks to the bowl")
	failResult(Actions.Care(a, { petId = kitten.id, action = "Play" }), "play while busy")
	clock += 10
	kitten.needs.Fun = 30
	okResult(Actions.Care(a, { petId = kitten.id, action = "Play" }), "Play")
	check(kitten.needs.Fun == 55, "fun went up")
	clock += 10
	failResult(Actions.Care(a, { petId = kitten.id, action = "Play" }), "play cooldown")
	-- Petting during the cooldown still works but gives no reward.
	okResult(Actions.Care(a, { petId = kitten.id, action = "Pet" }), "Pet")
	local r = okResult(Actions.Care(a, { petId = kitten.id, action = "Pet" }), "Pet again")
	check(r.noReward, "no reward inside cooldown")
	kitten.needs.Food = 99
	clock += 30
	failResult(Actions.Care(a, { petId = kitten.id, action = "UseItem", itemId = "kibble" }), "feed when full")
	failResult(Actions.Care(a, { petId = kitten.id, action = "UseItem", itemId = "feast" }), "feed without item")
	failResult(Actions.Care(a, { petId = "p999", action = "Pet" }), "unknown pet")
	failResult(Actions.Care(b, { petId = kitten.id, action = "Pet" }), "someone else's pet")
end)

test("sleep and wake", function()
	kitten.needs.Energy = 50
	okResult(Actions.Care(a, { petId = kitten.id, action = "Sleep" }), "Sleep")
	local model = a.plot.Pets:FindFirstChild(kitten.id)
	check(model:GetAttribute("Sleeping") == true, "sleeping attribute")
	check(model:GetAttribute("SleepTarget") ~= "", "goes to the bed")
	failResult(Actions.Care(a, { petId = kitten.id, action = "Brush" }), "brush while asleep")
	okResult(Actions.Care(a, { petId = kitten.id, action = "Wake" }), "Wake")
	check(not kitten.sleeping, "awake")
end)

test("shop rejects bad purchases and accepts good ones", function()
	a.data.coins = 100
	failResult(Actions.Buy(a, { itemId = "sofa" }), "locked item")
	failResult(Actions.Buy(a, { itemId = "pet_bed", qty = 2 }), "too expensive")
	failResult(Actions.Buy(a, { itemId = "kibble", qty = 0 }), "zero qty")
	failResult(Actions.Buy(a, { itemId = "kibble", qty = 1.5 }), "fractional qty")
	failResult(Actions.Buy(a, { itemId = "nope" }), "unknown item")
	check(a.data.coins == 100, "no coins spent on failures")
	okResult(Actions.Buy(a, { itemId = "kibble", qty = 5 }), "buy kibble")
	check(a.data.coins == 50, "charged 50")
	okResult(Actions.Buy(a, { itemId = "toy_ball" }), "buy toy")
	check(a.data.coins == 0 and a.data.inventory.toy_ball == 1, "toy in inventory")
	failResult(Actions.Buy(a, { itemId = "kibble" }), "broke")
	check(a.data.coins == 0, "never negative")
end)

test("placing, moving and storing furniture", function()
	failResult(Actions.Place(a, { itemId = "toy_ball", roomId = "living", cx = 2, cz = 6, rot = 0 }), "on top of the bowl")
	failResult(Actions.Place(a, { itemId = "toy_ball", roomId = "living", cx = 99, cz = 0, rot = 0 }), "outside room")
	failResult(Actions.Place(a, { itemId = "toy_ball", roomId = "bedroom", cx = 1, cz = 1, rot = 0 }), "locked room")
	failResult(Actions.Place(a, { itemId = "sofa", roomId = "living", cx = 1, cz = 1, rot = 0 }), "not owned")
	local r = okResult(Actions.Place(a, { itemId = "toy_ball", roomId = "living", cx = 12, cz = 8, rot = 0 }), "Place")
	check(a.data.inventory.toy_ball == nil, "taken from inventory")
	check(a.plot.Rooms.living.Furniture:FindFirstChild(r.uid), "model placed")
	okResult(Actions.MoveFurniture(a, { uid = r.uid, roomId = "living", cx = 13, cz = 9, rot = 1 }), "Move")
	failResult(Actions.MoveFurniture(a, { uid = r.uid, roomId = "living", cx = 2, cz = 6, rot = 0 }), "move onto bowl")
	okResult(Actions.StoreFurniture(a, { uid = r.uid }), "Store")
	check(a.data.inventory.toy_ball == 1, "back in inventory")
	check(a.plot.Rooms.living.Furniture:FindFirstChild(r.uid) == nil, "model removed")
	failResult(Actions.StoreFurniture(b, { uid = r.uid }), "store furniture Bob does not own")
end)

test("levels, room unlock and styles", function()
	a.data.coins = 5000
	failResult(Actions.UnlockRoom(a, { roomId = "bedroom" }), "level too low")
	a.data.xp = 0
	notifications = {}
	local load_ = load(shared.Economy)
	load_.AddXP(a.data, 2000)
	check(a.data.level >= 3, "levelled up")
	failResult(Actions.UnlockRoom(a, { roomId = "kitchen" }), "out of order")
	local coins = a.data.coins
	okResult(Actions.UnlockRoom(a, { roomId = "bedroom" }), "unlock bedroom")
	check(a.data.coins == coins - 1000, "charged")
	check(a.plot.Rooms.bedroom:GetAttribute("Locked") == false, "bedroom open")
	failResult(Actions.SetStyle(a, { roomId = "bedroom", kind = "Wallpaper", styleId = "bubblegum" }), "unowned style")
	okResult(Actions.BuyStyle(a, { kind = "Wallpaper", styleId = "bubblegum" }), "buy style")
	failResult(Actions.BuyStyle(a, { kind = "Wallpaper", styleId = "bubblegum" }), "buy twice")
	okResult(Actions.SetStyle(a, { roomId = "bedroom", kind = "Wallpaper", styleId = "bubblegum" }), "apply style")
	okResult(Actions.SetStyle(a, { roomId = "living", kind = "Floor", styleId = "checker" }), "free floor")
	okResult(Actions.MovePet(a, { petId = kitten.id, roomId = "bedroom" }), "move pet")
	check(kitten.room == "bedroom", "pet moved")
	failResult(Actions.MovePet(a, { petId = kitten.id, roomId = "garden" }), "locked room")
end)

test("breeding produces a baby with inherited traits", function()
	local tom
	for _, p in a.data.pets do
		if p.name == "Tom" then
			tom = p
		end
	end
	failResult(Actions.Breed(a, { a = kitten.id, b = kitten.id }), "same pet")
	local r = okResult(Actions.Breed(a, { a = tom.id, b = kitten.id }), "Breed")
	failResult(Actions.Breed(a, { a = tom.id, b = kitten.id }), "cooldown")
	failResult(Actions.ClaimBirth(a, { birthId = r.birthId, name = "Bean", gender = "F" }), "not ready yet")
	clock += Config.Breeding.Duration + 1
	local before = petCountIn(a)
	local c = okResult(Actions.ClaimBirth(a, { birthId = r.birthId, name = "Bean", gender = "F" }), "ClaimBirth")
	local baby = a.data.pets[c.petId]
	check(petCountIn(a) == before + 1, "baby added")
	check(baby.stage == "Baby", "is a baby")
	check(baby.parents[1] == tom.id, "parents recorded")
	check(#a.data.births == 0, "birth claimed")
	-- Babies grow up with care.
	for _ = 1, Config.Growth.AdultAfterCare do
		clock += Config.Care.Pet.Cooldown + 1
		okResult(Actions.Care(a, { petId = baby.id, action = "Pet" }), "pet baby")
	end
	check(baby.stage == "Adult", "grew up")
end)

test("needs tick, gifts and the daily bonus", function()
	kitten.needs.Food, kitten.needs.Fun = 100, 100
	PetService.Tick(a.plot, a.data, 600, clock)
	check(kitten.needs.Food < 100, "food decays")
	kitten.lastGiftAt = clock - Config.Gift.Interval - 1
	for _, need in Config.Needs do
		kitten.needs[need] = 100
	end
	PetService.Tick(a.plot, a.data, 1, clock)
	check(a.plot.Pets:FindFirstChild(kitten.id):GetAttribute("Gift") == true, "gift ready")
	local coins = a.data.coins
	okResult(Actions.CollectGift(a, { petId = kitten.id }), "CollectGift")
	check(a.data.coins > coins, "gift paid")
	failResult(Actions.CollectGift(a, { petId = kitten.id }), "gift twice")
	okResult(Actions.ClaimDaily(a, {}), "daily")
	failResult(Actions.ClaimDaily(a, {}), "daily twice")
end)

test("visiting a neighbour's pet", function()
	clock += 60
	local coins = b.data.coins
	okResult(Actions.VisitPet(b, { ownerId = 1, petId = kitten.id }), "visit")
	check(b.data.coins == coins + Config.Visit.Coins, "visitor rewarded")
	local r = okResult(Actions.VisitPet(b, { ownerId = 1, petId = kitten.id }), "visit again")
	check(r.noReward, "once per pet per day")
	failResult(Actions.VisitPet(a, { ownerId = 1, petId = kitten.id }), "visit yourself")
	local told = false
	for _, n in notifications do
		if n.player == a.player and n.msg.kind == "toast" then
			told = true
		end
	end
	check(told, "owner notified")
end)

test("rename and capacity", function()
	failResult(Actions.Rename(a, { petId = kitten.id, name = "<script>" }), "bad characters")
	okResult(Actions.Rename(a, { petId = kitten.id, name = "Princess" }), "rename")
	check(a.plot.Pets:FindFirstChild(kitten.id):GetAttribute("Name") == "Princess", "name replicated")
end)

test("save round-trips the played game", function()
	local loaded, repairs = SaveSchema.Load(a.data, clock)
	check(#repairs == 0, "no repairs: " .. table.concat(repairs, ", "))
	check(petCountIn({ data = loaded }) == petCountIn(a), "pets kept")
	check(loaded.coins == a.data.coins and loaded.level == a.data.level, "progress kept")
	check(#loaded.rooms == #a.data.rooms, "rooms kept")
	check(loaded.rooms[2].wallpaper == "bubblegum", "style kept")
end)

test("reset save", function()
	failResult(Actions.ResetSave(a, {}), "unconfirmed")
	okResult(Actions.ResetSave(a, { confirm = "RESET" }), "reset")
	check(petCountIn(a) == 0 and a.data.level == 1, "fresh start")
	check(#a.plot.Pets:GetChildren() == 0, "pet models cleared")
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
