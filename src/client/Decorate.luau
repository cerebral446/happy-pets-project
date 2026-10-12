-- Decorate mode: pick up furniture, slide a see-through preview around the
-- room's floor grid (green = fits, red = blocked), rotate it, then place it,
-- put it back in the inventory, or cancel. New items from the inventory are
-- placed the same way. The server re-checks every placement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Placement = require(Shared:WaitForChild("Placement"))
local FurnitureModels = require(Shared:WaitForChild("FurnitureModels"))
local State = require(script.Parent:WaitForChild("State"))
local UI = require(script.Parent:WaitForChild("UI"))

local Decorate = {}

-- Set by the client.
Decorate.OpenItems = function() end
Decorate.Toast = function(_text: string) end

local camera = workspace.CurrentCamera

local toolbar: Frame
local hint: TextLabel
local carryButtons: { [string]: TextButton } = {}
local idleButtons: { [string]: TextButton } = {}
local hoverBox: SelectionBox

type Carry = {
	itemId: string,
	uid: string?, -- nil for a new item from the inventory
	original: Model?,
	ghost: Model,
	tint: Highlight,
	rot: number,
	cx: number,
	cz: number,
	valid: boolean,
}
local carry: Carry? = nil
local pointer: Vector2? = nil -- last pointer position (viewport space)

local function roomFurnitureData(): { any }
	local room = State.RoomData(State.RoomId())
	return if room then room.furniture else {}
end

local function roomCF(): CFrame
	return State.RoomCFrame(State.ViewPlot, State.RoomIndex)
end

local function setHidden(model: Model?, hidden: boolean)
	if not model then
		return
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function refreshToolbar()
	local carrying = carry ~= nil
	for _, b in carryButtons do
		b.Visible = carrying
	end
	for _, b in idleButtons do
		b.Visible = not carrying
	end
	if carry then
		local item = Config.Items[carry.itemId]
		hint.Text = if UI.IsTouch() then "Tap the floor to move the " .. item.Name .. ", then press Place." else "Move the " .. item.Name .. " and click to place it. R rotates."
	else
		hint.Text = if UI.IsTouch() then "Tap furniture to move it." else "Click furniture to move it, or place something from your items."
	end
end

-- Moves the preview to the cell under a viewport point.
local function moveGhost(point: Vector2?)
	local c = carry
	if not c then
		return
	end
	if point then
		local ray = camera:ViewportPointToRay(point.X, point.Y)
		local floorY = roomCF().Position.Y
		if math.abs(ray.Direction.Y) > 1e-4 then
			local t = (floorY - ray.Origin.Y) / ray.Direction.Y
			if t > 0 then
				local hit = ray.Origin + ray.Direction * t
				local localPos = roomCF():PointToObjectSpace(hit)
				c.cx, c.cz = Placement.LocalToCell(c.itemId, localPos.X, localPos.Z, c.rot)
			end
		end
	end
	local w, d = Placement.Footprint(c.itemId, c.rot)
	c.cx = math.clamp(c.cx, 0, Placement.Cols - w)
	c.cz = math.clamp(c.cz, 0, Placement.Rows - d)
	c.ghost:PivotTo(FurnitureModels.PlacementCFrame(roomCF(), c.itemId, c.cx, c.cz, c.rot, Placement))
	c.valid = (Placement.Validate(roomFurnitureData(), c.itemId, c.cx, c.cz, c.rot, c.uid))
	c.tint.FillColor = if c.valid then Color3.fromRGB(110, 230, 110) else Color3.fromRGB(240, 80, 80)
	c.tint.OutlineColor = c.tint.FillColor
	if carryButtons.Place then
		UI.SetEnabled(carryButtons.Place, c.valid)
	end
end

local function makeGhost(itemId: string): (Model, Highlight)
	local ghost = FurnitureModels.Create(itemId)
	ghost.Name = "PlacementGhost"
	for _, p in ghost:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanQuery = false
			p.Transparency = math.max(p.Transparency, 0.35)
		elseif p:IsA("Light") then
			p.Enabled = false
		end
	end
	ghost.Parent = workspace
	local tint = UI.new("Highlight", { FillTransparency = 0.55, OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Adornee = ghost, Parent = ghost })
	return ghost, tint
