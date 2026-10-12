-- The pop-up windows: Adopt, My Pets, Shop, Items, Breed, Rooms, Visit,
-- Settings, plus the name dialog used for adopting, babies and renaming.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetRules = require(Shared:WaitForChild("PetRules"))
local PetModels = require(Shared:WaitForChild("PetModels"))
local FurnitureModels = require(Shared:WaitForChild("FurnitureModels"))
local State = require(script.Parent:WaitForChild("State"))
local UI = require(script.Parent:WaitForChild("UI"))

local player = Players.LocalPlayer

local Windows = {}

-- Set by the client.
Windows.StartPlacing = function(_itemId: string) end
Windows.Toast = function(_text: string) end

local rgb = Color3.fromRGB
local RARE = rgb(190, 120, 240)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- A 3D preview of a model. `fromFront` is the side the camera looks from.
local function preview(parent: Instance, model: Model, size: UDim2, order: number?, fromFront: boolean?): ViewportFrame
	local vp = UI.new("ViewportFrame", {
		Size = size,
		BackgroundColor3 = rgb(255, 238, 244),
		Ambient = rgb(200, 200, 200),
		LightColor = rgb(255, 255, 255),
		LightDirection = Vector3.new(-0.4, -1, -0.5),
		LayoutOrder = order or 0,
		Parent = parent,
	}, { UI.corner(12) })
	model.Parent = vp
	local cf, extents = model:GetBoundingBox()
	local radius = extents.Magnitude * 0.5
	local dir = if fromFront then Vector3.new(0.45, 0.55, 1) else Vector3.new(0.45, 0.45, -1)
	local cam = UI.new("Camera", { FieldOfView = 32, Parent = vp })
	cam.CFrame = CFrame.lookAt(cf.Position + dir.Unit * radius * 3.1, cf.Position)
	vp.CurrentCamera = cam
	return vp
end

local function petPreview(parent: Instance, look: any, size: UDim2, order: number?): ViewportFrame
	return preview(parent, PetModels.Build(look), size, order, false)
end

local function card(parent: Instance, order: number?, color: Color3?): Frame
	return UI.new("Frame", {
		BackgroundColor3 = color or UI.Colors.Panel,
		LayoutOrder = order or 0,
		Parent = parent,
	}, { UI.corner(14), UI.stroke(UI.Colors.Edge, 2) })
end

local function cardGrid(parent: Instance, cell: Vector2, order: number?): Frame
	local f = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	local grid = UI.grid(UDim2.fromOffset(cell.X, cell.Y), 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = f
	return f
end

local function note(parent: Instance, text: string, order: number?): TextLabel
	return UI.label({ Text = text, Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 16, TextColor3 = UI.Colors.Soft, LayoutOrder = order or 0, Parent = parent })
end

local function petCount(roomId: string?): number
	local n = 0
	for _, p in (State.Profile and State.Profile.pets or {}) do
		if not roomId or p.room == roomId then
			n += 1
		end
	end
	return n
end

local function sortedPets(): { any }
	local list = {}
	for _, p in (State.Profile and State.Profile.pets or {}) do
		table.insert(list, p)
	end
	table.sort(list, function(a, b)
		return (tonumber(string.sub(a.id, 2)) or 0) < (tonumber(string.sub(b.id, 2)) or 0)
	end)
	return list
end

local function selectPet(petId: string)
	local plot = State.HomePlot()
	local model = plot and (plot:FindFirstChild("Pets") :: Folder):FindFirstChild(petId)
	local data = State.PetData(petId)
	if not model or not data then
		return
	end
	if State.IsVisiting() then
		State.SetView(plot, 1)
	end
	local _, order = Config.RoomById(data.room)
	State.SetRoom(order or 1)
	State.Select(model :: Model)
end

---------------------------------------------------------------------------
-- Name dialog
---------------------------------------------------------------------------

-- Asks for a name (and optionally boy/girl). onSubmit returns true to close.
function Windows.NameDialog(title: string, message: string, default: string, askGender: boolean, onSubmit: (string, string) -> boolean)
	local _, content = UI.window("Name", title, Vector2.new(440, if askGender then 360 else 290))
	note(content, message, 1)
	local box = UI.new("TextBox", {
		Size = UDim2.new(1, -20, 0, 46),
		BackgroundColor3 = UI.Colors.White,
		Font = UI.Font,
		TextSize = 22,
		TextColor3 = UI.Colors.Ink,
		PlaceholderText = "Type a name",
		PlaceholderColor3 = UI.Colors.Gray,
		Text = default,
		ClearTextOnFocus = false,
		LayoutOrder = 2,
		Parent = content,
	}, { UI.corner(12), UI.stroke(UI.Colors.Edge, 3) })
	local gender = if math.random() < 0.5 then "F" else "M"
	if askGender then
		local row = UI.row(content, 46, 3)
		UI.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center).Parent = row
		local boy, girl
		local function paint()
			boy.BackgroundColor3 = if gender == "M" then rgb(70, 130, 220) else UI.Colors.Gray
			boy:SetAttribute("BaseColor", boy.BackgroundColor3)
			girl.BackgroundColor3 = if gender == "F" then rgb(230, 90, 150) else UI.Colors.Gray
			girl:SetAttribute("BaseColor", girl.BackgroundColor3)
		end
		boy = UI.button({ Text = "♂ Boy", Size = UDim2.fromOffset(130, 42), LayoutOrder = 1, Parent = row, OnClick = function()
			gender = "M"
			paint()
		end })
		girl = UI.button({ Text = "♀ Girl", Size = UDim2.fromOffset(130, 42), LayoutOrder = 2, Parent = row, OnClick = function()
			gender = "F"
			paint()
		end })
		paint()
	end
	local okButton: TextButton
	local function submit()
		local name = PetRules.CleanName(box.Text)
		if not name then
			Windows.Toast("Names need 1-20 letters or numbers.")
			return
		end
		UI.SetEnabled(okButton, false)
		okButton.Text = "…"
		local close = onSubmit(name, gender)
		if close then
			UI.CloseWindow()
		elseif okButton.Parent then
			UI.SetEnabled(okButton, true)
			okButton.Text = "OK"
		end
	end
	okButton = UI.button({ Text = "OK", Color = UI.Colors.Green, Size = UDim2.fromOffset(160, 46), LayoutOrder = 4, Parent = content, OnClick = submit })
	box.FocusLost:Connect(function(enter)
		if enter then
			submit()
		end
	end)
	task.defer(function()
		box:CaptureFocus()
	end)
