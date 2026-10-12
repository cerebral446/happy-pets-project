-- Every request a client can make, validated and applied on the server.
-- Each handler receives the player's session and the request payload and
-- returns { ok = boolean, msg = string?, ... }. Nothing the client sends is
-- trusted: prices, positions, ownership and cooldowns are all re-checked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local PetRules = require(Shared:WaitForChild("PetRules"))
local Placement = require(Shared:WaitForChild("Placement"))
local SaveSchema = require(Shared:WaitForChild("SaveSchema"))
local Rng = require(Shared:WaitForChild("Rng"))

local Plots = require(script.Parent:WaitForChild("Plots"))
local PetService = require(script.Parent:WaitForChild("PetService"))
local Names = require(script.Parent:WaitForChild("Names"))

local Actions = {}

export type Session = {
	player: Player,
	data: any,
	plot: Model,
	online: boolean,
	dirty: boolean,
	busy: boolean,
}

type Result = { [string]: any }

-- Set by the main script: sends a notification table to one player.
local notify: (Player, any) -> () = function() end
-- Set by the main script: finds another player's session (for visits).
local sessionFor: (number) -> Session? = function()
	return nil
end
-- Set by the main script: rebuilds a session from a fresh save.
local resetSession: (Session) -> () = function() end

function Actions.Init(notifyFn: (Player, any) -> (), sessionFn: (number) -> Session?, resetFn: (Session) -> ())
	notify = notifyFn
	sessionFor = sessionFn
	resetSession = resetFn
end

local function fail(msg: string): Result
	return { ok = false, msg = msg }
end

local function str(v: any): string?
	return if typeof(v) == "string" and #v <= 64 then v else nil
end

local function int(v: any): number?
	if typeof(v) == "number" and v == v and v == math.floor(v) and math.abs(v) < 1e6 then
		return v
	end
	return nil
end

-- Grants XP and coins, announces level-ups, and floats the reward above a pet.
local function reward(s: Session, xp: number, coins: number, petId: string?, text: string?)
	Economy.AddCoins(s.data, coins)
	local reached, bonus = Economy.AddXP(s.data, xp)
	s.dirty = true
	notify(s.player, { kind = "reward", xp = xp, coins = coins, petId = petId, text = text })
	for _, level in reached do
		notify(s.player, { kind = "levelup", level = level, coins = Config.LevelReward(level), unlocks = Economy.UnlocksAt(level) })
	end
	if bonus > 0 then
		s.dirty = true
	end
end

local function getPet(s: Session, petId: any): any
	local id = str(petId)
	return id and s.data.pets[id]
end

local function randomSpot(): (number, number)
	return math.random(-10, 10), math.random(-5, 6)
end

local function today(): number
	return Economy.DayIndex(os.time())
end

local function refreshAdoptDay(data: any)
	if data.adopt.day ~= today() then
		data.adopt = { day = today(), rerolls = 0, taken = {} }
	end
end

local function adoptionSeed(s: Session): number
	return PetRules.AdoptionSeed(s.player.UserId, s.data.adopt.day, s.data.adopt.rerolls)
end

---------------------------------------------------------------------------
-- Adoption
---------------------------------------------------------------------------

function Actions.GetAdoption(s: Session, _payload: any): Result
	refreshAdoptDay(s.data)
	local seed = adoptionSeed(s)
	local list = {}
	for _, species in Config.SpeciesOrder do
		local def = Config.Species[species]
		local candidates = PetRules.AdoptionCandidates(seed, species)
		for _, c in candidates do
			c.taken = s.data.adopt.taken[species .. ":" .. c.index] == true
		end
		table.insert(list, { species = species, level = def.Level, unlocked = s.data.level >= def.Level, candidates = candidates })
	end
	return { ok = true, species = list, starter = not s.data.starterDone, rerollCost = Config.Adoption.RerollCost }
end

function Actions.RerollAdoption(s: Session, _payload: any): Result
	refreshAdoptDay(s.data)
	if not Economy.Spend(s.data, Config.Adoption.RerollCost) then
		return fail("You need " .. Config.Adoption.RerollCost .. " coins to see new pets.")
	end
	s.data.adopt.rerolls += 1
	s.data.adopt.taken = {}
	s.dirty = true
	return Actions.GetAdoption(s, nil)
end

