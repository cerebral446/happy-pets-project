-- UI toolkit: the cosy late-2000s browser-game look (cream panels, glossy
-- rounded buttons, chunky outlines), plus windows, bars, tooltips and sounds.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer

local UI = {}

local rgb = Color3.fromRGB
UI.Colors = {
	Cream = rgb(255, 249, 236),
	Panel = rgb(255, 244, 222),
	Edge = rgb(196, 140, 120),
	Ink = rgb(92, 64, 70),
	Soft = rgb(150, 120, 120),
	Pink = rgb(246, 120, 166),
	Blue = rgb(92, 168, 240),
	Green = rgb(110, 196, 110),
	Yellow = rgb(250, 196, 60),
	Purple = rgb(170, 130, 230),
	Orange = rgb(250, 150, 70),
	Gray = rgb(186, 180, 186),
	Red = rgb(232, 90, 90),
	White = rgb(255, 255, 255),
}
UI.Font = Enum.Font.FredokaOne
UI.BodyFont = Enum.Font.GothamMedium

function UI.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UI.corner(radius: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function UI.stroke(color: Color3?, thickness: number?): UIStroke
	return UI.new("UIStroke", { Color = color or UI.Colors.Edge, Thickness = thickness or 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

function UI.textStroke(color: Color3?, thickness: number?): UIStroke
	return UI.new("UIStroke", { Color = color or UI.Colors.Ink, Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
end

function UI.padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return UI.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function UI.list(direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return UI.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 6),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UI.grid(cell: UDim2, padding: number?): UIGridLayout
	return UI.new("UIGridLayout", {
		CellSize = cell,
		CellPadding = UDim2.fromOffset(padding or 8, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UI.label(props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = UI.BodyFont,
		TextColor3 = UI.Colors.Ink,
		TextSize = 16,
		TextWrapped = true,
	}
	for k, v in props do
		base[k] = v
	end
	return UI.new("TextLabel", base)
end

function UI.title(props: { [string]: any }): TextLabel
	props.Font = props.Font or UI.Font
	props.TextSize = props.TextSize or 22
	return UI.label(props)
end

---------------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------------

local SOUNDS = {
	Click = "rbxasset://sounds/button.wav",
	Coin = "rbxasset://sounds/electronicpingshort.wav",
	Pop = "rbxasset://sounds/clickfast.wav",
	Whoosh = "rbxasset://sounds/swoosh.wav",
}
UI.SoundOn = true
local soundCache: { [string]: Sound } = {}

function UI.Play(name: string, volume: number?)
	if not UI.SoundOn then
		return
	end
	local s = soundCache[name]
	if not s then
		local id = SOUNDS[name]
		if not id then
			return
		end
		s = UI.new("Sound", { SoundId = id, Volume = volume or 0.5, Parent = SoundService })
		soundCache[name] = s
	end
	(s :: Sound).PlaybackSpeed = 0.95 + math.random() * 0.1
	SoundService:PlayLocalSound(s :: Sound)
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

export type ButtonProps = {
	Text: string,
	Color: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	TextSize: number?,
	LayoutOrder: number?,
	OnClick: (() -> ())?,
	Tooltip: string?,
	Name: string?,
}

-- Glossy rounded button. Call UI.SetEnabled to grey it out.
function UI.button(props: ButtonProps): TextButton
	local color = props.Color or UI.Colors.Pink
	local btn = UI.new("TextButton", {
		Name = props.Name or "Button",
		Text = props.Text,
		Font = UI.Font,
		TextSize = props.TextSize or 18,
		TextColor3 = UI.Colors.White,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Size = props.Size or UDim2.fromOffset(120, 40),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		TextWrapped = true,
	}, {
		UI.corner(12),
		UI.stroke(color:Lerp(Color3.new(0, 0, 0), 0.3), 3),
		UI.textStroke(color:Lerp(Color3.new(0, 0, 0), 0.45), 1.5),
		UI.new("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205)),
			Rotation = 90,
		}),
		UI.new("UIScale", { Scale = 1 }),
	})
	btn:SetAttribute("BaseColor", color)
	btn:SetAttribute("Enabled", true)
	local scale = btn:FindFirstChildOfClass("UIScale") :: UIScale
	local function tween(target: number)
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = target }):Play()
	end
	btn.MouseEnter:Connect(function()
		if btn:GetAttribute("Enabled") then
			tween(1.05)
		end
	end)
	btn.MouseLeave:Connect(function()
		tween(1)
	end)
	btn.MouseButton1Down:Connect(function()
		if btn:GetAttribute("Enabled") then
			tween(0.94)
		end
	end)
	btn.MouseButton1Up:Connect(function()
		tween(1)
	end)
	if props.OnClick then
		local onClick = props.OnClick
		btn.Activated:Connect(function()
			if btn:GetAttribute("Enabled") then
				UI.Play("Click", 0.4)
				onClick()
			end
		end)
	end
	if props.Tooltip then
		UI.tooltip(btn, props.Tooltip)
	end
	if props.Parent then
		btn.Parent = props.Parent
	end
	return btn
end

function UI.SetEnabled(btn: GuiButton, enabled: boolean)
	btn:SetAttribute("Enabled", enabled)
	local base = btn:GetAttribute("BaseColor") :: Color3
	btn.BackgroundColor3 = if enabled then base else UI.Colors.Gray
	local stroke = btn:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = (if enabled then base else UI.Colors.Gray):Lerp(Color3.new(0, 0, 0), 0.3)
	end
end

---------------------------------------------------------------------------
-- Screen, tooltips and bars
---------------------------------------------------------------------------

local screen: ScreenGui
local tooltipLabel: TextLabel
local tooltipOwner: GuiObject? = nil

function UI.Screen(): ScreenGui
	return screen
end

function UI.Init()
	screen = UI.new("ScreenGui", {
		Name = "HappyPetsUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	-- Scale everything with the window so phones and big monitors both work.
	local uiScale = UI.new("UIScale", { Parent = screen })
	local camera = workspace.CurrentCamera
	local function rescale()
		local size = camera.ViewportSize
		uiScale.Scale = math.clamp(math.min(size.X / 1100, size.Y / 720), 0.55, 1.25)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	tooltipLabel = UI.label({
		Name = "Tooltip",
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 0,
		BackgroundColor3 = UI.Colors.Ink,
		TextColor3 = UI.Colors.White,
		TextSize = 14,
		TextWrapped = false,
		Visible = false,
		ZIndex = 100,
		Parent = screen,
	})
	UI.corner(6).Parent = tooltipLabel
	UI.padding(6).Parent = tooltipLabel
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement and tooltipLabel.Visible then
			local scale = uiScale.Scale
			local pos = UserInputService:GetMouseLocation()
			tooltipLabel.Position = UDim2.fromOffset((pos.X + 14) / scale, (pos.Y + 4) / scale)
		end
	end)
end

function UI.UIScale(): number
	local s = screen:FindFirstChildOfClass("UIScale")
	return if s then s.Scale else 1
end

function UI.tooltip(gui: GuiObject, text: string | () -> string)
	gui.MouseEnter:Connect(function()
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			return
		end
		tooltipOwner = gui
		tooltipLabel.Text = if typeof(text) == "function" then text() else text
		local pos = UserInputService:GetMouseLocation()
		local scale = UI.UIScale()
		tooltipLabel.Position = UDim2.fromOffset((pos.X + 14) / scale, (pos.Y + 4) / scale)
		tooltipLabel.Visible = tooltipLabel.Text ~= ""
	end)
	gui.MouseLeave:Connect(function()
		if tooltipOwner == gui then
			tooltipLabel.Visible = false
		end
	end)
	gui.AncestryChanged:Connect(function()
		if not gui:IsDescendantOf(game) and tooltipOwner == gui then
			tooltipLabel.Visible = false
		end
	end)
end

-- A rounded progress bar. Returns the frame and a setter (fraction 0..1, text).
function UI.bar(props: { [string]: any }, color: Color3): (Frame, (number, string?) -> ())
	local back = UI.new("Frame", {
		BackgroundColor3 = rgb(236, 222, 210),
		Size = props.Size or UDim2.fromOffset(160, 16),
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { UI.corner(8), UI.stroke(UI.Colors.Edge, 2) })
	local fill = UI.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		Size = UDim2.fromScale(0.5, 1),
		Parent = back,
	}, {
		UI.corner(8),
		UI.new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215)), Rotation = 90 }),
	})
	local text = UI.label({
		Size = UDim2.fromScale(1, 1),
		Font = UI.Font,
		TextSize = props.TextSize or 13,
		TextColor3 = UI.Colors.White,
		ZIndex = 2,
		Parent = back,
	})
	UI.textStroke(UI.Colors.Ink, 1.5).Parent = text
	local function set(fraction: number, label: string?)
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		fill.Visible = fraction > 0.01
		text.Text = label or ""
	end
	return back, set
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------

local openWindow: Frame? = nil
local openName: string? = nil
local closeHandlers: { [Frame]: () -> () } = {}
UI.WindowChanged = nil :: any

function UI.CloseWindow()
	local w = openWindow
	if w then
		openWindow = nil
		openName = nil
		local onClose = closeHandlers[w]
		closeHandlers[w] = nil
		w.Parent:Destroy()
		if onClose then
			onClose()
		end
	end
end

function UI.OpenWindowName(): string?
	return openName
end

-- Opens a modal window (closing any other). Returns the window frame and a
-- scrolling content frame with a vertical list layout.
function UI.window(name: string, title: string, size: Vector2, onClose: (() -> ())?): (Frame, ScrollingFrame)
	UI.CloseWindow()
	-- A full-screen holder above the HUD: a dimmed backdrop that closes the
	-- window when clicked, with the window itself on top.
	local overlay = UI.new("Frame", {
		Name = "Overlay_" .. name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = screen,
	})
	local backdrop = UI.new("TextButton", {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = overlay,
	})
	backdrop.Activated:Connect(function()
		UI.CloseWindow()
	end)
	local scale = UI.UIScale()
	local view = workspace.CurrentCamera.ViewportSize / scale
	local w = math.min(size.X, view.X - 24)
	local h = math.min(size.Y, view.Y - 90)
	local frame = UI.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = UI.Colors.Cream,
		ZIndex = 2,
		Active = true,
		Parent = overlay,
	}, { UI.corner(18), UI.stroke(UI.Colors.Edge, 4) })
	-- Title ribbon.
	local ribbon = UI.new("Frame", {
		Name = "Ribbon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(math.min(w - 40, 320), 44),
		BackgroundColor3 = UI.Colors.Pink,
		ZIndex = 3,
		Parent = frame,
	}, {
		UI.corner(14),
		UI.stroke(rgb(200, 80, 120), 3),
		UI.new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215)), Rotation = 90 }),
	})
	local titleLabel = UI.title({ Text = title, Size = UDim2.fromScale(1, 1), TextColor3 = UI.Colors.White, TextSize = 24, Parent = ribbon })
	UI.textStroke(rgb(170, 60, 100), 2).Parent = titleLabel
	local close = UI.button({
		Name = "Close",
		Text = "✕",
		Color = UI.Colors.Red,
		Size = UDim2.fromOffset(38, 38),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -8, 0, 8),
		TextSize = 20,
		Parent = frame,
		OnClick = UI.CloseWindow,
	})
	close.ZIndex = 4
	local content = UI.new("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(14, 34),
		Size = UDim2.new(1, -28, 1, -46),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = UI.Colors.Edge,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = frame,
	}, { UI.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center), UI.new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingRight = UDim.new(0, 8) }) })
	openWindow = frame
	openName = name
	if onClose then
		closeHandlers[frame] = onClose
	end
	local s = UI.new("UIScale", { Scale = 0.85, Parent = frame })
	TweenService:Create(s, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	UI.Play("Pop", 0.3)
	return frame, content
end

-- A row frame for window content.
function UI.row(parent: Instance, height: number, order: number?): Frame
	return UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = order or 0,
		Parent = parent,
	})
