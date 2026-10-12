-- A fixed dollhouse camera looking into the current room from the front.
-- Mouse wheel / pinch zooms; Q/E or dragging with the right mouse button
-- swings the view a little; switching rooms glides across the house.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local State = require(script.Parent:WaitForChild("State"))

local CameraController = {}

local camera = workspace.CurrentCamera
local zoom = 1 -- 0.55 (close) .. 1.35 (far)
local swing = 0 -- radians, -0.5 .. 0.5
local current: CFrame? = nil
local dragging = false

local OFFSET = Vector3.new(0, 15, 27)
local LOOK = Vector3.new(0, 2.2, -1.5)

local function goal(): CFrame
	local roomCF = State.RoomCFrame(State.ViewPlot, State.RoomIndex)
	local focus = roomCF.Position + LOOK
	local offset = CFrame.Angles(0, swing, 0) * (OFFSET * zoom)
	return CFrame.lookAt(focus + offset, focus)
end

function CameraController.Zoom(delta: number)
	zoom = math.clamp(zoom + delta, 0.55, 1.35)
end

function CameraController.Snap()
	current = nil
end

function CameraController.Init()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 50

	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			CameraController.Zoom(-input.Position.Z * 0.08)
		elseif input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
			swing = math.clamp(swing - input.Delta.X * 0.004, -0.55, 0.55)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = true
		elseif input.KeyCode == Enum.KeyCode.Q then
			swing = math.clamp(swing + 0.2, -0.55, 0.55)
		elseif input.KeyCode == Enum.KeyCode.E then
			swing = math.clamp(swing - 0.2, -0.55, 0.55)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = false
		end
	end)
	UserInputService.TouchPinch:Connect(function(_, scale, _, inputState, processed)
		if not processed and inputState == Enum.UserInputState.Change then
			CameraController.Zoom((1 - scale) * 0.05)
		end
	end)
	State.RoomChanged:Connect(function()
		swing = 0
	end)

	RunService:BindToRenderStep("HappyPetsCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		if not State.ViewPlot then
			return
		end
		local target = goal()
		if not current or (current.Position - target.Position).Magnitude > Config.PlotSpacing * 0.5 then
			current = target
		else
			current = (current :: CFrame):Lerp(target, math.min(1, dt * 6))
		end
		camera.CFrame = current :: CFrame
	end)
end

return CameraController
