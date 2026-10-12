-- Client-side state shared by the UI modules: the player's profile (sent by
-- the server as JSON), which home and room the camera is looking at, the
-- selected pet, and a helper for server requests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestRemote = remotes:WaitForChild("Request") :: RemoteFunction

local State = {}

-- Minimal signal: Connect(fn) / Fire(...).
local function signal()
	local handlers = {}
	return {
		Connect = function(_, fn)
			table.insert(handlers, fn)
			return {
				Disconnect = function()
					local i = table.find(handlers, fn)
					if i then
						table.remove(handlers, i)
					end
				end,
			}
		end,
		Fire = function(_, ...)
			for _, fn in table.clone(handlers) do
				task.spawn(fn, ...)
			end
		end,
	}
end
State.Signal = signal

State.Profile = nil :: any
State.ProfileChanged = signal()
-- The plot being viewed (own home, or a neighbour's while visiting).
State.ViewPlot = nil :: Model?
State.RoomIndex = 1
State.RoomChanged = signal()
State.SelectedPet = nil :: Model?
State.SelectionChanged = signal()
State.Decorating = false
State.DecorateChanged = signal()
State.Busy = false

function State.HomePlot(): Model?
	local name = player:GetAttribute("Plot")
	local plots = workspace:FindFirstChild("Plots")
	if not name or not plots then
		return nil
	end
	return plots:FindFirstChild(name) :: Model?
end

function State.IsVisiting(): boolean
	return State.ViewPlot ~= nil and State.ViewPlot ~= State.HomePlot()
end

function State.RoomId(): string
	return Config.Rooms[State.RoomIndex].Id
end

function State.RoomModel(): Model?
	local plot = State.ViewPlot
	if not plot then
		return nil
	end
	return (plot:FindFirstChild("Rooms") :: Folder):FindFirstChild(State.RoomId()) :: Model?
end

function State.RoomCFrame(plot: Model?, order: number): CFrame
	local p = plot or State.ViewPlot
	local origin = if p then p:GetAttribute("Origin") :: Vector3 else Vector3.zero
	return CFrame.new(origin + Vector3.new((order - 1) * Config.Room.Spacing, 0, 0))
end

function State.SetRoom(index: number)
	index = math.clamp(index, 1, #Config.Rooms)
	if index ~= State.RoomIndex then
		State.RoomIndex = index
		State.RoomChanged:Fire(index)
	end
end

function State.SetView(plot: Model?, roomIndex: number?)
	State.ViewPlot = plot
	State.RoomIndex = roomIndex or 1
	State.Select(nil)
	State.RoomChanged:Fire(State.RoomIndex)
end

function State.Select(pet: Model?)
	if State.SelectedPet ~= pet then
		State.SelectedPet = pet
		State.SelectionChanged:Fire(pet)
	end
end

-- The saved data for one of the player's own pets.
function State.PetData(petId: string): any
	return State.Profile and State.Profile.pets[petId]
end

function State.HasRoom(roomId: string): boolean
	if not State.Profile then
		return false
	end
	for _, r in State.Profile.rooms do
		if r.id == roomId then
			return true
		end
	end
	return false
end

function State.RoomData(roomId: string): any
	if not State.Profile then
		return nil
	end
	for _, r in State.Profile.rooms do
		if r.id == roomId then
			return r
		end
	end
	return nil
end

local function readProfile()
	local json = player:GetAttribute("Profile")
	if typeof(json) ~= "string" then
		return
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if ok and typeof(data) == "table" then
		-- JSON turns empty dictionaries into empty arrays; both iterate the same.
		data.pets = data.pets or {}
		data.inventory = data.inventory or {}
		data.styles = data.styles or {}
		data.births = data.births or {}
		State.Profile = data
		State.ProfileChanged:Fire(data)
	end
end

function State.Init()
	player:GetAttributeChangedSignal("Profile"):Connect(readProfile)
	readProfile()
end

-- Feedback hooks set by the HUD (toast for errors, click sound).
State.OnError = function(_msg: string) end
State.OnRequest = function() end

-- Calls the server. Shows the error message (if any) and returns the result.
function State.Request(name: string, payload: any?): any
	State.OnRequest()
	local ok, result = pcall(function()
		return requestRemote:InvokeServer(name, payload or {})
	end)
	if not ok or typeof(result) ~= "table" then
		State.OnError("Couldn't reach the server. Please try again.")
		return { ok = false }
	end
	if not result.ok and result.msg then
		State.OnError(result.msg)
	end
	return result
end

return State