end

-- A row of tab buttons. onSelect(tabName) is called on click; returns a
-- function that highlights the given tab.
function UI.tabs(parent: Instance, names: { string }, onSelect: (string) -> (), order: number?): (string) -> ()
	local row = UI.row(parent, 40, order)
	UI.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center).Parent = row
	local buttons = {}
	local function highlight(name: string)
		for n, b in buttons do
			local active = n == name
			b.BackgroundColor3 = if active then UI.Colors.Pink else UI.Colors.Blue
			b:SetAttribute("BaseColor", b.BackgroundColor3)
			local stroke = b:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Thickness = if active then 4 else 3
			end
		end
	end
	local width = math.clamp(math.floor(560 / #names) - 6, 70, 110)
	for i, n in names do
		buttons[n] = UI.button({
			Text = n,
			Color = UI.Colors.Blue,
			Size = UDim2.fromOffset(width, 36),
			TextSize = 16,
			LayoutOrder = i,
			Parent = row,
			OnClick = function()
				highlight(n)
				onSelect(n)
			end,
		})
	end
	return highlight
end

-- Simple "are you sure?" dialog.
function UI.confirm(title: string, message: string, yesText: string, onYes: () -> ())
	local _, content = UI.window("Confirm", title, Vector2.new(420, 250))
	UI.label({ Text = message, Size = UDim2.new(1, 0, 0, 80), TextSize = 18, LayoutOrder = 1, Parent = content })
	local row = UI.row(content, 48, 2)
	UI.list(Enum.FillDirection.Horizontal, 16, Enum.HorizontalAlignment.Center).Parent = row
	UI.button({ Text = "Cancel", Color = UI.Colors.Gray, Size = UDim2.fromOffset(130, 44), LayoutOrder = 1, Parent = row, OnClick = UI.CloseWindow })
	UI.button({
		Text = yesText,
		Color = UI.Colors.Green,
		Size = UDim2.fromOffset(150, 44),
		LayoutOrder = 2,
		Parent = row,
		OnClick = function()
			UI.CloseWindow()
			onYes()
		end,
	})
end

-- Lets windows know if the player is on a touch screen.
function UI.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

function UI.Inset(): number
	return GuiService:GetGuiInset().Y
end

return UI