local function placeNewPet(s: Session, pet: any)
	local x, z = randomSpot()
	pet.x, pet.z = x, z
	s.data.pets[pet.id] = pet
	PetService.Spawn(s.plot, pet)
	PetService.UpdateSleep(s.plot, s.data, pet)
	s.dirty = true
end

function Actions.Adopt(s: Session, payload: any): Result
	refreshAdoptDay(s.data)
	local species = str(payload.species)
	local index = int(payload.index)
	local def = species and Config.Species[species]
	if not def or not index then
		return fail("That pet isn't available.")
	end
	if s.data.level < def.Level then
		return fail(def.Name .. "s unlock at level " .. def.Level .. ".")
	end
	local gender = payload.gender
	if gender ~= "M" and gender ~= "F" then
		return fail("Choose boy or girl.")
	end
	local candidate = PetRules.AdoptionCandidates(adoptionSeed(s), species)[index]
	local takenKey = species .. ":" .. index
	if not candidate or s.data.adopt.taken[takenKey] then
		return fail("Someone already adopted that pet. Pick another!")
	end
	local room = Economy.RoomWithSpace(s.data)
	if not room then
		return fail("Your home is full! Unlock another room to make space.")
	end
	local free = not s.data.starterDone and species == "Cat"
	local price = if free then 0 else candidate.price
	if not Economy.CanAfford(s.data, price) then
		return fail("You need " .. price .. " coins to adopt this pet.")
	end
	-- Filtering yields; re-check money afterwards in case it changed.
	local name, err = Names.Filter(s.player, payload.name)
	if not name then
		return fail(err or "Invalid name.")
	end
	if not Economy.Spend(s.data, price) then
		return fail("You need " .. price .. " coins to adopt this pet.")
	end
	local pet = PetRules.NewPet(SaveSchema.NewId(s.data, "p"), species, candidate.look, name, gender, "Adult", os.time(), room)
	s.data.adopt.taken[takenKey] = true
	s.data.starterDone = true
	s.data.stats.adopted += 1
	placeNewPet(s, pet)
	PetService.StartAction(s.plot, s.data, pet, "Pet", 3)
	reward(s, Config.Adoption.XP, 0, pet.id, "Welcome home, " .. name .. "!")
	return { ok = true, petId = pet.id, room = room }
end

---------------------------------------------------------------------------
-- Pet care
---------------------------------------------------------------------------

local ITEM_ACTION_ANIM = { Feed = "Eat", Treat = "Treat", Bath = "Bath", Medicine = "Medicine" }

local function careDone(s: Session, pet: any)
	pet.careCount += 1
	s.data.stats.care += 1
	if PetRules.Grow(pet, os.time()) then
		PetService.Spawn(s.plot, pet)
		notify(s.player, { kind = "toast", text = pet.name .. " has grown up! 🎉" })
	end
	PetService.UpdateAttributes(s.plot, pet)
	s.dirty = true
end

local function isBusy(s: Session, pet: any): boolean
	local model = PetService.Find(s.plot, pet.id)
	return model ~= nil and (model:GetAttribute("ActionEnd") :: number) > workspace:GetServerTimeNow()
end

