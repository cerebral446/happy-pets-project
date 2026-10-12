-- Happy Pets client: starts the UI, camera and pet animation, handles
-- clicking/tapping pets and furniture, and shows server notifications.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local State = require(script.Parent:WaitForChild("State"))
local UI = require(script.Parent:WaitForChild("UI"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local PetAnimator = require(script.Parent:WaitForChild("PetAnimator"))
local PetPanel = require(script.Parent:WaitForChild("PetPanel"))
local Windows = require(script.Parent:WaitForChild("Windows"))
local Decorate = require(script.Parent:WaitForChild("Decorate"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local Audio = require(script.Parent:WaitForChild("Audio"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local notifyRemote = remotes:WaitForChild("Notify") :: RemoteEvent

-- No backpack, health bar or player list clutter; this is a click game.
for _, coreType in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.PlayerList } do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreType, false)
	end)
end

UI.Init()
State.Init()

---------------------------------------------------------------------------
-- Wiring between modules
---------------------------------------------------------------------------

local function openWindow(id: string)
	if id ~= "Decorate" and State.Decorating then
		Decorate.Exit()
	end
	if id == "Adopt" then
		Windows.Adopt()
	elseif id == "Pets" then
		Windows.Pets()
	elseif id == "Shop" then
		Windows.Shop()
	elseif id == "Items" then
		Windows.Items()
	elseif id == "Decorate" then
		UI.CloseWindow()
		if State.Decorating then
			Decorate.Exit()
		else
			Decorate.Enter()
		end
	elseif id == "Breed" then
		Windows.Breed()
	elseif id == "Rooms" then
		Windows.Rooms()
	elseif id == "Visit" then
		Windows.Visit()
	elseif id == "Settings" then
		Windows.Settings()
	end
end

local function claimDaily()
	local r = State.Request("ClaimDaily")
	if r.ok then
		UI.Play("Coin", 0.6)
	end
end

Hud.Init(openWindow, claimDaily)
PetPanel.Init()
PetAnimator.Init()
Decorate.Init()
CameraController.Init()
Audio.Init()

Windows.Toast = function(text)
	Hud.Toast(text)
end
Windows.StartPlacing = function(itemId)
	UI.CloseWindow()
	if State.IsVisiting() then
		State.SetView(State.HomePlot(), 1)
	end
	-- Place in the current room if it's unlocked, otherwise the first room.
	if not State.HasRoom(State.RoomId()) then
		State.SetRoom(1)
	end
	Decorate.StartPlacing(itemId)
end
Decorate.OpenItems = Windows.Items
Decorate.Toast = function(text)
	Hud.Toast(text)
end
PetPanel.OpenShop = function(tab)
	Windows.Shop(tab)
end
PetPanel.Rename = Windows.Rename

local function collectGift(model: Model)
	local r = State.Request("CollectGift", { petId = model:GetAttribute("PetId") })
	if r.ok then
		PetAnimator.Hearts(model)
	end
end
PetAnimator.OnGiftClicked = collectGift

State.DecorateChanged:Connect(function(on)
	local nav = Hud.NavButton("Decorate")
	if nav then
		nav.BackgroundColor3 = if on then UI.Colors.Pink else UI.Colors.Green
		nav:SetAttribute("BaseColor", nav.BackgroundColor3)
	end
end)

---------------------------------------------------------------------------
-- Clicking pets and furniture
---------------------------------------------------------------------------

local function petAt(point: Vector2): Model?
	local plot = State.ViewPlot
	local folder = plot and plot:FindFirstChild("Pets")
	if not folder then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	if not hit then
		return nil
	end
	local inst: Instance? = hit.Instance
	while inst and inst.Parent ~= folder do
		inst = inst.Parent
	end
	return inst :: Model?
end

local function furnitureAt(point: Vector2): Model?
	local room = State.RoomModel()
	local folder = room and room:FindFirstChild("Furniture")
	if not folder then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	local inst: Instance? = hit and hit.Instance
	while inst and inst.Parent ~= folder do
		inst = inst.Parent
	end
	return inst :: Model?
end

local ROLE_TIPS = {
	Bowl = "Pets eat here when you feed them.",
	Bed = "Sleepy pets nap here and recover energy faster.",
	Toy = "Pets play with this when you press Play.",
	Litter = "Keeps pets in this room clean for longer.",
}

local function handlePress(point: Vector2)
	if Decorate.HandlePress(point) then
		return
	end
	local pet = petAt(point)
	if pet then
		local own = not State.IsVisiting()
		if own and pet:GetAttribute("Gift") == true then
			collectGift(pet)
		end
		if State.SelectedPet == pet then
			-- Clicking the selected pet again gives it a pat.
			if own then
				State.Request("Care", { petId = pet:GetAttribute("PetId"), action = "Pet" })
			else
				State.Request("VisitPet", { ownerId = pet:GetAttribute("Owner"), petId = pet:GetAttribute("PetId") })
			end
		else
			UI.Play("Pop", 0.3)
			Audio.PetSound(pet, "Greet")
			State.Select(pet)
			PetAnimator.Bubble(pet, if pet:GetAttribute("Sleeping") then "💤" else "❤️", 1.2)
		end
		return
	end
	local furniture = furnitureAt(point)
	if furniture and not State.IsVisiting() then
		local item = Config.Items[furniture:GetAttribute("Item") :: string]
		if item then
			local tip = (item.Role and ROLE_TIPS[item.Role]) or (if (item.Comfort or 0) > 0 then "Decorations keep pets happy for longer." else "")
			Hud.Toast(string.format("%s %s: %s Use 🛋️ Decorate to move it.", item.Icon, item.Name, tip))
		end
		return
	end
	State.Select(nil)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		handlePress(UserInputService:GetMouseLocation())
	elseif input.UserInputType == Enum.UserInputType.Touch then
		-- Touch positions exclude the top bar inset; convert to viewport space.
		handlePress(Vector2.new(input.Position.X, input.Position.Y + UI.Inset()))
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		PetAnimator.SetHover(if State.Decorating then nil else petAt(UserInputService:GetMouseLocation()))
	end
end)

-- Arrow keys / A-D switch rooms.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
		State.SetRoom(State.RoomIndex - 1)
	elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
		State.SetRoom(State.RoomIndex + 1)
	end
end)

---------------------------------------------------------------------------
-- Server notifications
---------------------------------------------------------------------------

notifyRemote.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "table" then
		return
	end
	if msg.kind == "reward" then
		local worldPos = nil
		local plot = State.ViewPlot
		local model = plot and msg.petId and (plot:FindFirstChild("Pets") :: Folder):FindFirstChild(msg.petId)
		if model then
			worldPos = PetAnimator.WorldPosition(model :: Model)
		end
		Hud.FloatReward(worldPos, msg.xp or 0, msg.coins or 0)
		if msg.text then
			if model then
				PetAnimator.Bubble(model :: Model, "💖", 2)
			end
			Hud.Toast(msg.text)
		end
	elseif msg.kind == "levelup" then
		Hud.LevelUp(msg.level, msg.coins, msg.unlocks or {})
	elseif msg.kind == "toast" then
		Hud.Toast(msg.text)
	elseif msg.kind == "reset" then
		UI.CloseWindow()
		State.SetView(State.HomePlot(), 1)
	end
end)

