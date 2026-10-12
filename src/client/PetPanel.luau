-- The panel that opens when you click a pet: portrait, needs, mood and the
-- care actions. Visitors get a smaller panel with just "Pet".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetRules = require(Shared:WaitForChild("PetRules"))
local State = require(script.Parent:WaitForChild("State"))
local UI = require(script.Parent:WaitForChild("UI"))

local PetPanel = {}

local panel: Frame
local portrait: ViewportFrame
local nameLabel: TextLabel
local infoLabel: TextLabel
local moodLabel: TextLabel
local needBars: { [string]: (number, string?) -> () } = {}
local needsFrame: Frame
local actionsFrame: Frame
local popup: Frame? = nil
local buttons: { [string]: TextButton } = {}
local current: Model? = nil

-- Set by the client: opens the shop on a tab, opens the rename dialog.
PetPanel.OpenShop = function(_tab: string) end
PetPanel.Rename = function(_petId: string, _name: string) end

local function closePopup()
	if popup then
		popup:Destroy()
		popup = nil
	end
end

local function petId(): string?
	return current and current:GetAttribute("PetId") :: string?
end

local function care(action: string, extra: { [string]: any }?)
	local id = petId()
	if not id then
		return
	end
	local payload = { petId = id, action = action }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	closePopup()
	State.Request("Care", payload)
end