end

local function stopCarry()
	local c = carry
	if c then
		carry = nil
		c.ghost:Destroy()
		setHidden(c.original, false)
	end
	refreshToolbar()
end

local function beginCarry(itemId: string, uid: string?, original: Model?, cx: number?, cz: number?, rot: number?)
	stopCarry()
	local ghost, tint = makeGhost(itemId)
	carry = { itemId = itemId, uid = uid, original = original, ghost = ghost, tint = tint, rot = rot or 0, cx = cx or 0, cz = cz or 0, valid = false }
	setHidden(original, true)
	if not cx then
		-- New item: start in the first free spot, or the middle.
		local fx, fz, frot = Placement.FindFreeSpot(roomFurnitureData(), itemId)
		local c = carry :: Carry
		if fx then
			c.cx, c.cz, c.rot = fx, fz :: number, frot :: number
		else
			c.cx, c.cz = Placement.Cols // 2, Placement.Rows // 2
		end
	end
	moveGhost(nil)
	refreshToolbar()
end

local function rotate()
	local c = carry
	if c then
		c.rot = (c.rot + 1) % 4
		moveGhost(nil)
	end
end

local function confirm()
	local c = carry
	if not c then
		return
	end
	if not c.valid then
		Decorate.Toast("That spot is blocked. Try somewhere else!")
		return
	end
	local result
	if c.uid then
		result = State.Request("MoveFurniture", { uid = c.uid, roomId = State.RoomId(), cx = c.cx, cz = c.cz, rot = c.rot })
	else
		result = State.Request("Place", { itemId = c.itemId, roomId = State.RoomId(), cx = c.cx, cz = c.cz, rot = c.rot })
	end
	if result.ok then
		UI.Play("Pop", 0.4)
		stopCarry()
	end
end

local function store()
	local c = carry
	if not c then
		return
	end
	if not c.uid then
		stopCarry()
		return
	end
	local result = State.Request("StoreFurniture", { uid = c.uid })
	if result.ok then
		Decorate.Toast(Config.Items[c.itemId].Name .. " was put away in your items.")
		carry = nil
		c.ghost:Destroy()
		refreshToolbar()
	end
end

-- Furniture model under a viewport point in the current room.
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
	if not hit then
		return nil
	end
	local inst: Instance? = hit.Instance
	while inst and inst.Parent ~= folder do
		inst = inst.Parent
	end
	return inst :: Model?
end

local function pickUp(model: Model)
	local uid = model:GetAttribute("Uid") :: string
	for _, f in roomFurnitureData() do
		if f.uid == uid then
			beginCarry(f.item, uid, model, f.cx, f.cz, f.rot)
			return
		end
	end
end

function Decorate.IsActive(): boolean
	return State.Decorating
end

function Decorate.Enter()
	if State.IsVisiting() then
		State.SetView(State.HomePlot(), State.RoomIndex)
	end
	if not State.HasRoom(State.RoomId()) then
		Decorate.Toast("Unlock this room before decorating it.")
		return
	end
	State.Select(nil)
	State.Decorating = true
	toolbar.Visible = true
	refreshToolbar()
	State.DecorateChanged:Fire(true)
end

function Decorate.Exit()
	stopCarry()
	State.Decorating = false
	toolbar.Visible = false
	hoverBox.Adornee = nil
	State.DecorateChanged:Fire(false)
end

-- Starts placing a new item from the inventory in the current room.
function Decorate.StartPlacing(itemId: string)
	if not State.Decorating then
		Decorate.Enter()
	end
	if not State.Decorating then
		return
	end
	if not State.Profile or (State.Profile.inventory[itemId] or 0) < 1 then
		Decorate.Toast("You don't have that item.")
		return
	end
	beginCarry(itemId, nil, nil)
end

