-- The always-on interface: status bar (level, XP, coins, daily bonus, save
-- state), the navigation bar, the room switcher, the "visiting" banner,
-- toasts, floating rewards and the level-up celebration.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local State = require(script.Parent:WaitForChild("State"))
local UI = require(script.Parent:WaitForChild("UI"))

local player = Players.LocalPlayer

local Hud = {}

local screen: ScreenGui
local toastHolder: Frame
local navButtons: { [string]: TextButton } = {}
local navBadges: { [string]: TextLabel } = {}
local roomLabel: TextLabel
local visitBanner: Frame
local visitLabel: TextLabel
local roomBar: Frame

export type NavHandler = (string) -> ()

local NAV = {
	{ id = "Adopt", icon = "🐾", label = "Adopt", color = UI.Colors.Pink, tip = "Adopt a new pet" },
	{ id = "Pets", icon = "📖", label = "My Pets", color = UI.Colors.Purple, tip = "Your pet collection" },
	{ id = "Shop", icon = "🛍️", label = "Shop", color = UI.Colors.Orange, tip = "Buy food, toys and furniture" },
	{ id = "Items", icon = "🎒", label = "Items", color = UI.Colors.Blue, tip = "Your inventory" },
	{ id = "Decorate", icon = "🛋️", label = "Decorate", color = UI.Colors.Green, tip = "Move and place furniture" },
	{ id = "Breed", icon = "💞", label = "Breed", color = Color3.fromRGB(240, 100, 130), tip = "Have baby pets" },
	{ id = "Rooms", icon = "🏠", label = "Rooms", color = Color3.fromRGB(120, 180, 200), tip = "Unlock rooms, wallpaper and floors" },
	{ id = "Visit", icon = "👋", label = "Visit", color = Color3.fromRGB(110, 170, 150), tip = "Visit other players' pets" },
	{ id = "Settings", icon = "⚙️", label = "Settings", color = UI.Colors.Gray, tip = "Sound and save options" },
}

function Hud.Toast(text: string, color: Color3?)
	local toast = UI.new("Frame", {
		Size = UDim2.fromOffset(420, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = color or UI.Colors.Cream,
		Parent = toastHolder,
	}, { UI.corner(14), UI.stroke(UI.Colors.Edge, 3), UI.padding(10) })
	local label = UI.label({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		Font = UI.Font,
		TextSize = 18,
		TextColor3 = if color then UI.Colors.White else UI.Colors.Ink,
		Parent = toast,
	})
	if color then
		UI.textStroke(color:Lerp(Color3.new(0, 0, 0), 0.4), 1.5).Parent = label
	end
	task.delay(3.2, function()
		local info = TweenInfo.new(0.4)
		TweenService:Create(toast, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		local stroke = toast:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		end
		task.wait(0.45)
		toast:Destroy()
	end)
	-- Keep at most four.
	local list = {}
	for _, c in toastHolder:GetChildren() do
		if c:IsA("Frame") then
			table.insert(list, c)
		end
	end
	if #list > 4 then
		list[1]:Destroy()
	end
end

function Hud.Error(text: string)
	UI.Play("Pop", 0.4)
	Hud.Toast(text, Color3.fromRGB(232, 110, 110))
end

-- "+5 XP  +2 🪙" rising from a point on screen (or the screen centre).
function Hud.FloatReward(worldPos: Vector3?, xp: number, coins: number)
	local parts = {}
	if xp > 0 then
		table.insert(parts, "+" .. xp .. " XP")
	end
	if coins > 0 then
		table.insert(parts, "+" .. coins .. " 🪙")
	end
	if #parts == 0 then
		return
	end
	local scale = UI.UIScale()
	local camera = workspace.CurrentCamera
	local pos = camera.ViewportSize / 2
	if worldPos then
		local p, onScreen = camera:WorldToViewportPoint(worldPos)
		if onScreen then
			pos = Vector2.new(p.X, p.Y)
		end
	end
	local label = UI.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(pos.X / scale, pos.Y / scale),
		Size = UDim2.fromOffset(220, 34),
		Text = table.concat(parts, "   "),
		Font = UI.Font,
		TextSize = 26,
		TextColor3 = if coins > 0 then UI.Colors.Yellow else Color3.fromRGB(140, 230, 120),
		ZIndex = 15,
		Parent = screen,
	})
	UI.textStroke(UI.Colors.Ink, 2.5).Parent = label
	local info = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(label, info, { Position = label.Position - UDim2.fromOffset(0, 70) }):Play()
	task.delay(0.8, function()
		TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
	end)
	task.delay(1.5, function()
		label:Destroy()
	end)
	if coins > 0 then
		UI.Play("Coin", 0.35)
	end