end

local SUGGESTED = { "Mittens", "Biscuit", "Pumpkin", "Daisy", "Pepper", "Mochi", "Luna", "Oreo", "Peanut", "Clover", "Ziggy", "Hazel", "Noodle", "Maple", "Sprout", "Pip" }

local function suggestName(): string
	return SUGGESTED[math.random(1, #SUGGESTED)]
end

---------------------------------------------------------------------------
-- Adopt
---------------------------------------------------------------------------

function Windows.Adopt()
	local _, content = UI.window("Adopt", "Adoption Centre", Vector2.new(760, 600))
	local info = State.Request("GetAdoption")
	if not info.ok or not content.Parent then
		return
	end
	local starter = info.starter
	local body: Frame? = nil

	local function showSpecies(speciesId: string)
		if body then
			body:Destroy()
		end
		body = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3, Parent = content }, { UI.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center) })
		local entry
		for _, e in info.species do
			if e.species == speciesId then
				entry = e
			end
		end
		local def = Config.Species[speciesId]
		if not entry.unlocked then
			note(body :: Frame, string.format("🔒 %ss unlock at level %d. Keep caring for your pets to level up!", def.Name, def.Level), 1)
			return
		end
		local grid = cardGrid(body :: Frame, Vector2.new(170, 250), 2)
		for _, c in entry.candidates do
			local rare = c.rarity == "Rare"
			local f = card(grid, c.index, if rare then rgb(248, 236, 255) else nil)
			UI.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center).Parent = f
			UI.padding(6).Parent = f
			petPreview(f, { species = speciesId, color = c.look.color, pattern = c.look.pattern, eyes = c.look.eyes, stage = "Adult" }, UDim2.fromOffset(150, 120), 1)
			UI.title({ Text = (if rare then "✨ " else "") .. c.look.color .. " " .. def.Name, Size = UDim2.new(1, 0, 0, 22), TextSize = 17, TextColor3 = if rare then RARE else UI.Colors.Ink, LayoutOrder = 2, Parent = f })
			UI.label({ Text = c.look.pattern .. " · " .. c.look.eyes .. " eyes", Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = UI.Colors.Soft, LayoutOrder = 3, Parent = f })
			local free = starter and speciesId == "Cat"
			local price = if free then 0 else c.price
			local btn = UI.button({
				Text = if c.taken then "Adopted ✓" elseif free then "Adopt FREE" else "Adopt 🪙" .. price,
				Color = if free then UI.Colors.Green else UI.Colors.Pink,
				Size = UDim2.fromOffset(150, 38),
				TextSize = 16,
				LayoutOrder = 4,
				Parent = f,
				OnClick = function()
					Windows.NameDialog("Name your " .. string.lower(def.Name), "What will you call your new " .. c.look.color .. " " .. string.lower(def.Name) .. "?", suggestName(), true, function(name, gender)
						local result = State.Request("Adopt", { species = speciesId, index = c.index, name = name, gender = gender })
						if result.ok then
							UI.Play("Coin", 0.5)
							task.defer(function()
								local _, order = Config.RoomById(result.room)
								State.SetView(State.HomePlot(), order or 1)
								task.wait(0.4)
								selectPet(result.petId)
							end)
						end
						return result.ok == true
					end)
				end,
			})
			if c.taken or (not free and State.Profile and State.Profile.coins < price) then
				UI.SetEnabled(btn, false)
			end
		end
	end

	if starter then
		note(content, "Welcome to Happy Pets! 🐱 Choose your very first kitten. It's free! Then feed it, play with it, and build it a cosy home.", 1)
	else
		local p = State.Profile
		note(content, string.format("Your home has room for %d pets (%d now). New pets arrive every day. Rare coats are marked ✨.", p and p.capacity or 0, petCount()), 1)
	end
	local tabs = {}
	for _, e in info.species do
		if not starter or e.species == "Cat" then
			table.insert(tabs, e.species)
		end
	end
	local highlight = UI.tabs(content, tabs, showSpecies, 2)
	highlight(tabs[1])
	showSpecies(tabs[1])
	if not starter then
		UI.button({
			Text = "🔄 Show me different pets (🪙" .. info.rerollCost .. ")",
			Color = UI.Colors.Blue,
			Size = UDim2.fromOffset(320, 40),
			TextSize = 16,
			LayoutOrder = 4,
			Parent = content,
			OnClick = function()
				local r = State.Request("RerollAdoption")
				if r.ok then
					Windows.Adopt()
				end
			end,
		})
	end
