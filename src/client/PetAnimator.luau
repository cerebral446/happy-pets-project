-- Brings the pets in the room you're looking at to life, entirely on this
-- client: wandering, sitting, looking around, walking to the bowl or a toy,
-- eating, playing, sleeping in bed, plus hearts, bubbles and thought bubbles.
--
-- The server only says *what* a pet is doing (attributes on its model, see
-- PetService); every pose here is computed locally from the rig attributes
-- written by PetModels, so it costs no network traffic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local State = require(script.Parent:WaitForChild("State"))
local UI = require(script.Parent:WaitForChild("UI"))
local Audio = require(script.Parent:WaitForChild("Audio"))

local player = Players.LocalPlayer

local PetAnimator = {}

type PartInfo = { part: BasePart, group: string, rest: CFrame, eye: boolean, eyeClosed: boolean }
type PetState = {
	model: Model,
	root: BasePart,
	parts: { PartInfo },
	joints: { [string]: CFrame },
	bodyInv: CFrame,
	height: number,
	hip: number,
	scale: number,
	pos: Vector3,
	yaw: number,
	target: Vector3?,
	targetYaw: number?,
	mode: string, -- "idle", "walk", "sit", "look", "groom"
	modeUntil: number,
	phase: number,
	stride: number,
	blinkAt: number,
	lastActionId: number,
	lastTeleport: number,
	thoughtAt: number,
	bubble: BillboardGui,
	bubbleText: TextLabel,
	bubbleUntil: number,
	nameTag: BillboardGui,
	gift: BillboardGui?,
	effectAt: number,
	room: string,
	toy: Model?,
	toyPivot: CFrame?,
	wasSleeping: boolean,
	snoreAt: number,
}

local pets: { [Model]: PetState } = {}
local hovered: Model? = nil
local highlight: Highlight
local giftFolder: Folder

-- Called when the player clicks a coin gift above a pet.
PetAnimator.OnGiftClicked = function(_model: Model) end

local W, D = Config.Room.Width, Config.Room.Depth

local function now(): number
	return workspace:GetServerTimeNow()
end

local function roomFloor(model: Model): CFrame
	local plot = model.Parent and model.Parent.Parent :: Model
	local roomId = model:GetAttribute("Room") :: string
	local _, order = Config.RoomById(roomId)
	return State.RoomCFrame(plot, order or 1)
end

local function randomSpot(model: Model): Vector3
	local floor = roomFloor(model)
	local x = (math.random() - 0.5) * (W - 5)
	local z = (math.random() - 0.5) * (D - 6) + 0.5
	return (floor * CFrame.new(x, 0, z)).Position
end

local function clampToRoom(model: Model, p: Vector3): Vector3
	local floor = roomFloor(model)
	local l = floor:PointToObjectSpace(p)
	local x = math.clamp(l.X, -W / 2 + 1.5, W / 2 - 1.5)
	local z = math.clamp(l.Z, -D / 2 + 1.5, D / 2 - 1)
	return (floor * CFrame.new(x, 0, z)).Position
end

local function findFurniture(model: Model, uid: string): Model?
	if uid == "" then
		return nil
	end
	local plot = model.Parent and model.Parent.Parent
	local rooms = plot and plot:FindFirstChild("Rooms")
	if not rooms then
		return nil
	end
	for _, room in rooms:GetChildren() do
		local f = room:FindFirstChild("Furniture")
		local item = f and f:FindFirstChild(uid)
		if item then
			return item :: Model
		end
	end
	return nil
end

-- Where a sleeping pet lies on each kind of bed (relative to the bed's pivot).
local SLEEP_SPOTS = {
	pet_bed = Vector3.new(0, 0.95, 0),
	cushion = Vector3.new(0, 0.55, 0),
	sofa = Vector3.new(-1.2, 1.4, 0.15),
	dog_house = Vector3.new(0, 0, 2.6),
}

local function bubbleGui(parent: BasePart, height: number): (BillboardGui, TextLabel)
	local gui = UI.new("BillboardGui", {
		Name = "Bubble",
		Size = UDim2.fromOffset(64, 56),
		StudsOffsetWorldSpace = Vector3.new(0, height * 0.5 + 1.6, 0),
		AlwaysOnTop = true,
		Enabled = false,
		LightInfluence = 0,
		Adornee = parent,
		Parent = parent,
	})
	local frame = UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UI.Colors.White,
		Parent = gui,
	}, { UI.corner(24), UI.stroke(UI.Colors.Edge, 2) })
	local text = UI.label({ Size = UDim2.fromScale(1, 1), TextScaled = true, Text = "", Parent = frame, Font = UI.Font })
	return gui, text