function Actions.Care(s: Session, payload: any): Result
	local pet = getPet(s, payload.petId)
	if not pet then
		return fail("That pet isn't here.")
	end
	local action = str(payload.action)
	local now = os.time()

	if action == "Wake" then
		if not pet.sleeping then
			return fail(pet.name .. " is already awake.")
		end
		pet.sleeping = false
		PetService.UpdateSleep(s.plot, s.data, pet)
		s.dirty = true
		return { ok = true }
	end

	if action == "Sleep" then
		if pet.sleeping then
			return fail(pet.name .. " is already asleep.")
		end
		if pet.needs.Energy >= 90 then
			return fail(pet.name .. " isn't sleepy yet.")
		end
		pet.sleeping = true
		PetService.UpdateSleep(s.plot, s.data, pet)
		s.dirty = true
		return { ok = true }
	end

	if pet.sleeping and action ~= "Pet" then
		return fail(pet.name .. " is asleep. Wake them up first, or let them rest.")
	end

	if action == "Pet" then
		local left = PetRules.CooldownLeft(pet, "Pet", now)
		if not pet.sleeping then
			PetService.StartAction(s.plot, s.data, pet, "Pet", Config.Care.Pet.Duration)
		end
		if left > 0 then
			-- Still a happy reaction, just no reward until the cooldown passes.
			return { ok = true, noReward = true }
		end
		pet.cooldowns.Pet = now
		PetRules.ApplyEffects(pet, Config.Care.Pet.Effects)
		careDone(s, pet)
		reward(s, Config.Care.Pet.XP, Config.Care.Pet.Coins, pet.id)
		return { ok = true }
	end

	if isBusy(s, pet) then
		return fail(pet.name .. " is busy right now.")
	end

	if action == "Play" or action == "Brush" then
		local care = Config.Care[action]
		local left = PetRules.CooldownLeft(pet, action, now)
		if left > 0 then
			return fail(string.format("%s needs a little break first (%ds).", pet.name, math.ceil(left)))
		end
		if action == "Play" then
			if pet.needs.Energy < care.MinEnergy then
				return fail(pet.name .. " is too tired to play. Let them sleep!")
			end
			local room = Economy.GetRoom(s.data, pet.room)
			if not room or not Placement.HasRole(room.furniture, "Toy") then
				return fail("Put a toy in this room so " .. pet.name .. " can play!")
			end
		end
		pet.cooldowns[action] = now
		PetRules.ApplyEffects(pet, care.Effects)
		PetService.StartAction(s.plot, s.data, pet, action, care.Duration, if action == "Play" then "Toy" else nil)
		careDone(s, pet)
		reward(s, care.XP, care.Coins, pet.id)
		return { ok = true }
	end

	if action == "UseItem" then
		local itemId = str(payload.itemId)
		local item = itemId and Config.Items[itemId]
		if not item or item.Kind ~= "Consumable" then
			return fail("You can't use that on a pet.")
		end
		if Economy.InventoryCount(s.data, itemId :: string) < 1 then
			return fail("You don't have any " .. item.Name .. ". Buy some in the shop!")
		end
		local n = pet.needs
		if item.Action == "Feed" and n.Food >= 95 then
			return fail(pet.name .. " isn't hungry right now.")
		elseif item.Action == "Bath" and n.Clean >= 95 then
			return fail(pet.name .. " is already squeaky clean.")
		elseif item.Action == "Medicine" and n.Health >= 95 then
			return fail(pet.name .. " is perfectly healthy.")
		elseif item.Action == "Treat" then
			local full = true
			for need, amount in item.Effects do
				if amount > 0 and n[need] < 95 then
					full = false
				end
			end
			if full then
				return fail(pet.name .. " doesn't need that right now.")
			end
		end
		Economy.TakeItem(s.data, itemId :: string, 1)
		PetRules.ApplyEffects(pet, item.Effects)
		local text = nil
		local def = Config.Species[pet.species]
		if item.Action == "Feed" and def.Favorite == itemId then
			PetRules.ApplyEffects(pet, { Fun = Config.Care.FavoriteFun })
			text = "Yum! My favourite!"
		end
		PetService.StartAction(s.plot, s.data, pet, ITEM_ACTION_ANIM[item.Action] or "Treat", Config.Care.Item.Duration, if item.Action == "Feed" then "Bowl" else nil)
		careDone(s, pet)
		reward(s, Config.Care.Item.XP, Config.Care.Item.Coins, pet.id, text)
		return { ok = true }
	end

	return fail("Unknown action.")
end

function Actions.CollectGift(s: Session, payload: any): Result
	local pet = getPet(s, payload.petId)
	if not pet then
		return fail("That pet isn't here.")
	end
	local now = os.time()
	if now - pet.lastGiftAt < Config.Gift.Interval or PetRules.Mood(pet) < Config.Gift.MinMood then
		return fail("No gift yet. Happy pets leave gifts every few minutes!")
	end
	pet.lastGiftAt = now
	s.data.stats.gifts += 1
	local model = PetService.Find(s.plot, pet.id)
	if model then
		model:SetAttribute("Gift", false)
	end
	reward(s, Config.Gift.XP, Economy.GiftCoins(s.data), pet.id, "A gift from " .. pet.name .. "!")
	return { ok = true }
end

function Actions.Rename(s: Session, payload: any): Result
	local pet = getPet(s, payload.petId)
	if not pet then
		return fail("That pet isn't here.")
	end
	local name, err = Names.Filter(s.player, payload.name)
	if not name then
		return fail(err or "Invalid name.")
	end
	pet.name = name
	PetService.UpdateAttributes(s.plot, pet)
	s.dirty = true
	return { ok = true, name = name }