end

function Hud.LevelUp(level: number, coins: number, unlocks: { string })
	UI.Play("Coin", 0.6)
	local holder = UI.new("Frame", {
		Name = "LevelUp",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
		Active = true,
		Parent = screen,
	})
	local card = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = UI.Colors.Cream,
		Parent = holder,
	}, { UI.corner(20), UI.stroke(UI.Colors.Yellow, 5), UI.padding(18), UI.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center) })
	local big = UI.title({ Text = "⭐ Level " .. level .. "! ⭐", Size = UDim2.new(1, 0, 0, 44), TextSize = 36, TextColor3 = UI.Colors.Yellow, LayoutOrder = 1, Parent = card })
	UI.textStroke(Color3.fromRGB(170, 110, 30), 2.5).Parent = big
	UI.label({ Text = "You earned " .. coins .. " 🪙", Size = UDim2.new(1, 0, 0, 26), TextSize = 20, Font = UI.Font, LayoutOrder = 2, Parent = card })
	if #unlocks > 0 then
		UI.label({ Text = "New things unlocked:", Size = UDim2.new(1, 0, 0, 22), TextSize = 16, TextColor3 = UI.Colors.Soft, LayoutOrder = 3, Parent = card })
		UI.label({
			Text = table.concat(unlocks, " · "),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 17,
			LayoutOrder = 4,
			Parent = card,
		})
	end
	UI.button({
		Text = "Hooray!",
		Color = UI.Colors.Green,
		Size = UDim2.fromOffset(160, 46),
		LayoutOrder = 5,
		Parent = card,
		OnClick = function()
			holder:Destroy()
		end,
	})
	local s = UI.new("UIScale", { Scale = 0.6, Parent = card })
	TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

function Hud.SetBadge(id: string, text: string?)
	local badge = navBadges[id]
	if badge then
		badge.Visible = text ~= nil
		badge.Text = text or ""
	end
end

function Hud.NavButton(id: string): TextButton?
	return navButtons[id]
end

