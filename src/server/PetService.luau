-- Pet models in the world and their replicated state.
--
-- The server owns each pet's data (needs, room, sleeping) and builds one
-- model per pet in its plot's Pets folder. The model's attributes tell every
-- client what the pet is doing:
--   PetId, Owner, Name, Species, Gender, Stage, Room, Mood, Sleeping,
--   Gift (a coin gift is waiting), Low (the need that wants attention),
--   Action ("Eat", "Play", "Pet", "Bath", "Brush", "Treat", "Medicine", "Sleep")
--   ActionTarget (furniture uid to walk to), ActionEnd (server time),
--   ActionId (increments so repeated actions retrigger)
-- Clients animate the walking, wandering and reactions locally.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetRules = require(Shared:WaitForChild("PetRules"))
local PetModels = require(Shared:WaitForChild("PetModels"))
local Placement = require(Shared:WaitForChild("Placement"))
local Economy = require(Shared:WaitForChild("Economy"))

local Plots = require(script.Parent:WaitForChild("Plots"))

local PetService = {}

local function lookKey(pet: any): string
	return table.concat({ pet.species, pet.color, pet.pattern, pet.eyes, pet.stage }, "|")
end

function PetService.Find(plot: Model, petId: string): Model?
	return (plot:FindFirstChild("Pets") :: Folder):FindFirstChild(petId) :: Model?
end

-- Room environment used by the needs simulation.
function PetService.RoomEnv(data: any, roomId: string): PetRules.Env
	local room = Economy.GetRoom(data, roomId)
	local furniture = if room then room.furniture else {}
	return {
		comfort = Placement.Comfort(furniture),
		litter = Placement.HasRole(furniture, "Litter"),
		hasBed = Placement.HasRole(furniture, "Bed"),
	}
end

local function roomFloorCFrame(plot: Model, roomId: string): CFrame
	local _, order = Config.RoomById(roomId)
	return Plots.RoomCFrame(plot, order or 1)
end

function PetService.UpdateAttributes(plot: Model, pet: any)
	local model = PetService.Find(plot, pet.id)
	if not model then
		return
	end
	local mood = PetRules.Mood(pet)
	model:SetAttribute("Name", pet.name)
	model:SetAttribute("Gender", pet.gender)
	model:SetAttribute("Stage", pet.stage)
	model:SetAttribute("Room", pet.room)
	model:SetAttribute("Mood", math.floor(mood + 0.5))
	model:SetAttribute("Sleeping", pet.sleeping)
	model:SetAttribute("Low", PetRules.LowestNeed(pet) or "")
end

-- Creates (or rebuilds, after growing up) the model for a pet.
function PetService.Spawn(plot: Model, pet: any)
	local existing = PetService.Find(plot, pet.id)
	if existing then
		if existing:GetAttribute("Look") == lookKey(pet) then
			PetService.UpdateAttributes(plot, pet)
			return
		end
		existing:Destroy()
	end
	local model = PetModels.Create(pet)
	model.Name = pet.id
	model:SetAttribute("PetId", pet.id)
	model:SetAttribute("Owner", plot:GetAttribute("Owner"))
	model:SetAttribute("Species", pet.species)
	model:SetAttribute("Look", lookKey(pet))
	model:SetAttribute("Action", "")
	model:SetAttribute("ActionTarget", "")
	model:SetAttribute("ActionEnd", 0)
	model:SetAttribute("ActionId", 0)
	model:SetAttribute("Gift", false)
	local floorCF = roomFloorCFrame(plot, pet.room)
	model:PivotTo(floorCF * CFrame.new(pet.x, 0, pet.z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	model.Parent = (plot:FindFirstChild("Pets") :: Folder)
	PetService.UpdateAttributes(plot, pet)
end

function PetService.Remove(plot: Model, petId: string)
	local model = PetService.Find(plot, petId)
	if model then
		model:Destroy()
	end
end

-- Moves a pet's model to its (new) room.
function PetService.Relocate(plot: Model, pet: any)
	local model = PetService.Find(plot, pet.id)
	if model then
		model:PivotTo(roomFloorCFrame(plot, pet.room) * CFrame.new(pet.x, 0, pet.z))
		model:SetAttribute("Room", pet.room)
		-- Tell clients to snap rather than walk across the house.
		model:SetAttribute("Teleport", (model:GetAttribute("Teleport") or 0) + 1)
	end
end

-- Starts a visible action. `role` picks furniture to walk to (nearest of
-- that role in the pet's room).
function PetService.StartAction(plot: Model, data: any, pet: any, action: string, duration: number, role: string?)
	local model = PetService.Find(plot, pet.id)
	if not model then
		return
	end
	local target = ""
	if role then
		local room = Economy.GetRoom(data, pet.room)
		local f = room and Placement.NearestWithRole(room.furniture, role, pet.x, pet.z)
		if f then
			target = f.uid
		end
	end
	model:SetAttribute("Action", action)
	model:SetAttribute("ActionTarget", target)
	-- Walking to the furniture takes a moment, so allow a little longer.
	model:SetAttribute("ActionEnd", workspace:GetServerTimeNow() + duration + (if target ~= "" then 2.5 else 0))
	model:SetAttribute("ActionId", (model:GetAttribute("ActionId") or 0) + 1)
end

-- Sleeping pets head to the nearest bed in their room.
function PetService.UpdateSleep(plot: Model, data: any, pet: any)
	local model = PetService.Find(plot, pet.id)
	if not model then
		return
	end
	model:SetAttribute("Sleeping", pet.sleeping)
	if pet.sleeping then
		local room = Economy.GetRoom(data, pet.room)
		local bed = room and Placement.NearestWithRole(room.furniture, "Bed", pet.x, pet.z)
		model:SetAttribute("SleepTarget", if bed then bed.uid else "")
	else
		model:SetAttribute("SleepTarget", "")
	end
end

-- Advances every pet's needs by dt seconds and refreshes attributes.
function PetService.Tick(plot: Model, data: any, dt: number, now: number)
	local envs = {}
	for _, pet in data.pets do
		local env = envs[pet.room]
		if not env then
			env = PetService.RoomEnv(data, pet.room)
			envs[pet.room] = env
		end
		local sleepChanged = PetRules.Simulate(pet, dt, env)
		if PetRules.Grow(pet, now) then
			PetService.Spawn(plot, pet)
		end
		if sleepChanged then
			PetService.UpdateSleep(plot, data, pet)
		end
		local model = PetService.Find(plot, pet.id)
		if model then
			local ready = now - pet.lastGiftAt >= Config.Gift.Interval and PetRules.Mood(pet) >= Config.Gift.MinMood
			model:SetAttribute("Gift", ready)
		end
		PetService.UpdateAttributes(plot, pet)
	end
end

function PetService.SpawnAll(plot: Model, data: any)
	for _, pet in data.pets do
		PetService.Spawn(plot, pet)
		PetService.UpdateSleep(plot, data, pet)
	end
end

return PetService