-- A small list of choices beside the panel.
local function openPopup(title: string, entries: { { text: string, onClick: () -> (), color: Color3? } }, emptyText: string?, emptyAction: { text: string, onClick: () -> () }?)
	closePopup()
	local frame = UI.new("Frame", {
		Name = "Popup",
		Position = UDim2.new(1, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(210, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = UI.Colors.Cream,
		Parent = panel,
	}, { UI.corner(14), UI.stroke(UI.Colors.Edge, 3), UI.padding(8), UI.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center) })
	UI.title({ Text = title, Size = UDim2.new(1, 0, 0, 24), TextSize = 18, LayoutOrder = 0, Parent = frame })
	for i, e in entries do
		UI.button({ Text = e.text, Color = e.color or UI.Colors.Blue, Size = UDim2.new(1, 0, 0, 36), TextSize = 15, LayoutOrder = i, Parent = frame, OnClick = e.onClick })
	end
	if #entries == 0 then
		UI.label({ Text = emptyText or "Nothing here.", Size = UDim2.new(1, 0, 0, 40), TextSize = 14, LayoutOrder = 1, Parent = frame })
		if emptyAction then
			UI.button({ Text = emptyAction.text, Color = UI.Colors.Orange, Size = UDim2.new(1, 0, 0, 36), TextSize = 15, LayoutOrder = 2, Parent = frame, OnClick = emptyAction.onClick })
		end
	end
	UI.button({ Text = "Close", Color = UI.Colors.Gray, Size = UDim2.new(1, 0, 0, 30), TextSize = 14, LayoutOrder = 99, Parent = frame, OnClick = closePopup })
	popup = frame
end

local function itemPopup(actions: { string }, title: string, shopTab: string)
	local entries = {}
	local inventory = State.Profile and State.Profile.inventory or {}
	local ids = {}
	for itemId, count in inventory do
		local item = Config.Items[itemId]
		if item and item.Kind == "Consumable" and table.find(actions, item.Action) and count > 0 then
			table.insert(ids, itemId)
		end
	end
	table.sort(ids, function(a, b)
		return Config.Items[a].Price < Config.Items[b].Price
	end)
	local data = State.PetData(petId() or "")
	local favorite = data and Config.Species[data.species] and Config.Species[data.species].Favorite
	for _, itemId in ids do
		local item = Config.Items[itemId]
		local star = if itemId == favorite then " ⭐" else ""
		table.insert(entries, {
			text = string.format("%s %s ×%d%s", item.Icon, item.Name, inventory[itemId], star),
			onClick = function()
				care("UseItem", { itemId = itemId })
			end,
		})
	end
	openPopup(title, entries, "You don't have any. Buy some in the shop!", {
		text = "🛍️ Go to shop",
		onClick = function()
			closePopup()
			PetPanel.OpenShop(shopTab)
		end,
	})
end

local function movePopup()
	local data = State.PetData(petId() or "")
	if not data or not State.Profile then
		return
	end
	local entries = {}
	for _, room in State.Profile.rooms do
		local def = Config.RoomById(room.id)
		if def and room.id ~= data.room then
			local n = 0
			for _, p in State.Profile.pets do
				if p.room == room.id then
					n += 1
				end
			end
			table.insert(entries, {
				text = string.format("%s (%d/%d)", def.Name, n, def.Capacity),
				color = if n >= def.Capacity then UI.Colors.Gray else UI.Colors.Green,
				onClick = function()
					closePopup()
					local id = petId()
					local result = State.Request("MovePet", { petId = id, roomId = room.id })
					if result.ok then
						local _, order = Config.RoomById(room.id)
						State.SetRoom(order)
						-- Keep the moved pet selected.
						local plot = State.HomePlot()
						local model = plot and id and (plot:FindFirstChild("Pets") :: Folder):FindFirstChild(id)
						if model then
							State.Select(model :: Model)
						end
					end
				end,
			})
		end
	end
	openPopup("Move to…", entries, "Unlock more rooms to move pets around.")
end

local function setPortrait(model: Model)
	portrait:ClearAllChildren()
	local clone = model:Clone()
	for _, d in clone:GetDescendants() do
		if d:IsA("BillboardGui") or d:IsA("Highlight") then
			d:Destroy()
		end
	end
	-- Pets face -Z; the portrait camera looks from -Z, turned a little for a 3/4 view.
	clone:PivotTo(CFrame.Angles(0, math.rad(25), 0))
	clone.Parent = portrait
	local root = clone.PrimaryPart
	local h = if root then ((root:GetAttribute("Height") :: number?) or root.Size.Y) else 3
	local cam = UI.new("Camera", { FieldOfView = 30, Parent = portrait })
	cam.CFrame = CFrame.lookAt(Vector3.new(0, h * 0.62, -h * 3.2), Vector3.new(0, h * 0.5, 0))
	portrait.CurrentCamera = cam
end

local function actionButton(id: string, text: string, color: Color3, order: number, tip: string, onClick: () -> ())
	buttons[id] = UI.button({ Name = id, Text = text, Color = color, Size = UDim2.fromOffset(112, 34), TextSize = 15, LayoutOrder = order, Parent = actionsFrame, Tooltip = tip, OnClick = onClick })
end

local function refresh()
	local model = current
	if not model then
		return
	end
	local visiting = State.IsVisiting()
	local data = if visiting then nil else State.PetData(model:GetAttribute("PetId") :: string)
	local gender = model:GetAttribute("Gender")
	nameLabel.Text = (model:GetAttribute("Name") or "?") .. (if gender == "F" then " ♀" else " ♂")
	nameLabel.TextColor3 = if gender == "F" then Color3.fromRGB(230, 90, 150) else Color3.fromRGB(70, 130, 220)
	local mood = (model:GetAttribute("Mood") :: number?) or 0
	local moodText, moodIcon = PetRules.MoodLabel(mood)
	moodLabel.Text = moodIcon .. " " .. moodText .. (if model:GetAttribute("Sleeping") then " · Sleeping 💤" else "")

	if data then
		local rarity = PetRules.Rarity(data.species, data)
		infoLabel.Text = string.format("%s %s · %s%s", data.color, PetRules.DisplaySpecies(data), data.pattern, if rarity == "Rare" then " · ✨Rare" else "")
		for _, need in Config.Needs do
			local v = data.needs[need] or 0
			needBars[need](v / 100, string.format("%s %d%%", Config.NeedInfo[need].Label, math.floor(v + 0.5)))
		end
		needsFrame.Visible = true
		local now = workspace:GetServerTimeNow()
		local sleeping = data.sleeping
		for id, btn in buttons do
			btn.Visible = id ~= "Visit"
		end
		buttons.Sleep.Text = if sleeping then "☀️ Wake" else "💤 Sleep"
		for _, action in { "Play", "Brush" } do
			local left = PetRules.CooldownLeft(data, action, now)
			local label = if action == "Play" then "🎾 Play" else "🪮 Brush"
			buttons[action].Text = if left > 0 then string.format("%s %ds", label, math.ceil(left)) else label
			UI.SetEnabled(buttons[action], left <= 0 and not sleeping)
		end
		for _, id in { "Feed", "Care" } do
			UI.SetEnabled(buttons[id], not sleeping)
		end
	else
		infoLabel.Text = (model:GetAttribute("Species") or "") .. (if model:GetAttribute("Stage") == "Baby" then " (baby)" else "")
		needsFrame.Visible = false
		for id, btn in buttons do
			btn.Visible = id == "Visit"
		end
	end
end

function PetPanel.Open(model: Model)
	current = model
	closePopup()
	panel.Visible = true
	setPortrait(model)
	refresh()
end

function PetPanel.Close()
	current = nil
	closePopup()
	panel.Visible = false
end

function PetPanel.Current(): Model?
	return current
end

function PetPanel.Init()
	local screen = UI.Screen()
	panel = UI.new("Frame", {
		Name = "PetPanel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, -20),
		Size = UDim2.fromOffset(262, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = UI.Colors.Cream,
		Visible = false,
		Parent = screen,
	}, { UI.corner(18), UI.stroke(UI.Colors.Edge, 4) })
	-- The panel's contents; the close button and popups sit outside the list.
	local body = UI.new("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = panel,
	}, { UI.padding(10), UI.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center) })
	UI.button({
		Text = "✕",
		Color = UI.Colors.Red,
		Size = UDim2.fromOffset(32, 32),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		TextSize = 16,
		Parent = panel,
		OnClick = function()
			State.Select(nil)
		end,
	})

	portrait = UI.new("ViewportFrame", {
		Size = UDim2.fromOffset(150, 120),
		BackgroundColor3 = Color3.fromRGB(255, 232, 240),
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.5, -1, 0.6),
		LayoutOrder = 1,
		Parent = body,
	}, { UI.corner(16), UI.stroke(Color3.fromRGB(240, 170, 200), 3) })
	nameLabel = UI.title({ Size = UDim2.new(1, 0, 0, 28), TextSize = 24, LayoutOrder = 2, Parent = body })
	infoLabel = UI.label({ Size = UDim2.new(1, 0, 0, 18), TextSize = 14, TextColor3 = UI.Colors.Soft, LayoutOrder = 3, Parent = body })
	moodLabel = UI.label({ Size = UDim2.new(1, 0, 0, 20), TextSize = 16, Font = UI.Font, LayoutOrder = 4, Parent = body })

	needsFrame = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 5, Parent = body }, { UI.list(Enum.FillDirection.Vertical, 4) })
	for i, need in Config.Needs do
		local info = Config.NeedInfo[need]
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = i, Parent = needsFrame })
		UI.label({ Size = UDim2.fromOffset(26, 22), Text = info.Icon, TextSize = 18, Parent = row })
		local _, set = UI.bar({ Position = UDim2.fromOffset(30, 2), Size = UDim2.new(1, -32, 0, 18), Parent = row, TextSize = 12 }, info.Color)
		needBars[need] = set
	end

	actionsFrame = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 6, Parent = body }, { UI.grid(UDim2.fromOffset(116, 34), 6) })
	actionButton("Pet", "✋ Pet", UI.Colors.Pink, 1, "Give some love", function()
		care("Pet")
	end)
	actionButton("Feed", "🍖 Feed", UI.Colors.Orange, 2, "Feed food from your inventory", function()
		itemPopup({ "Feed" }, "Feed with…", "Food")
	end)
	actionButton("Play", "🎾 Play", UI.Colors.Blue, 3, "Play with a toy in this room", function()
		care("Play")
	end)
	actionButton("Brush", "🪮 Brush", Color3.fromRGB(90, 190, 210), 4, "A quick brush keeps fur clean", function()
		care("Brush")
	end)
	actionButton("Care", "🧴 Care", UI.Colors.Purple, 5, "Bath, treats and vitamins", function()
		itemPopup({ "Bath", "Treat", "Medicine" }, "Use…", "Care")
	end)
	actionButton("Sleep", "💤 Sleep", Color3.fromRGB(120, 140, 220), 6, "Send to bed or wake up", function()
		local data = State.PetData(petId() or "")
		care(if data and data.sleeping then "Wake" else "Sleep")
	end)
	actionButton("Rename", "✏️ Rename", UI.Colors.Gray, 7, "Change this pet's name", function()
		local id = petId()
		local data = id and State.PetData(id)
		if id and data then
			PetPanel.Rename(id, data.name)
		end
	end)
	actionButton("Move", "🚪 Move", UI.Colors.Green, 8, "Move to another room", movePopup)
	actionButton("Visit", "✋ Pet", UI.Colors.Pink, 9, "Pet your neighbour's pet (bonus once a day)", function()
		local model = current
		if not model then
			return
		end
		State.Request("VisitPet", { ownerId = model:GetAttribute("Owner"), petId = model:GetAttribute("PetId") })
	end)

	State.SelectionChanged:Connect(function(model)
		if model then
			PetPanel.Open(model)
		else
			PetPanel.Close()
		end
	end)
	State.ProfileChanged:Connect(refresh)
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum >= 0.5 and current then
			accum = 0
			if not current.Parent then
				State.Select(nil)
				return
			end
			refresh()
		end
	end)
end

return PetPanel