local function buildStatusBar(onDaily: () -> ())
	local bar = UI.new("Frame", {
		Name = "StatusBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(0, 52),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = UI.Colors.Cream,
		Parent = screen,
	}, { UI.corner(18), UI.stroke(UI.Colors.Edge, 3), UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center), UI.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })

	local star = UI.new("Frame", { Size = UDim2.fromOffset(44, 44), BackgroundColor3 = UI.Colors.Yellow, LayoutOrder = 1, Parent = bar }, { UI.corner(22), UI.stroke(Color3.fromRGB(200, 140, 30), 3) })
	local levelText = UI.title({ Size = UDim2.fromScale(1, 1), Text = "1", TextSize = 22, TextColor3 = UI.Colors.White, Parent = star })
	UI.textStroke(Color3.fromRGB(170, 110, 30), 2).Parent = levelText
	UI.tooltip(star, "Your level")

	local xpBack, setXP = UI.bar({ Size = UDim2.fromOffset(180, 22), LayoutOrder = 2, Parent = bar, TextSize = 14 }, Color3.fromRGB(130, 210, 110))
	UI.tooltip(xpBack, function()
		local p = State.Profile
		return if p then string.format("%d / %d XP to level %d", p.xp, p.xpNext, p.level + 1) else ""
	end)

	local coinPill = UI.new("Frame", { Size = UDim2.fromOffset(130, 36), BackgroundColor3 = Color3.fromRGB(255, 236, 170), LayoutOrder = 3, Parent = bar }, { UI.corner(18), UI.stroke(Color3.fromRGB(220, 170, 60), 3) })
	local coinText = UI.title({ Size = UDim2.fromScale(1, 1), Text = "🪙 0", TextSize = 20, TextColor3 = UI.Colors.Ink, Parent = coinPill })
	UI.tooltip(coinPill, "Coins: earn them by caring for pets and collecting gifts")

	local daily = UI.button({ Text = "🎁 Daily", Color = UI.Colors.Purple, Size = UDim2.fromOffset(100, 38), TextSize = 16, LayoutOrder = 4, Parent = bar, OnClick = onDaily, Tooltip = "Collect your daily bonus" })

	local saveText = UI.label({ Size = UDim2.fromOffset(92, 36), Text = "…", TextSize = 13, TextColor3 = UI.Colors.Soft, LayoutOrder = 5, Parent = bar })
	UI.tooltip(saveText, function()
		local status = player:GetAttribute("SaveStatus")
		if status == "Offline" then
			return "DataStores aren't available here, so progress won't be kept."
		end
		return "Your home saves automatically."
	end)

	local function refresh()
		local p = State.Profile
		if not p then
			return
		end
		levelText.Text = tostring(p.level)
		setXP(if p.xpNext > 0 then p.xp / p.xpNext else 1, string.format("%d / %d XP", p.xp, p.xpNext))
		local function commas(n: number): string
			local s = tostring(math.floor(n))
			local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
			return (string.gsub(out, "^,", ""))
		end
		coinText.Text = "🪙 " .. commas(p.coins)
		daily.Visible = p.dailyReady == true
	end
	State.ProfileChanged:Connect(refresh)
	refresh()

	local function refreshSave()
		local status = player:GetAttribute("SaveStatus")
		local text = {
			Loading = "⏳ Loading",
			Saving = "💾 Saving…",
			Saved = "✓ Saved",
			Offline = "⚠ Not saving",
			Error = "⚠ Save failed",
		}
		saveText.Text = text[status] or ""
		saveText.TextColor3 = if status == "Offline" or status == "Error" then UI.Colors.Red else UI.Colors.Soft
	end
	player:GetAttributeChangedSignal("SaveStatus"):Connect(refreshSave)
	refreshSave()
end

local function buildNav(onNav: NavHandler)
	local nav = UI.new("Frame", {
		Name = "Nav",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(0, 74),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = UI.Colors.Cream,
		Parent = screen,
	}, { UI.corner(20), UI.stroke(UI.Colors.Edge, 3), UI.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center), UI.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
	for i, item in NAV do
		local btn = UI.button({
			Name = item.id,
			Text = "",
			Color = item.color,
			Size = UDim2.fromOffset(72, 62),
			LayoutOrder = i,
			Parent = nav,
			Tooltip = item.tip,
			OnClick = function()
				onNav(item.id)
			end,
		})
		UI.label({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 2), Text = item.icon, TextSize = 26, Parent = btn })
		local label = UI.label({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -22), Text = item.label, Font = UI.Font, TextSize = 14, TextColor3 = UI.Colors.White, Parent = btn })
		UI.textStroke(item.color:Lerp(Color3.new(0, 0, 0), 0.45), 1.5).Parent = label
		local badge = UI.label({
			Name = "Badge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.fromOffset(24, 24),
			BackgroundTransparency = 0,
			BackgroundColor3 = UI.Colors.Red,
			Text = "!",
			Font = UI.Font,
			TextSize = 15,
			TextColor3 = UI.Colors.White,
			Visible = false,
			ZIndex = 3,
			Parent = btn,
		})
		UI.corner(12).Parent = badge
		UI.stroke(UI.Colors.White, 2).Parent = badge
		navButtons[item.id] = btn
		navBadges[item.id] = badge
	end
	return nav
end