-- Called by the client for clicks/taps while decorating. Returns true if handled.
function Decorate.HandlePress(point: Vector2): boolean
	if not State.Decorating then
		return false
	end
	pointer = point
	if carry then
		if UI.IsTouch() then
			moveGhost(point)
		else
			moveGhost(point)
			confirm()
		end
		return true
	end
	local model = furnitureAt(point)
	if model then
		pickUp(model)
	end
	return true
end

function Decorate.Init()
	local screen = UI.Screen()
	toolbar = UI.new("Frame", {
		Name = "DecorateBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(640, 96),
		BackgroundColor3 = UI.Colors.Cream,
		Visible = false,
		Parent = screen,
	}, { UI.corner(16), UI.stroke(UI.Colors.Green, 4) })
	UI.title({ Text = "🛋️ Decorating", Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 24), TextSize = 20, Parent = toolbar })
	hint = UI.label({ Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 0, 18), TextSize = 14, TextColor3 = UI.Colors.Soft, Parent = toolbar })
	local row = UI.new("Frame", { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = toolbar }, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })

	carryButtons.Rotate = UI.button({ Text = "⟳ Rotate", Color = UI.Colors.Blue, Size = UDim2.fromOffset(110, 38), TextSize = 16, LayoutOrder = 1, Parent = row, Tooltip = "Rotate (R)", OnClick = rotate })
	carryButtons.Place = UI.button({ Text = "✓ Place", Color = UI.Colors.Green, Size = UDim2.fromOffset(110, 38), TextSize = 16, LayoutOrder = 2, Parent = row, OnClick = confirm })
	carryButtons.Store = UI.button({ Text = "📦 Put away", Color = UI.Colors.Orange, Size = UDim2.fromOffset(130, 38), TextSize = 16, LayoutOrder = 3, Parent = row, Tooltip = "Move it back to your items", OnClick = store })
	carryButtons.Cancel = UI.button({ Text = "✕ Cancel", Color = UI.Colors.Gray, Size = UDim2.fromOffset(110, 38), TextSize = 16, LayoutOrder = 4, Parent = row, OnClick = stopCarry })
	idleButtons.Items = UI.button({ Text = "🎒 Place an item", Color = UI.Colors.Blue, Size = UDim2.fromOffset(180, 38), TextSize = 16, LayoutOrder = 5, Parent = row, OnClick = function()
		Decorate.OpenItems()
	end })
	idleButtons.Done = UI.button({ Text = "✓ Done", Color = UI.Colors.Green, Size = UDim2.fromOffset(120, 38), TextSize = 16, LayoutOrder = 6, Parent = row, OnClick = Decorate.Exit })

	hoverBox = UI.new("SelectionBox", { Color3 = UI.Colors.Green, LineThickness = 0.08, SurfaceTransparency = 0.85, SurfaceColor3 = UI.Colors.Green, Parent = workspace })

	ContextActionService:BindAction("HappyPetsRotate", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and State.Decorating and carry then
			rotate()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.R)
	ContextActionService:BindAction("HappyPetsCancel", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and State.Decorating then
			if carry then
				stopCarry()
			else
				Decorate.Exit()
			end
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Escape, Enum.KeyCode.Delete)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			pointer = UserInputService:GetMouseLocation()
		end
	end)
	RunService.RenderStepped:Connect(function()
		if not State.Decorating then
			return
		end
		if carry and pointer and not UI.IsTouch() then
			moveGhost(pointer)
			hoverBox.Adornee = nil
		elseif not carry and pointer and not UI.IsTouch() then
			hoverBox.Adornee = furnitureAt(pointer)
		end
	end)
	-- Leaving the room or visiting someone ends what you were holding.
	State.RoomChanged:Connect(function()
		if carry then
			stopCarry()
		end
		if State.Decorating and (State.IsVisiting() or not State.HasRoom(State.RoomId())) then
			Decorate.Exit()
		end
	end)
	-- The server's copy of the room changed (e.g. after placing): re-check.
	State.ProfileChanged:Connect(function()
		if carry then
			moveGhost(nil)
		end
	end)
end

return Decorate