end

---------------------------------------------------------------------------
-- My Pets
---------------------------------------------------------------------------

function Windows.Pets()
	local _, content = UI.window("Pets", "My Pets", Vector2.new(760, 600))
	local p = State.Profile
	if not p then
		return
	end
	local pets = sortedPets()
	note(content, string.format("%d of %d spaces used. Unlock rooms to make space for more pets.", #pets, p.capacity), 1)
	if #pets == 0 then
		note(content, "You don't have any pets yet!", 2)
		UI.button({ Text = "🐾 Adopt a pet", Color = UI.Colors.Pink, Size = UDim2.fromOffset(200, 44), LayoutOrder = 3, Parent = content, OnClick = Windows.Adopt })
		return
	end
	local grid = cardGrid(content, Vector2.new(220, 236), 2)
	for i, pet in pets do
		local f = card(grid, i)
		UI.padding(6).Parent = f
		UI.list(Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Center).Parent = f
		petPreview(f, pet, UDim2.fromOffset(200, 100), 1)
		local g = if pet.gender == "F" then " ♀" else " ♂"
		UI.title({ Text = pet.name .. g, Size = UDim2.new(1, 0, 0, 22), TextSize = 18, TextColor3 = if pet.gender == "F" then rgb(230, 90, 150) else rgb(70, 130, 220), LayoutOrder = 2, Parent = f })
		local rare = PetRules.Rarity(pet.species, pet) == "Rare"
		UI.label({ Text = string.format("%s%s %s · %s", if rare then "✨" else "", pet.color, PetRules.DisplaySpecies(pet), pet.pattern), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = UI.Colors.Soft, LayoutOrder = 3, Parent = f })
		local moodText, moodIcon = PetRules.MoodLabel(PetRules.Mood(pet))
		local roomDef = Config.RoomById(pet.room)
		UI.label({ Text = string.format("%s %s · %s%s", moodIcon, moodText, roomDef and roomDef.Name or "?", if pet.sleeping then " · 💤" else ""), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, LayoutOrder = 4, Parent = f })
		local row = UI.row(f, 34, 5)
		UI.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center).Parent = row
		UI.button({ Text = "🔍 Find", Color = UI.Colors.Blue, Size = UDim2.fromOffset(98, 32), TextSize = 14, LayoutOrder = 1, Parent = row, OnClick = function()
			UI.CloseWindow()
			selectPet(pet.id)
		end })
		UI.button({ Text = "✏️ Rename", Color = UI.Colors.Gray, Size = UDim2.fromOffset(98, 32), TextSize = 14, LayoutOrder = 2, Parent = row, OnClick = function()
			Windows.Rename(pet.id, pet.name)
		end })
	end
end

function Windows.Rename(petId: string, current: string)
	Windows.NameDialog("Rename", "Choose a new name for " .. current .. ".", current, false, function(name)
		local result = State.Request("Rename", { petId = petId, name = name })
		if result.ok then
			Windows.Toast("Renamed to " .. tostring(result.name) .. "!")
		end
		return result.ok == true
	end)
end

---------------------------------------------------------------------------
-- Shop
---------------------------------------------------------------------------

local function styleSwatch(parent: Instance, style: any, kind: string, order: number?): Frame
	local swatch = UI.new("Frame", { Size = UDim2.fromOffset(150, 80), BackgroundColor3 = style.Color, LayoutOrder = order or 0, Parent = parent }, { UI.corner(10), UI.stroke(UI.Colors.Edge, 2) })
	local accent = if kind == "Wallpaper" then style.Accent else style.Alt
	if style.Pattern == "Stripes" then
		for i = 0, 4 do
			UI.new("Frame", { Position = UDim2.new(i * 0.2 + 0.05, 0, 0, 0), Size = UDim2.new(0.1, 0, 1, 0), BackgroundColor3 = accent, BorderSizePixel = 0, Parent = swatch })
		end
	elseif style.Pattern == "Dots" or style.Pattern == "Stars" then
		for i = 0, 5 do
			local dot = UI.new("Frame", { Position = UDim2.new((i % 3) * 0.3 + 0.12, 0, (i // 3) * 0.45 + 0.15, 0), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = accent, Rotation = if style.Pattern == "Stars" then 45 else 0, Parent = swatch })
			if style.Pattern == "Dots" then
				UI.corner(7).Parent = dot
			end
		end
	elseif style.Pattern == "Checker" then
		for x = 0, 5 do
			for y = 0, 2 do
				if (x + y) % 2 == 1 then
					UI.new("Frame", { Position = UDim2.fromScale(x / 6, y / 3), Size = UDim2.fromScale(1 / 6, 1 / 3), BackgroundColor3 = accent, BorderSizePixel = 0, Parent = swatch })
				end
			end
		end
	end
	return swatch
end

local function ownsStyle(kind: string, style: any): boolean
	return style.Price == 0 or (State.Profile and State.Profile.styles[style.Id] == true)
end

function Windows.Shop(startTab: string?)
	local _, content = UI.window("Shop", "Pet Shop", Vector2.new(780, 620))
	local body: Frame? = nil
	local currentTab = startTab or "Food"

	local function showTab(tab: string)
		currentTab = tab
		if body then
			body:Destroy()
		end
		body = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3, Parent = content }, { UI.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center) })
		local p = State.Profile
		if not p then
			return
		end

		if tab == "Styles" then
			for kindIndex, kind in { "Wallpaper", "Floor" } do
				UI.title({ Text = if kind == "Wallpaper" then "Wallpaper" else "Floors", Size = UDim2.new(1, 0, 0, 26), LayoutOrder = kindIndex * 10, Parent = body })
				local grid = cardGrid(body :: Frame, Vector2.new(170, 190), kindIndex * 10 + 1)
				local list = if kind == "Wallpaper" then Config.Wallpapers else Config.Floors
				for i, style in list do
					if style.Id == "grass" then
						continue
					end
					local f = card(grid, i)
					UI.padding(8).Parent = f
					UI.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center).Parent = f
					styleSwatch(f, style, kind, 1)
					UI.title({ Text = style.Name, Size = UDim2.new(1, 0, 0, 20), TextSize = 16, LayoutOrder = 2, Parent = f })
					local owned = ownsStyle(kind, style)
					local locked = p.level < style.Level
					local btn = UI.button({
						Text = if owned then "Owned ✓" elseif locked then "🔒 Level " .. style.Level else "Buy 🪙" .. style.Price,
						Color = UI.Colors.Orange,
						Size = UDim2.fromOffset(150, 36),
						TextSize = 15,
						LayoutOrder = 3,
						Parent = f,
						OnClick = function()
							local r = State.Request("BuyStyle", { kind = kind, styleId = style.Id })
							if r.ok then
								Windows.Toast("Bought " .. style.Name .. "! Apply it from 🏠 Rooms.")
								showTab(currentTab)
							end
						end,
					})
					if owned or locked or p.coins < style.Price then
						UI.SetEnabled(btn, false)
					end
				end
			end
			return
		end

		local ids = {}
		for id, item in Config.Items do
			if item.Tab == tab then
				table.insert(ids, id)
			end
		end
		table.sort(ids, function(a, b)
			local ia, ib = Config.Items[a], Config.Items[b]
			if ia.Level ~= ib.Level then
				return ia.Level < ib.Level
			end
			return ia.Price < ib.Price
		end)
		local grid = cardGrid(body :: Frame, Vector2.new(170, 236), 1)
		for i, id in ids do
			local item = Config.Items[id]
			local locked = p.level < item.Level
			local f = card(grid, i)
			UI.padding(6).Parent = f
			UI.list(Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Center).Parent = f
			if item.Kind == "Furniture" then
				preview(f, FurnitureModels.Create(id), UDim2.fromOffset(150, 90), 1, true)
			else
				local icon = UI.new("Frame", { Size = UDim2.fromOffset(150, 90), BackgroundColor3 = rgb(255, 238, 244), LayoutOrder = 1, Parent = f }, { UI.corner(12) })
				UI.label({ Size = UDim2.fromScale(1, 1), Text = item.Icon, TextSize = 52, Parent = icon })
			end
			UI.title({ Text = item.Name, Size = UDim2.new(1, 0, 0, 20), TextSize = 16, LayoutOrder = 2, Parent = f })
			local effects = {}
			if item.Effects then
				for _, need in Config.Needs do
					local v = item.Effects[need]
					if v then
						table.insert(effects, string.format("%s+%d", Config.NeedInfo[need].Icon, v))
					end
				end
			end
			local desc = item.Desc .. (if #effects > 0 then "\n" .. table.concat(effects, " ") elseif item.Comfort and item.Comfort > 0 then "\n😌 Comfort +" .. item.Comfort else "")
			UI.label({ Text = desc, Size = UDim2.new(1, 0, 0, 40), TextSize = 12, TextColor3 = UI.Colors.Soft, LayoutOrder = 3, Parent = f })
			local owned = p.inventory[id] or 0
			UI.label({ Text = if owned > 0 then "You have " .. owned else " ", Size = UDim2.new(1, 0, 0, 14), TextSize = 12, LayoutOrder = 4, Parent = f })
			local row = UI.row(f, 36, 5)
			UI.list(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center).Parent = row
			local function buy(qty: number)
				local r = State.Request("Buy", { itemId = id, qty = qty })
				if r.ok then
					UI.Play("Coin", 0.4)
					if item.Kind == "Furniture" then
						UI.confirm("Bought " .. item.Name .. "!", "Place it in your room now? You can also place it later from 🎒 Items.", "Place it!", function()
							Windows.StartPlacing(id)
						end)
					else
						Windows.Toast(string.format("Bought %d × %s!", qty, item.Name))
						showTab(currentTab)
					end
				end
			end
			if locked then
				local b = UI.button({ Text = "🔒 Level " .. item.Level, Color = UI.Colors.Gray, Size = UDim2.fromOffset(150, 34), TextSize = 15, LayoutOrder = 1, Parent = row })
				UI.SetEnabled(b, false)
			else
				local b1 = UI.button({ Text = "🪙" .. item.Price, Color = UI.Colors.Orange, Size = UDim2.fromOffset(if item.Kind == "Consumable" then 74 else 150, 34), TextSize = 15, LayoutOrder = 1, Parent = row, Tooltip = "Buy one", OnClick = function()
					buy(1)
				end })
				UI.SetEnabled(b1, p.coins >= item.Price)
				if item.Kind == "Consumable" then
					local b5 = UI.button({ Text = "×5 🪙" .. item.Price * 5, Color = UI.Colors.Orange, Size = UDim2.fromOffset(74, 34), TextSize = 13, LayoutOrder = 2, Parent = row, Tooltip = "Buy five", OnClick = function()
						buy(5)
					end })
					UI.SetEnabled(b5, p.coins >= item.Price * 5)
				end
			end
		end
	end

	note(content, "Food and care items are used on pets. Toys and furniture go in your rooms, and decorations keep pets happy for longer.", 1)
	local highlight = UI.tabs(content, Config.ShopTabs, showTab, 2)
	highlight(currentTab)
	showTab(currentTab)
end

---------------------------------------------------------------------------
-- Items (inventory)
---------------------------------------------------------------------------

function Windows.Items()
	local _, content = UI.window("Items", "My Items", Vector2.new(720, 580))
	local p = State.Profile
	if not p then
		return
	end
	local consumables, furniture = {}, {}
	for id, count in p.inventory do
		local item = Config.Items[id]
		if item and count > 0 then
			table.insert(if item.Kind == "Consumable" then consumables else furniture, id)
		end
	end
	table.sort(consumables)
	table.sort(furniture)

	UI.title({ Text = "Food & care", Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Parent = content })
	if #consumables == 0 then
		note(content, "No food or care items. Pick some up in the shop!", 2)
	else
		local grid = cardGrid(content, Vector2.new(150, 150), 2)
		for i, id in consumables do
			local item = Config.Items[id]
			local f = card(grid, i)
			UI.padding(6).Parent = f
			UI.list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Center).Parent = f
			UI.label({ Text = item.Icon, Size = UDim2.new(1, 0, 0, 44), TextSize = 38, LayoutOrder = 1, Parent = f })
			UI.title({ Text = item.Name, Size = UDim2.new(1, 0, 0, 20), TextSize = 15, LayoutOrder = 2, Parent = f })
			UI.label({ Text = "×" .. p.inventory[id], Size = UDim2.new(1, 0, 0, 18), TextSize = 15, LayoutOrder = 3, Parent = f })
			UI.button({ Text = "Use", Color = UI.Colors.Green, Size = UDim2.fromOffset(120, 32), TextSize = 15, LayoutOrder = 4, Parent = f, Tooltip = "Use on the selected pet", OnClick = function()
				local pet = State.SelectedPet
				if not pet or State.IsVisiting() then
					Windows.Toast("Click one of your pets first, then use the item.")
					UI.CloseWindow()
					return
				end
				local r = State.Request("Care", { petId = pet:GetAttribute("PetId"), action = "UseItem", itemId = id })
				if r.ok then
					UI.CloseWindow()
				end
			end })
		end
	end

	UI.title({ Text = "Furniture & toys", Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 3, Parent = content })
	if #furniture == 0 then
		note(content, "Everything you own is already placed. Buy more in the shop, or use 🛋️ Decorate to put items away.", 4)
	else
		local grid = cardGrid(content, Vector2.new(150, 170), 4)
		for i, id in furniture do
			local item = Config.Items[id]
			local f = card(grid, i)
			UI.padding(6).Parent = f
			UI.list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Center).Parent = f
			preview(f, FurnitureModels.Create(id), UDim2.fromOffset(130, 70), 1, true)
			UI.title({ Text = item.Name, Size = UDim2.new(1, 0, 0, 20), TextSize = 15, LayoutOrder = 2, Parent = f })
			UI.label({ Text = "×" .. p.inventory[id], Size = UDim2.new(1, 0, 0, 16), TextSize = 14, LayoutOrder = 3, Parent = f })
			UI.button({ Text = "Place", Color = UI.Colors.Green, Size = UDim2.fromOffset(120, 32), TextSize = 15, LayoutOrder = 4, Parent = f, OnClick = function()
				UI.CloseWindow()
				Windows.StartPlacing(id)
			end })
		end
	end