end

local function nameTagGui(model: Model, root: BasePart, height: number): BillboardGui
	local gui = UI.new("BillboardGui", {
		Name = "NameTag",
		Size = UDim2.fromOffset(160, 26),
		StudsOffsetWorldSpace = Vector3.new(0, height * 0.5 + 0.6, 0),
		AlwaysOnTop = true,
		Enabled = false,
		LightInfluence = 0,
		Adornee = root,
		Parent = root,
	})
	local label = UI.label({
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		Font = UI.Font,
		TextSize = 18,
		TextColor3 = UI.Colors.White,
		Parent = gui,
	})
	UI.textStroke(UI.Colors.Ink, 2).Parent = label
	local function refresh()
		local g = model:GetAttribute("Gender")
		label.Text = tostring(model:GetAttribute("Name") or "") .. (if g == "F" then " ♀" elseif g == "M" then " ♂" else "")
	end
	model:GetAttributeChangedSignal("Name"):Connect(refresh)
	refresh()
	return gui
end

local function giftGui(state: PetState): BillboardGui
	-- Interactive billboards have to live in PlayerGui.
	local gui = UI.new("BillboardGui", {
		Name = "Gift_" .. state.model.Name,
		Size = UDim2.fromOffset(52, 52),
		StudsOffsetWorldSpace = Vector3.new(0, state.height * 0.5 + 1.4, 0),
		AlwaysOnTop = true,
		Active = true,
		LightInfluence = 0,
		Adornee = state.root,
		Parent = giftFolder,
	})
	local btn = UI.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UI.Colors.Yellow,
		Text = "🪙",
		TextScaled = true,
		Font = UI.Font,
		Parent = gui,
	}, { UI.corner(26), UI.stroke(Color3.fromRGB(200, 140, 30), 3) })
	btn.Activated:Connect(function()
		PetAnimator.OnGiftClicked(state.model)
	end)
	UI.tooltip(btn, "Collect gift")
	return gui
end

local function track(model: Model)
	if pets[model] then
		return
	end
	local root = model.PrimaryPart or model:FindFirstChild("Root") :: BasePart?
	if not root then
		return
	end
	local joints = {}
	for name, value in model:GetAttributes() do
		if string.sub(name, 1, 6) == "Joint_" and typeof(value) == "CFrame" then
			joints[string.sub(name, 7)] = value
		end
	end
	local parts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= root then
			local group = p:GetAttribute("Group")
			local rest = p:GetAttribute("Rest")
			if typeof(group) == "string" and typeof(rest) == "CFrame" and joints[group] then
				table.insert(parts, { part = p, group = group, rest = rest, eye = p:GetAttribute("Eye") == true, eyeClosed = p:GetAttribute("EyeClosed") == true })
			end
		end
	end
	local height = (root:GetAttribute("Height") :: number?) or root.Size.Y
	local pivot = model:GetPivot()
	local look = pivot.LookVector
	local bubble, bubbleText = bubbleGui(root, height)
	local state: PetState = {
		model = model,
		root = root,
		parts = parts,
		joints = joints,
		bodyInv = (joints.Body or CFrame.identity):Inverse(),
		height = height,
		hip = if joints.LegFL then joints.LegFL.Position.Y else 0.8,
		scale = height / 3.2,
		pos = pivot.Position,
		yaw = math.atan2(-look.X, -look.Z),
		target = nil,
		mode = "idle",
		modeUntil = os.clock() + math.random() * 2,
		phase = math.random() * 6,
		stride = 0,
		blinkAt = os.clock() + 2 + math.random() * 3,
		lastActionId = (model:GetAttribute("ActionId") :: number?) or 0,
		lastTeleport = (model:GetAttribute("Teleport") :: number?) or 0,
		thoughtAt = os.clock() + 4 + math.random() * 6,
		bubble = bubble,
		bubbleText = bubbleText,
		bubbleUntil = 0,
		nameTag = nameTagGui(model, root, height),
		gift = nil,
		effectAt = 0,
		room = model:GetAttribute("Room") :: string,
		toy = nil,
		toyPivot = nil,
		wasSleeping = model:GetAttribute("Sleeping") == true,
		snoreAt = os.clock() + 8 + math.random() * 10,
	}
	pets[model] = state