local function buildRoomBar()
	roomBar = UI.new("Frame", {
		Name = "RoomBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -92),
		Size = UDim2.fromOffset(360, 44),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	UI.button({
		Text = "◀",
		Color = UI.Colors.Blue,
		Size = UDim2.fromOffset(48, 42),
		Parent = roomBar,
		Tooltip = "Previous room",
		OnClick = function()
			State.SetRoom(State.RoomIndex - 1)
		end,
	})
	UI.button({
		Text = "▶",
		Color = UI.Colors.Blue,
		Size = UDim2.fromOffset(48, 42),
		Position = UDim2.new(1, -48, 0, 0),
		Parent = roomBar,
		Tooltip = "Next room",
		OnClick = function()
			State.SetRoom(State.RoomIndex + 1)
		end,
	})
	local plate = UI.new("Frame", { Position = UDim2.fromOffset(56, 2), Size = UDim2.new(1, -112, 1, -4), BackgroundColor3 = UI.Colors.Cream, Parent = roomBar }, { UI.corner(14), UI.stroke(UI.Colors.Edge, 3) })
	roomLabel = UI.title({ Size = UDim2.fromScale(1, 1), TextSize = 18, Text = "", Parent = plate })

	local function refresh()
		local def = Config.Rooms[State.RoomIndex]
		local plot = State.ViewPlot
		local text = def.Name
		if plot and not State.IsVisiting() and State.Profile then
			if State.HasRoom(def.Id) then
				local n = 0
				for _, pet in State.Profile.pets do
					if pet.room == def.Id then
						n += 1
					end
				end
				text = string.format("%s  (%d/%d 🐾)", def.Name, n, def.Capacity)
			else
				text = "🔒 " .. def.Name
			end
		end
		roomLabel.Text = text
	end
	State.RoomChanged:Connect(refresh)
	State.ProfileChanged:Connect(refresh)
	refresh()
end

local function buildVisitBanner()
	visitBanner = UI.new("Frame", {
		Name = "VisitBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(440, 46),
		BackgroundColor3 = Color3.fromRGB(110, 170, 150),
		Visible = false,
		Parent = screen,
	}, { UI.corner(14), UI.stroke(Color3.fromRGB(70, 120, 100), 3) })
	visitLabel = UI.title({ Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -150, 1, 0), TextSize = 18, TextColor3 = UI.Colors.White, TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = visitBanner })
	UI.textStroke(Color3.fromRGB(60, 100, 90), 1.5).Parent = visitLabel
	UI.button({
		Text = "🏠 Go home",
		Color = UI.Colors.Pink,
		Size = UDim2.fromOffset(126, 36),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		TextSize = 16,
		Parent = visitBanner,
		OnClick = function()
			State.SetView(State.HomePlot(), 1)
		end,
	})
	State.RoomChanged:Connect(function()
		local visiting = State.IsVisiting()
		visitBanner.Visible = visiting
		if visiting and State.ViewPlot then
			visitLabel.Text = "Visiting " .. tostring(State.ViewPlot:GetAttribute("OwnerName")) .. "'s home"
		end
	end)
end

function Hud.SetVisible(visible: boolean)
	for _, name in { "StatusBar", "Nav", "RoomBar" } do
		local f = screen:FindFirstChild(name)
		if f then
			(f :: GuiObject).Visible = visible
		end
	end
end

function Hud.Init(onNav: NavHandler, onDaily: () -> ())
	screen = UI.Screen()
	toastHolder = UI.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 124),
		Size = UDim2.fromOffset(420, 300),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = screen,
	}, { UI.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center) })
	buildStatusBar(onDaily)
	buildNav(onNav)
	buildRoomBar()
	buildVisitBanner()

	State.OnError = Hud.Error
	State.ProfileChanged:Connect(function(p)
		local readyBirths = 0
		local t = workspace:GetServerTimeNow()
		for _, b in p.births do
			if b.readyAt <= t then
				readyBirths += 1
			end
		end
		Hud.SetBadge("Breed", if readyBirths > 0 then tostring(readyBirths) else nil)
		Hud.SetBadge("Adopt", if not p.starterDone then "!" else nil)
		UI.SoundOn = p.settings and p.settings.sound ~= false
	end)
end

return Hud