end

function Actions.MovePet(s: Session, payload: any): Result
	local pet = getPet(s, payload.petId)
	local roomId = str(payload.roomId)
	if not pet or not roomId then
		return fail("That pet isn't here.")
	end
	local def = Config.RoomById(roomId)
	if not def or not Economy.HasRoom(s.data, roomId) then
		return fail("You haven't unlocked that room yet.")
	end
	if pet.room == roomId then
		return fail(pet.name .. " is already in the " .. def.Name .. ".")
	end
	if Economy.PetsInRoom(s.data, roomId) >= def.Capacity then
		return fail("The " .. def.Name .. " is full (" .. def.Capacity .. " pets).")
	end
	pet.room = roomId
	pet.x, pet.z = randomSpot()
	PetService.Relocate(s.plot, pet)
	PetService.UpdateSleep(s.plot, s.data, pet)
	s.dirty = true
	return { ok = true }
end

---------------------------------------------------------------------------
-- Shop
---------------------------------------------------------------------------

function Actions.Buy(s: Session, payload: any): Result
	local itemId = str(payload.itemId)
	local qty = if payload.qty == nil then 1 else int(payload.qty)
	local item = itemId and Config.Items[itemId]
	if not item then
		return fail("That item isn't for sale.")
	end
	if not qty or qty < 1 or qty > 10 then
		return fail("You can buy 1 to 10 at a time.")
	end
	if s.data.level < item.Level then
		return fail(item.Name .. " unlocks at level " .. item.Level .. ".")
	end
	local cost = item.Price * qty
	if not Economy.Spend(s.data, cost) then
		return fail("You need " .. cost .. " coins for that.")
	end
	Economy.AddItem(s.data, itemId :: string, qty)
	reward(s, math.max(1, cost // 20), 0, nil, nil)
	return { ok = true, itemId = itemId, count = Economy.InventoryCount(s.data, itemId :: string) }
end

function Actions.BuyStyle(s: Session, payload: any): Result
	local kind = payload.kind
	local styleId = str(payload.styleId)
	local def = if kind == "Wallpaper" and styleId then Config.WallpaperById(styleId) elseif kind == "Floor" and styleId then Config.FloorById(styleId) else nil
	if not def then
		return fail("That style isn't for sale.")
	end
	if Economy.OwnsStyle(s.data, kind, styleId :: string) then
		return fail("You already own " .. def.Name .. ".")
	end
	if s.data.level < def.Level then
		return fail(def.Name .. " unlocks at level " .. def.Level .. ".")
	end
	if not Economy.Spend(s.data, def.Price) then
		return fail("You need " .. def.Price .. " coins for that.")
	end
	s.data.styles[styleId :: string] = true
	reward(s, math.max(1, def.Price // 20), 0, nil, nil)
	return { ok = true }
end

function Actions.SetStyle(s: Session, payload: any): Result
	local kind = payload.kind
	local roomId = str(payload.roomId)
	local styleId = str(payload.styleId)
	local room = roomId and Economy.GetRoom(s.data, roomId)
	if not room or not styleId or (kind ~= "Wallpaper" and kind ~= "Floor") then
		return fail("You can't decorate that room.")
	end
	if not Economy.OwnsStyle(s.data, kind, styleId) then
		return fail("Buy that style in the shop first.")
	end
	if kind == "Wallpaper" then
		room.wallpaper = styleId
	else
		room.floor = styleId
	end
	Plots.RefreshRoom(s.plot, s.data, room.id)
	s.dirty = true
	return { ok = true }
end

function Actions.UnlockRoom(s: Session, payload: any): Result
	local roomId = str(payload.roomId)
	local nextRoom = Economy.NextRoom(s.data)
	if not nextRoom or nextRoom.Id ~= roomId then
		return fail("Unlock the rooms in order.")
	end
	if s.data.level < nextRoom.Level then
		return fail(nextRoom.Name .. " unlocks at level " .. nextRoom.Level .. ".")
	end
	if not Economy.Spend(s.data, nextRoom.Price) then
		return fail("You need " .. nextRoom.Price .. " coins to open the " .. nextRoom.Name .. ".")
	end
	table.insert(s.data.rooms, SaveSchema.NewRoom(nextRoom))
	Plots.RefreshRoom(s.plot, s.data, nextRoom.Id)
	reward(s, 50, 0, nil, nextRoom.Name .. " unlocked!")
	return { ok = true }
end

---------------------------------------------------------------------------
-- Decorating
---------------------------------------------------------------------------

local function findFurniture(data: any, uid: string): (any, any, number?)
	for _, room in data.rooms do
		for i, f in room.furniture do
			if f.uid == uid then
				return f, room, i
			end
		end
	end
	return nil, nil, nil
end

function Actions.Place(s: Session, payload: any): Result
	local itemId = str(payload.itemId)
	local roomId = str(payload.roomId)
	local cx, cz, rot = int(payload.cx), int(payload.cz), int(payload.rot)
	local room = roomId and Economy.GetRoom(s.data, roomId)
	if not itemId or not room or not cx or not cz or not rot then
		return fail("You can't place that there.")
	end
	if Economy.InventoryCount(s.data, itemId) < 1 then
		return fail("You don't have that item.")
	end
	local ok, why = Placement.Validate(room.furniture, itemId, cx, cz, rot)
	if not ok then
		return fail(why or "It doesn't fit there.")
	end
	Economy.TakeItem(s.data, itemId, 1)
	local uid = SaveSchema.NewId(s.data, "f")
	table.insert(room.furniture, { uid = uid, item = itemId, cx = cx, cz = cz, rot = rot })
	Plots.SyncFurniture(s.plot, room)
	s.dirty = true
	return { ok = true, uid = uid }
end

function Actions.MoveFurniture(s: Session, payload: any): Result
	local uid = str(payload.uid)
	local roomId = str(payload.roomId)
	local cx, cz, rot = int(payload.cx), int(payload.cz), int(payload.rot)
	local target = roomId and Economy.GetRoom(s.data, roomId)
	if not uid or not target or not cx or not cz or not rot then
		return fail("You can't move that there.")
	end
	local f, fromRoom, index = findFurniture(s.data, uid)
	if not f then
		return fail("That furniture isn't in your home.")
	end
	local ok, why = Placement.Validate(target.furniture, f.item, cx, cz, rot, uid)
	if not ok then
		return fail(why or "It doesn't fit there.")
	end
	f.cx, f.cz, f.rot = cx, cz, rot
	if fromRoom ~= target then
		table.remove(fromRoom.furniture, index :: number)
		table.insert(target.furniture, f)
		Plots.SyncFurniture(s.plot, fromRoom)
	end
	Plots.SyncFurniture(s.plot, target)
	s.dirty = true
	return { ok = true }
end

function Actions.StoreFurniture(s: Session, payload: any): Result
	local uid = str(payload.uid)
	local f, room, index = findFurniture(s.data, uid or "")
	if not f then
		return fail("That furniture isn't in your home.")
	end
	table.remove(room.furniture, index :: number)
	Economy.AddItem(s.data, f.item, 1)
	Plots.SyncFurniture(s.plot, room)
	-- Pets sleeping on it look for another bed.
	for _, pet in s.data.pets do
		if pet.sleeping and pet.room == room.id then
			PetService.UpdateSleep(s.plot, s.data, pet)
		end
	end
	s.dirty = true
	return { ok = true }
end

---------------------------------------------------------------------------
-- Breeding
---------------------------------------------------------------------------

function Actions.Breed(s: Session, payload: any): Result
	local a, b = getPet(s, payload.a), getPet(s, payload.b)
	local now = os.time()
	local ok, why = PetRules.CanBreed(a, b, now)
	if not ok then
		return fail(why or "They can't have babies right now.")
	end
	if #s.data.births >= Config.Breeding.MaxPending then
		return fail("You already have " .. Config.Breeding.MaxPending .. " babies on the way!")
	end
	if Economy.PetCount(s.data) + #s.data.births >= Economy.PetCapacity(s.data) then
		return fail("There's no room for a baby. Unlock another room first.")
	end
	if not Economy.Spend(s.data, Config.Breeding.Cost) then
		return fail("Breeding costs " .. Config.Breeding.Cost .. " coins.")
	end
	local seed = Rng.Hash(s.player.UserId, a.id, b.id, now, s.data.nextId)
	local birth = {
		id = SaveSchema.NewId(s.data, "b"),
		species = a.species,
		parents = { a.id, b.id },
		look = PetRules.Inherit(a, b, seed),
		readyAt = now + Config.Breeding.Duration,
	}
	table.insert(s.data.births, birth)
	a.lastBredAt, b.lastBredAt = now, now
	for _, p in { a, b } do
		PetService.StartAction(s.plot, s.data, p, "Love", 4)
	end
	s.data.stats.bred += 1
	reward(s, Config.Breeding.XP, 0, a.id, "A baby is on the way! 💕")
	return { ok = true, birthId = birth.id, readyAt = birth.readyAt }
end

function Actions.ClaimBirth(s: Session, payload: any): Result
	local id = str(payload.birthId)
	local index = nil
	for i, b in s.data.births do
		if b.id == id then
			index = i
		end
	end
	if not index then
		return fail("That baby isn't here.")
	end
	local birth = s.data.births[index]
	if os.time() < birth.readyAt then
		return fail("The baby isn't ready yet.")
	end
	local gender = payload.gender
	if gender ~= "M" and gender ~= "F" then
		return fail("Choose boy or girl.")
	end
	local room = Economy.RoomWithSpace(s.data, s.data.pets[birth.parents[1]] and s.data.pets[birth.parents[1]].room)
	if not room then
		return fail("Your home is full! Unlock another room to make space.")
	end
	local name, err = Names.Filter(s.player, payload.name)
	if not name then
		return fail(err or "Invalid name.")
	end
	-- Re-find: the list may have changed while the name was being filtered.
	index = table.find(s.data.births, birth)
	if not index then
		return fail("That baby isn't here.")
	end
	table.remove(s.data.births, index)
	local pet = PetRules.NewPet(SaveSchema.NewId(s.data, "p"), birth.species, birth.look, name, gender, "Baby", os.time(), room)
	pet.parents = { birth.parents[1], birth.parents[2] }
	placeNewPet(s, pet)
	PetService.StartAction(s.plot, s.data, pet, "Pet", 3)
	reward(s, 20, 0, pet.id, "Say hello to " .. name .. "!")
	return { ok = true, petId = pet.id, room = room }
end

---------------------------------------------------------------------------
-- Daily bonus, visiting, settings, reset
---------------------------------------------------------------------------

function Actions.ClaimDaily(s: Session, _payload: any): Result
	if s.data.daily.day == today() then
		return fail("You've already collected today's bonus. Come back tomorrow!")
	end
	s.data.daily.day = today()
	reward(s, Config.Daily.XP, Economy.DailyCoins(s.data), nil, "Daily bonus!")
	return { ok = true }
end

function Actions.VisitPet(s: Session, payload: any): Result
	local ownerId = int(payload.ownerId)
	local petId = str(payload.petId)
	if not ownerId or not petId or ownerId == s.player.UserId then
		return fail("You can't visit that pet.")
	end
	local owner = sessionFor(ownerId)
	local pet = owner and owner.data.pets[petId]
	if not owner or not pet then
		return fail("That pet isn't around any more.")
	end
	if pet.sleeping then
		return fail(pet.name .. " is asleep. Shh!")
	end
	local visits = s.data.visits
	if visits.day ~= today() then
		s.data.visits = { day = today(), count = 0, petted = {} }
		visits = s.data.visits
	end
	PetService.StartAction(owner.plot, owner.data, pet, "Pet", Config.Care.Pet.Duration)
	local key = ownerId .. ":" .. petId
	if visits.petted[key] or visits.count >= Config.Visit.PerDay then
		return { ok = true, noReward = true }
	end
	visits.petted[key] = true
	visits.count += 1
	PetRules.ApplyEffects(pet, { Fun = Config.Visit.Fun })
	PetService.UpdateAttributes(owner.plot, pet)
	owner.dirty = true
	reward(s, Config.Visit.XP, Config.Visit.Coins, pet.id, "You made " .. pet.name .. " happy!")
	notify(owner.player, { kind = "toast", text = s.player.DisplayName .. " petted " .. pet.name .. "! 💕" })
	return { ok = true }
end

function Actions.SetSetting(s: Session, payload: any): Result
	if (payload.key == "sound" or payload.key == "music") and typeof(payload.value) == "boolean" then
		s.data.settings[payload.key] = payload.value
		s.dirty = true
		return { ok = true }
	end
	return fail("Unknown setting.")
end

function Actions.ResetSave(s: Session, payload: any): Result
	if payload.confirm ~= "RESET" then
		return fail("Reset not confirmed.")
	end
	resetSession(s)
	return { ok = true }
end

return Actions