end

local function untrack(model: Model)
	local state = pets[model]
	if state then
		if state.gift then
			state.gift:Destroy()
		end
		if state.toy and state.toyPivot and state.toy.Parent then
			state.toy:PivotTo(state.toyPivot)
		end
		pets[model] = nil
	end
end

function PetAnimator.Bubble(model: Model, text: string, seconds: number?)
	local state = pets[model]
	if not state then
		return
	end
	state.bubbleText.Text = text
	state.bubble.Enabled = true
	state.bubbleUntil = os.clock() + (seconds or 2)
end

-- Floating particles (hearts, bubbles, sparkles) rising from a pet.
local function burst(state: PetState, symbols: { string }, count: number)
	for i = 1, count do
		task.delay((i - 1) * 0.12, function()
			if not state.root.Parent then
				return
			end
			local gui = UI.new("BillboardGui", {
				Size = UDim2.fromOffset(34, 34),
				StudsOffsetWorldSpace = Vector3.new((math.random() - 0.5) * 2 * state.scale, state.height * 0.3, (math.random() - 0.5) * 1.2),
				AlwaysOnTop = true,
				LightInfluence = 0,
				Adornee = state.root,
				Parent = state.root,
			})
			local label = UI.label({ Size = UDim2.fromScale(1, 1), Text = symbols[math.random(1, #symbols)], TextScaled = true, Parent = gui })
			local info = TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(gui, info, { StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + Vector3.new(0, 3, 0) }):Play()
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
			task.delay(1.35, function()
				gui:Destroy()
			end)
		end)
	end
end

function PetAnimator.Hearts(model: Model)
	local state = pets[model]
	if state then
		burst(state, { "💕", "💖", "❤️" }, 5)
	end
end

function PetAnimator.WorldPosition(model: Model): Vector3?
	local state = pets[model]
	if state then
		return state.pos + Vector3.new(0, state.height, 0)
	end
	return model:GetPivot().Position
end

function PetAnimator.SetHover(model: Model?)
	hovered = model
end

---------------------------------------------------------------------------
-- Behaviour
---------------------------------------------------------------------------

local ACTION_EFFECTS = {
	Pet = { "💕", "💖", "❤️" },
	Love = { "💕", "💗", "💞" },
	Bath = { "🫧", "🫧", "💧" },
	Brush = { "✨", "⭐" },
	Treat = { "😋", "⭐" },
	Medicine = { "💊", "✨" },
	Eat = { "😋" },
	Play = { "🎵", "⭐", "💫" },
}

-- Which voice each action uses (see Config.Audio).
local ACTION_VOICES = {
	Pet = "Love",
	Love = "Love",
	Treat = "Love",
	Eat = "Eat",
	Play = "Play",
	Bath = "Greet",
	Brush = "Love",
	Medicine = "Greet",
}

-- Pets only make noise in the room you're looking at.
local function inView(model: Model): boolean
	return model:GetAttribute("Room") == State.RoomId()
end

local function actionGoal(state: PetState, action: string, target: Model?): (Vector3?, Vector3?)
	if not target then
		return nil, nil
	end
	local pivot = target:GetPivot()
	local item = target:GetAttribute("Item") :: string
	local def = Config.Items[item]
	local radius = if def then math.max(def.Footprint[1], def.Footprint[2]) * Config.Room.Cell * 0.5 else 1
	-- Stand at the edge of the item, on the side nearest the pet.
	local away = state.pos - pivot.Position
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(0, 0, 1)
	end
	local stand = pivot.Position + away.Unit * (radius + state.scale * 1.1)
	return clampToRoom(state.model, Vector3.new(stand.X, pivot.Position.Y, stand.Z)), pivot.Position
end

local function sleepSpot(state: PetState, bed: Model?): Vector3?
	if not bed then
		return nil
	end
	local item = bed:GetAttribute("Item") :: string
	local offset = SLEEP_SPOTS[item]
	local pivot = bed:GetPivot()
	if offset then
		return pivot:PointToWorldSpace(offset)
	end
	local cf, size = bed:GetBoundingBox()
	return Vector3.new(cf.Position.X, cf.Position.Y + size.Y / 2 - 0.2, cf.Position.Z)
end

local function walkTo(state: PetState, target: Vector3, dt: number, speed: number): boolean
	local delta = target - state.pos
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local dist = flat.Magnitude
	if dist < 0.15 then
		state.pos = Vector3.new(target.X, target.Y, target.Z)
		return true
	end
	local step = math.min(dist, speed * dt)
	local dir = flat.Unit
	state.pos += dir * step
	-- Hop down from a bed straight away, but up onto one only when close.
	if dist < 2.2 or target.Y < state.pos.Y then
		state.pos = Vector3.new(state.pos.X, state.pos.Y + (target.Y - state.pos.Y) * math.min(1, dt * 6), state.pos.Z)
	end
	state.targetYaw = math.atan2(-dir.X, -dir.Z)
	state.stride = math.min(1, state.stride + dt * 5)
	state.phase += dt * speed * 2.4 / math.max(state.scale, 0.5)
	return false
end

local function turnTo(state: PetState, yaw: number, dt: number)
	local diff = (yaw - state.yaw + math.pi) % (2 * math.pi) - math.pi
	state.yaw += diff * math.min(1, dt * 8)
end

local function cameraYaw(state: PetState): number
	local cam = workspace.CurrentCamera.CFrame.Position
	local d = cam - state.pos
	return math.atan2(-d.X, -d.Z)
end

-- Returns the pose name for this frame and moves the pet.
local function behave(state: PetState, dt: number, t: number): string
	local model = state.model
	local clock = os.clock()

	-- Teleports (moved to another room) snap instantly.
	local tp = (model:GetAttribute("Teleport") :: number?) or 0
	if tp ~= state.lastTeleport then
		state.lastTeleport = tp
		state.pos = model:GetPivot().Position
		state.target = nil
		state.mode = "idle"
	end
	if model:GetAttribute("Room") ~= state.room then
		state.room = model:GetAttribute("Room") :: string
		state.pos = clampToRoom(model, model:GetPivot().Position)
	end

	local speedFactor = 0.6 + 0.4 * (((model:GetAttribute("Mood") :: number?) or 70) / 100)
	local walkSpeed = 5 * speedFactor * math.max(0.7, state.scale)

	-- Actions requested by the server take priority.
	local action = model:GetAttribute("Action") :: string
	local actionEnd = (model:GetAttribute("ActionEnd") :: number?) or 0
	local actionId = (model:GetAttribute("ActionId") :: number?) or 0
	if actionId ~= state.lastActionId then
		state.lastActionId = actionId
		state.effectAt = 0
		if action == "Eat" then
			PetAnimator.Bubble(model, "🍽️", 1.5)
		end
		local voice = ACTION_VOICES[action]
		if voice and inView(model) and (model:GetAttribute("ActionEnd") :: number? or 0) > now() then
			-- Eating and playing sound once the pet reaches the bowl or toy.
			local delay = if (action == "Eat" or action == "Play") and model:GetAttribute("ActionTarget") ~= "" then 1.6 else 0
			task.delay(delay, Audio.PetSound, model, voice)
		end
	end
	if action ~= "" and actionEnd > now() then
		local target = findFurniture(model, model:GetAttribute("ActionTarget") :: string)
		local stand, look = actionGoal(state, action, target)
		if stand and not walkTo(state, stand, dt, walkSpeed * 1.4) then
			return "walk"
		end
		if look then
			local d = look - state.pos
			turnTo(state, math.atan2(-d.X, -d.Z), dt)
		elseif action == "Pet" or action == "Love" or action == "Treat" or action == "Medicine" then
			turnTo(state, cameraYaw(state), dt)
		end
		if action == "Play" and target and target ~= state.toy then
			state.toy = target
			state.toyPivot = target:GetPivot()
		end
		local fx = ACTION_EFFECTS[action]
		if fx and clock >= state.effectAt then
			state.effectAt = clock + (if action == "Bath" then 0.6 else 1.4)
			burst(state, fx, if action == "Pet" or action == "Love" then 3 else 2)
		end
		state.stride = math.max(0, state.stride - dt * 5)
		return action
	end
	if state.toy then
		if state.toy.Parent and state.toyPivot then
			state.toy:PivotTo(state.toyPivot)
		end
		state.toy, state.toyPivot = nil, nil
	end

	-- Falling asleep, and the odd snore or purr while asleep.
	local sleeping = model:GetAttribute("Sleeping") == true
	if sleeping ~= state.wasSleeping then
		state.wasSleeping = sleeping
		if sleeping and inView(model) then
			Audio.PetSound(model, "Sleep", 0.7)
		end
		state.snoreAt = clock + 15 + math.random() * 15
	elseif sleeping and clock >= state.snoreAt then
		state.snoreAt = clock + 18 + math.random() * 20
		if inView(model) then
			Audio.PetSound(model, "Sleep", 0.45)
		end
	end

	-- Sleeping: walk to bed (if any) and curl up.
	if sleeping then
		local bed = findFurniture(model, (model:GetAttribute("SleepTarget") :: string?) or "")
		local spot = sleepSpot(state, bed)
		if spot and not walkTo(state, spot, dt, walkSpeed) then
			return "walk"
		end
		state.stride = math.max(0, state.stride - dt * 5)
		if clock >= state.effectAt then
			state.effectAt = clock + 2.2
			burst(state, { "💤" }, 1)
		end
		return "sleep"
	end
	-- Woke up on a bed: hop down.
	local floorY = roomFloor(model).Position.Y
	if state.pos.Y > floorY + 0.05 and not state.target then
		state.target = clampToRoom(model, state.pos + Vector3.new(0, 0, 2.5))
		state.mode = "walk"
	end

	-- Thought bubble when a need is low.
	local low = model:GetAttribute("Low") :: string?
	if low and low ~= "" and clock >= state.thoughtAt then
		state.thoughtAt = clock + 9 + math.random() * 6
		local info = Config.NeedInfo[low]
		if info then
			PetAnimator.Bubble(model, info.Icon, 2.5)
			if inView(model) and math.random() < 0.5 then
				Audio.PetSound(model, "Sad")
			end
		end
	end

	-- Wandering.
	if state.mode == "walk" and state.target then
		if walkTo(state, state.target, dt, walkSpeed) then
			state.target = nil
			local r = math.random()
			state.mode = if r < 0.35 then "sit" elseif r < 0.6 then "look" elseif r < 0.75 then "groom" else "idle"
			state.modeUntil = clock + 2 + math.random() * 5
		end
		return "walk"
	end
	state.stride = math.max(0, state.stride - dt * 5)
	if clock >= state.modeUntil then
		if model == State.SelectedPet and math.random() < 0.6 then
			-- Selected pets tend to stay put and look at you.
			state.mode = "look"
			state.targetYaw = cameraYaw(state)
			state.modeUntil = clock + 3
		else
			state.mode = "walk"
			state.target = randomSpot(model)
		end
	end
	if model == State.SelectedPet then
		turnTo(state, cameraYaw(state), dt * 0.5)
	end
	return state.mode
end

---------------------------------------------------------------------------
-- Posing
---------------------------------------------------------------------------

local partsBuffer: { BasePart } = {}
local cframeBuffer: { CFrame } = {}

local function pose(state: PetState, poseName: string, t: number, dt: number)
	if state.targetYaw then
		turnTo(state, state.targetYaw, dt)
	end
	local s = state.scale
	local swing = math.sin(state.phase) * math.rad(32) * state.stride
	local lift = 0
	local body = CFrame.identity
	local head = CFrame.identity
	local tail = CFrame.Angles(0, math.sin(t * 3) * 0.25, 0)
	local legs = {
		LegFL = CFrame.Angles(swing, 0, 0),
		LegBR = CFrame.Angles(swing, 0, 0),
		LegFR = CFrame.Angles(-swing, 0, 0),
		LegBL = CFrame.Angles(-swing, 0, 0),
	}
	local eyesClosed = false

	if poseName == "walk" then
		body = CFrame.new(0, math.abs(math.sin(state.phase)) * 0.12 * s, 0)
		head = CFrame.Angles(math.sin(state.phase * 2) * 0.04, 0, 0)
		tail = CFrame.Angles(0.15, math.sin(t * 6) * 0.4, 0)
	elseif poseName == "sit" then
		local drop = state.hip * 0.35
		body = CFrame.new(0, -drop, 0.15 * s) * CFrame.Angles(math.rad(22), 0, 0)
		legs.LegBL = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(75), 0, 0)
		legs.LegBR = legs.LegBL
		legs.LegFL = CFrame.Angles(math.rad(-8), 0, 0)
		legs.LegFR = legs.LegFL
		head = CFrame.Angles(math.rad(-18), math.sin(t * 0.7) * 0.3, 0)
		lift = -drop * 0.6
		tail = CFrame.Angles(-0.4, math.sin(t * 1.5) * 0.5, 0)
	elseif poseName == "look" then
		head = CFrame.Angles(math.sin(t * 0.9) * 0.1, math.sin(t * 1.1) * 0.6, math.sin(t * 0.8) * 0.15)
	elseif poseName == "groom" then
		head = CFrame.Angles(math.rad(-35) + math.sin(t * 8) * 0.12, 0.6, 0.3)
		legs.LegFL = CFrame.Angles(math.rad(-50), 0, 0)
	elseif poseName == "sleep" then
		local drop = state.hip * 0.85
		lift = -drop
		body = CFrame.Angles(0, 0, 0.08)
		legs.LegFL = CFrame.Angles(math.rad(80), 0, 0)
		legs.LegFR = legs.LegFL
		legs.LegBL = CFrame.Angles(math.rad(-80), 0, 0)
		legs.LegBR = legs.LegBL
		head = CFrame.new(0, -0.35 * s, -0.1 * s) * CFrame.Angles(math.rad(-12), 0.35, 0.3)
		tail = CFrame.Angles(0.5, 1.1, 0)
		eyesClosed = true
		-- Gentle breathing.
		body = body * CFrame.new(0, math.sin(t * 1.6) * 0.04 * s, 0)
	elseif poseName == "Eat" then
		body = CFrame.Angles(math.rad(-10), 0, 0)
		head = CFrame.Angles(math.rad(-38) + math.sin(t * 10) * 0.12, 0, 0)
		tail = CFrame.Angles(0.2, math.sin(t * 8) * 0.5, 0)
	elseif poseName == "Play" then
		local hop = math.abs(math.sin(t * 5.5))
		lift = hop * 1.1 * s
		state.yaw += dt * 2.2
		legs.LegFL = CFrame.Angles(math.rad(-40) * hop, 0, 0)
		legs.LegFR = legs.LegFL
		tail = CFrame.Angles(0.3, math.sin(t * 12) * 0.6, 0)
		if state.toy and state.toyPivot and state.toy.Parent then
			local bounce = math.abs(math.sin(t * 5.5 + 1.2)) * 1.2
			state.toy:PivotTo(state.toyPivot * CFrame.new(0, bounce, 0) * CFrame.Angles(0, t * 3, 0))
		end
	elseif poseName == "Pet" or poseName == "Love" or poseName == "Treat" or poseName == "Medicine" then
		local hop = math.max(0, math.sin(t * 7))
		lift = hop * 0.35 * s
		head = CFrame.Angles(math.rad(10), 0, math.sin(t * 3) * 0.3)
		tail = CFrame.Angles(0.4, math.sin(t * 16) * 0.7, 0)
		eyesClosed = poseName == "Pet" and math.sin(t * 2) > 0
	elseif poseName == "Bath" or poseName == "Brush" then
		body = CFrame.Angles(0, 0, math.sin(t * 9) * 0.12)
		head = CFrame.Angles(0, math.sin(t * 9) * 0.3, 0)
		tail = CFrame.Angles(0.2, math.sin(t * 14) * 0.6, 0)
	else
		-- Idle: breathing and the odd tail flick.
		body = CFrame.new(0, math.sin(t * 2) * 0.03 * s, 0)
		head = CFrame.Angles(0, math.sin(t * 0.5) * 0.15, 0)
	end

	-- Blinking.
	local clock = os.clock()
	if not eyesClosed and clock >= state.blinkAt then
		eyesClosed = true
		if clock >= state.blinkAt + 0.14 then
			state.blinkAt = clock + 2 + math.random() * 4
		end
	end

	local ground = CFrame.new(state.pos) * CFrame.Angles(0, state.yaw, 0) * CFrame.new(0, lift, 0)
	local bodyWorld = ground * (state.joints.Body or CFrame.identity) * body
	local groupCF: { [string]: CFrame } = {
		Body = bodyWorld,
		Head = bodyWorld * state.bodyInv * (state.joints.Head or CFrame.identity) * head,
		Tail = bodyWorld * state.bodyInv * (state.joints.Tail or CFrame.identity) * tail,
	}
	for _, leg in { "LegFL", "LegFR", "LegBL", "LegBR" } do
		if state.joints[leg] then
			groupCF[leg] = ground * state.joints[leg] * legs[leg]
		end
	end

	local n = 0
	for _, info in state.parts do
		local cf = groupCF[info.group]
		if cf then
			n += 1
			partsBuffer[n] = info.part
			cframeBuffer[n] = cf * info.rest
		end
		if info.eye or info.eyeClosed then
			local hidden = if info.eye then eyesClosed else not eyesClosed
			local want = if hidden then 1 else 0
			if info.part.Transparency ~= want then
				info.part.Transparency = want
			end
		end
	end
	n += 1
	partsBuffer[n] = state.root
	cframeBuffer[n] = CFrame.new(state.pos) * CFrame.Angles(0, state.yaw, 0) * CFrame.new(0, state.height / 2, 0)
	for i = #partsBuffer, n + 1, -1 do
		partsBuffer[i] = nil
		cframeBuffer[i] = nil
	end
	workspace:BulkMoveTo(partsBuffer, cframeBuffer, Enum.BulkMoveMode.FireCFrameChanged)
end

---------------------------------------------------------------------------

local function petsFolder(): Folder?
	local plot = State.ViewPlot
	return plot and plot:FindFirstChild("Pets") :: Folder?
end

local watchedFolder: Folder? = nil
local folderConns: { RBXScriptConnection } = {}

local function watch(folder: Folder?)
	if folder == watchedFolder then
		return
	end
	for _, c in folderConns do
		c:Disconnect()
	end
	table.clear(folderConns)
	for model in pets do
		untrack(model)
	end
	watchedFolder = folder
	if not folder then
		return
	end
	for _, m in folder:GetChildren() do
		if m:IsA("Model") then
			track(m)
		end
	end
	table.insert(folderConns, folder.ChildAdded:Connect(function(m)
		if m:IsA("Model") then
			-- Parts and attributes replicate with the model; give them a frame.
			task.defer(track, m)
		end
	end))
	table.insert(folderConns, folder.ChildRemoved:Connect(function(m)
		untrack(m :: Model)
	end))
end

function PetAnimator.Init()
	giftFolder = UI.new("Folder", { Name = "PetGifts", Parent = player:WaitForChild("PlayerGui") })
	highlight = UI.new("Highlight", {
		Name = "PetSelection",
		FillTransparency = 1,
		OutlineColor = Color3.fromRGB(255, 120, 180),
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Parent = workspace,
	})
	State.SelectionChanged:Connect(function(model)
		highlight.Adornee = model
	end)
	State.RoomChanged:Connect(function()
		watch(petsFolder())
	end)

	RunService.RenderStepped:Connect(function(dt)
		dt = math.min(dt, 0.1)
		watch(petsFolder())
		local t = os.clock()
		local own = State.ViewPlot == State.HomePlot()
		local roomId = State.RoomId()
		for model, state in pets do
			if not model.Parent or not state.root.Parent then
				untrack(model)
				continue
			end
			-- Only animate pets in (or next to) the room on screen.
			local _, roomIdx = Config.RoomById(model:GetAttribute("Room") :: string)
			roomIdx = roomIdx or 1
			if math.abs(roomIdx - State.RoomIndex) <= 1 then
				local poseName = behave(state, dt, t)
				pose(state, poseName, t + state.phase * 0.1, dt)
			end
			state.nameTag.Enabled = model == hovered or model == State.SelectedPet
			if state.bubble.Enabled and t >= state.bubbleUntil then
				state.bubble.Enabled = false
			end
			-- Coin gifts only for your own pets in the room you're looking at.
			local wantsGift = own and model:GetAttribute("Gift") == true and model:GetAttribute("Room") == roomId and not State.Decorating
			if wantsGift and not state.gift then
				state.gift = giftGui(state)
			elseif not wantsGift and state.gift then
				state.gift:Destroy()
				state.gift = nil
			end
			if state.gift then
				state.gift.StudsOffsetWorldSpace = Vector3.new(0, state.height * 0.5 + 1.4 + math.sin(t * 3) * 0.25, 0)
			end
		end
	end)
end

return PetAnimator