end

---------------------------------------------------------------------------
-- Breed
---------------------------------------------------------------------------

function Windows.Breed()
	local _, content = UI.window("Breed", "Baby Pets", Vector2.new(760, 620))
	local p = State.Profile
	if not p then
		return
	end
	local now = workspace:GetServerTimeNow()

	-- Babies on the way.
	if #p.births > 0 then
		UI.title({ Text = "Babies on the way", Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Parent = content })
		local grid = cardGrid(content, Vector2.new(200, 210), 2)
		for i, b in p.births do
			local def = Config.Species[b.species]
			local f = card(grid, i, rgb(255, 240, 246))
			UI.padding(6).Parent = f
			UI.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center).Parent = f
			local ready = b.readyAt <= now
			if ready then
				petPreview(f, { species = b.species, color = b.look.color, pattern = b.look.pattern, eyes = b.look.eyes, stage = "Baby" }, UDim2.fromOffset(180, 100), 1)
			else
				local egg = UI.new("Frame", { Size = UDim2.fromOffset(180, 100), BackgroundColor3 = rgb(255, 238, 244), LayoutOrder = 1, Parent = f }, { UI.corner(12) })
				UI.label({ Size = UDim2.fromScale(1, 1), Text = "🎀", TextSize = 50, Parent = egg })
			end
			local status = UI.title({ Text = if ready then "A " .. string.lower(def.Baby) .. " is here!" else "", Size = UDim2.new(1, 0, 0, 22), TextSize = 16, LayoutOrder = 2, Parent = f })
			if not ready then
				local conn
				conn = RunService.Heartbeat:Connect(function()
					if not status.Parent then
						conn:Disconnect()
						return
					end
					local left = math.max(0, b.readyAt - workspace:GetServerTimeNow())
					status.Text = string.format("Arriving in %d:%02d", left // 60, math.floor(left % 60))
					if left <= 0 then
						conn:Disconnect()
						Windows.Breed()
					end
				end)
			end
			local btn = UI.button({ Text = "💕 Meet baby", Color = UI.Colors.Pink, Size = UDim2.fromOffset(170, 38), TextSize = 16, LayoutOrder = 3, Parent = f, OnClick = function()
				Windows.NameDialog("Name your " .. string.lower(def.Baby), "Your new " .. b.look.color .. " " .. string.lower(def.Baby) .. " needs a name!", suggestName(), true, function(name, gender)
					local r = State.Request("ClaimBirth", { birthId = b.id, name = name, gender = gender })
					if r.ok then
						task.defer(function()
							local _, order = Config.RoomById(r.room)
							State.SetView(State.HomePlot(), order or 1)
							task.wait(0.4)
							selectPet(r.petId)
						end)
					end
					return r.ok == true
				end)
			end })
			UI.SetEnabled(btn, ready)
		end
	end

	note(content, string.format("Pick a boy and a girl of the same kind. Both must be grown up and happy. Costs 🪙%d; the baby arrives after %d minutes and inherits its parents' coats, with a small chance of something rare ✨.", Config.Breeding.Cost, Config.Breeding.Duration // 60), 3)

	local adults = {}
	for _, pet in sortedPets() do
		if pet.stage == "Adult" then
			table.insert(adults, pet)
		end
	end
	if #adults < 2 then
		note(content, "You need at least two grown-up pets (a boy and a girl of the same kind). Adopt more from 🐾 Adopt!", 4)
		return
	end

	local chosen: { [string]: any } = { M = nil, F = nil }
	local row = UI.row(content, 0, 5)
	row.AutomaticSize = Enum.AutomaticSize.Y
	UI.list(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center).Parent = row
	local breedButton: TextButton
	local summary: TextLabel
	local columnButtons: { [string]: { [string]: TextButton } } = { M = {}, F = {} }

	local function refreshChoice()
		for gender, buttons in columnButtons do
			for id, btn in buttons do
				local on = chosen[gender] and chosen[gender].id == id
				local base = if gender == "F" then rgb(230, 90, 150) else rgb(70, 130, 220)
				btn.BackgroundColor3 = if on then base else rgb(200, 196, 200)
				btn:SetAttribute("BaseColor", btn.BackgroundColor3)
			end
		end
		local a, b = chosen.M, chosen.F
		if a and b then
			local ok, why = PetRules.CanBreed(a, b, workspace:GetServerTimeNow())
			summary.Text = if ok then string.format("%s + %s 💕 Their baby could be %s or %s, %s or %s.", a.name, b.name, a.color, b.color, a.pattern, b.pattern) else "⚠ " .. tostring(why)
			UI.SetEnabled(breedButton, ok == true and p.coins >= Config.Breeding.Cost)
		else
			summary.Text = "Choose one pet from each column."
			UI.SetEnabled(breedButton, false)
		end
	end

	for _, gender in { "M", "F" } do
		local col = UI.new("Frame", { Size = UDim2.fromOffset(300, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = if gender == "M" then 1 else 2, Parent = row }, { UI.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center) })
		UI.title({ Text = if gender == "M" then "♂ Boys" else "♀ Girls", Size = UDim2.new(1, 0, 0, 24), TextColor3 = if gender == "F" then rgb(230, 90, 150) else rgb(70, 130, 220), Parent = col })
		local any = false
		for i, pet in adults do
			if pet.gender == gender then
				any = true
				local cooling = workspace:GetServerTimeNow() - (pet.lastBredAt or 0) < Config.Breeding.Cooldown
				columnButtons[gender][pet.id] = UI.button({
					Text = string.format("%s · %s %s%s", pet.name, pet.color, Config.Species[pet.species].Name, if cooling then " ⏳" else ""),
					Color = rgb(200, 196, 200),
					Size = UDim2.new(1, 0, 0, 36),
					TextSize = 14,
					LayoutOrder = i,
					Parent = col,
					OnClick = function()
						chosen[gender] = pet
						refreshChoice()
					end,
				})
			end
		end
		if not any then
			note(col, "No grown-up " .. (if gender == "M" then "boys" else "girls") .. " yet.", 99)
		end
	end
	summary = note(content, "", 6)
	summary.TextColor3 = UI.Colors.Ink
	breedButton = UI.button({ Text = "💞 Breed (🪙" .. Config.Breeding.Cost .. ")", Color = UI.Colors.Pink, Size = UDim2.fromOffset(240, 46), LayoutOrder = 7, Parent = content, OnClick = function()
		if not chosen.M or not chosen.F then
			return
		end
		local r = State.Request("Breed", { a = chosen.M.id, b = chosen.F.id })
		if r.ok then
			Windows.Breed()
		end
	end })
	refreshChoice()
end

---------------------------------------------------------------------------
-- Rooms
---------------------------------------------------------------------------

function Windows.Rooms()
	local _, content = UI.window("Rooms", "My Home", Vector2.new(760, 620))
	local p = State.Profile
	if not p then
		return
	end
	note(content, "Unlock rooms to make space for more pets, and give each room its own wallpaper and floor. Buy new styles in 🛍️ Shop → Styles.", 1)
	for order, def in Config.Rooms do
		local roomData = State.RoomData(def.Id)
		local f = card(content, order + 1)
		f.Size = UDim2.new(1, -10, 0, 0)
		f.AutomaticSize = Enum.AutomaticSize.Y
		UI.padding(10).Parent = f
		UI.list(Enum.FillDirection.Vertical, 6).Parent = f
		local header = UI.row(f, 36, 1)
		UI.title({ Text = (if roomData then "" else "🔒 ") .. def.Name, Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = header })
		if roomData then
			local n = petCount(def.Id)
			UI.label({ Text = string.format("%d/%d pets", n, def.Capacity), Position = UDim2.fromScale(0.45, 0), Size = UDim2.new(0.25, 0, 1, 0), TextSize = 15, Parent = header })
			UI.button({ Text = "Go there", Color = UI.Colors.Blue, Size = UDim2.fromOffset(120, 34), AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), TextSize = 15, Parent = header, OnClick = function()
				UI.CloseWindow()
				State.SetView(State.HomePlot(), order)
			end })
			if def.Outdoor then
				note(f, "An outdoor garden with room for " .. def.Capacity .. " pets.", 2)
			else
				for kindIndex, kind in { "Wallpaper", "Floor" } do
					local list = if kind == "Wallpaper" then Config.Wallpapers else Config.Floors
					local strip = UI.new("ScrollingFrame", {
						Size = UDim2.new(1, 0, 0, 74),
						BackgroundTransparency = 1,
						CanvasSize = UDim2.new(),
						AutomaticCanvasSize = Enum.AutomaticSize.X,
						ScrollingDirection = Enum.ScrollingDirection.X,
						ScrollBarThickness = 6,
						LayoutOrder = 1 + kindIndex,
						Parent = f,
					}, { UI.list(Enum.FillDirection.Horizontal, 6) })
					UI.label({ Text = kind, Size = UDim2.fromOffset(70, 60), TextSize = 14, Font = UI.Font, LayoutOrder = 0, Parent = strip })
					local currentId = if kind == "Wallpaper" then roomData.wallpaper else roomData.floor
					for i, style in list do
						if style.Id == "grass" or not ownsStyle(kind, style) then
							continue
						end
						local btn = UI.new("TextButton", { Size = UDim2.fromOffset(90, 60), Text = "", AutoButtonColor = true, BackgroundTransparency = 1, LayoutOrder = i, Parent = strip })
						local sw = styleSwatch(btn, style, kind)
						sw.Size = UDim2.fromScale(1, 1)
						sw.Active = false
						for _, d in sw:GetDescendants() do
							if d:IsA("GuiObject") then
								d.Active = false
							end
						end
						local st = sw:FindFirstChildOfClass("UIStroke")
						if st and style.Id == currentId then
							st.Color = UI.Colors.Pink
							st.Thickness = 5
						end
						UI.tooltip(btn, style.Name)
						btn.Activated:Connect(function()
							UI.Play("Click", 0.4)
							local r = State.Request("SetStyle", { roomId = def.Id, kind = kind, styleId = style.Id })
							if r.ok then
								State.SetView(State.HomePlot(), order)
								Windows.Rooms()
							end
						end)
					end
				end
			end
		else
			local nextRoom = nil
			for _, d in Config.Rooms do
				if not State.HasRoom(d.Id) then
					nextRoom = d
					break
				end
			end
			local isNext = nextRoom and nextRoom.Id == def.Id
			note(f, string.format("Room for %d more pets. Needs level %d and 🪙%d.%s", def.Capacity, def.Level, def.Price, if isNext then "" else " Unlock the rooms before it first."), 2)
			if isNext then
				local btn = UI.button({ Text = "🔓 Unlock (🪙" .. def.Price .. ")", Color = UI.Colors.Green, Size = UDim2.fromOffset(220, 40), TextSize = 16, LayoutOrder = 3, Parent = f, OnClick = function()
					UI.confirm("Unlock " .. def.Name .. "?", "This costs 🪙" .. def.Price .. ".", "Unlock!", function()
						local r = State.Request("UnlockRoom", { roomId = def.Id })
						if r.ok then
							UI.Play("Coin", 0.6)
							State.SetView(State.HomePlot(), order)
						end
					end)
				end })
				UI.SetEnabled(btn, p.level >= def.Level and p.coins >= def.Price)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Visit
---------------------------------------------------------------------------

function Windows.Visit()
	local _, content = UI.window("Visit", "Visit Neighbours", Vector2.new(560, 520))
	note(content, string.format("Visit other players' homes and pet their pets. Each pet you pet gives you 🪙%d (up to %d a day), and makes its owner's pet happier!", Config.Visit.Coins, Config.Visit.PerDay), 1)
	local plots = workspace:FindFirstChild("Plots")
	local any = false
	for i, plot in (if plots then plots:GetChildren() else {}) do
		if plot:GetAttribute("Owner") ~= player.UserId then
			any = true
			local f = card(content, i + 1)
			f.Size = UDim2.new(1, -10, 0, 56)
			local pets = plot:FindFirstChild("Pets")
			UI.title({ Text = "🏡 " .. tostring(plot:GetAttribute("OwnerName")), Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.6, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = f })
			UI.label({ Text = (if pets then #pets:GetChildren() else 0) .. " pets", Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.2, 0, 1, 0), TextSize = 15, Parent = f })
			UI.button({ Text = "Visit", Color = UI.Colors.Green, Size = UDim2.fromOffset(110, 40), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Parent = f, OnClick = function()
				UI.CloseWindow()
				State.SetView(plot :: Model, 1)
			end })
		end
	end
	if not any then
		note(content, "Nobody else is here right now. Invite a friend to visit your pets!", 2)
	end
	if State.IsVisiting() then
		UI.button({ Text = "🏠 Go home", Color = UI.Colors.Pink, Size = UDim2.fromOffset(180, 42), LayoutOrder = 99, Parent = content, OnClick = function()
			UI.CloseWindow()
			State.SetView(State.HomePlot(), 1)
		end })
	end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

function Windows.Settings()
	local _, content = UI.window("Settings", "Settings", Vector2.new(520, 560))
	local p = State.Profile
	local soundOn = not p or p.settings.sound ~= false
	local soundButton: TextButton
	soundButton = UI.button({ Text = if soundOn then "🔊 Sound: On" else "🔈 Sound: Off", Color = UI.Colors.Blue, Size = UDim2.fromOffset(220, 44), LayoutOrder = 1, Parent = content, OnClick = function()
		soundOn = not soundOn
		UI.SoundOn = soundOn
		soundButton.Text = if soundOn then "🔊 Sound: On" else "🔈 Sound: Off"
		State.Request("SetSetting", { key = "sound", value = soundOn })
	end })

	UI.title({ Text = "How to play", Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 2, Parent = content })
	note(content, table.concat({
		"• Click a pet to see its needs and care for it.",
		"• Keep Food, Fun, Energy and Clean up and Health follows.",
		"• Happy pets leave 🪙 gifts. Click them to collect!",
		"• Toys let pets play; beds help them sleep faster; decorations keep them happy longer.",
		"• ◀ ▶ switch rooms. Mouse wheel zooms. Right-drag or Q/E turns the view.",
		"• In Decorate mode click furniture to move it. R rotates.",
	}, "\n"), 3)

	if p then
		UI.title({ Text = "Your stats", Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 4, Parent = content })
		note(content, string.format("Care actions: %d · Pets adopted: %d · Babies: %d · Gifts: %d", p.stats.care, p.stats.adopted, p.stats.bred, p.stats.gifts), 5)
	end
	local status = player:GetAttribute("SaveStatus")
	note(content, if status == "Offline" then "⚠ Saving is unavailable on this server (DataStores are off), so progress won't be kept." else "💾 Your home saves automatically every minute and when you leave.", 6)

	UI.button({ Text = "Reset save…", Color = UI.Colors.Red, Size = UDim2.fromOffset(200, 40), TextSize = 16, LayoutOrder = 7, Parent = content, OnClick = function()
		UI.confirm("Reset everything?", "This deletes ALL your pets, coins, furniture and levels and starts over. This can't be undone!", "Yes, reset", function()
			UI.confirm("Are you really sure?", "Last chance! Every pet will be gone.", "Reset forever", function()
				local r = State.Request("ResetSave", { confirm = "RESET" })
				if r.ok then
					Windows.Toast("Your save was reset. Welcome back!")
				end
			end)
		end)
	end })
end

return Windows