---------------------------------------------------------------------------
-- Start: wait for our home, then look at it.
---------------------------------------------------------------------------

local loading = UI.new("Frame", {
	Name = "Loading",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(255, 232, 240),
	ZIndex = 50,
	Parent = UI.Screen(),
})
local loadingTitle = UI.title({ Text = "🐾 " .. Config.GameName .. " 🐾", Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromScale(0, 0.38), TextSize = 64, TextColor3 = UI.Colors.Pink, Parent = loading })
UI.textStroke(Color3.fromRGB(170, 60, 100), 3).Parent = loadingTitle
UI.label({ Text = "Fluffing the cushions…", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromScale(0, 0.52), TextSize = 22, Font = UI.Font, Parent = loading })
Hud.SetVisible(false)

task.spawn(function()
	local plot = State.HomePlot()
	while not plot or not State.Profile do
		task.wait(0.2)
		plot = State.HomePlot()
	end
	State.SetView(plot, 1)
	CameraController.Snap()
	task.wait(0.3)
	loading:Destroy()
	Hud.SetVisible(true)
	-- First visit: straight to choosing a kitten.
	if State.Profile and not State.Profile.starterDone then
		task.wait(0.5)
		Windows.Adopt()
	end
end)

player:GetAttributeChangedSignal("Plot"):Connect(function()
	if not State.IsVisiting() then
		State.SetView(State.HomePlot(), State.RoomIndex)
	end
end)
