-- Each player gets a plot: a little dollhouse of rooms side by side, open at
-- the front so the camera can look in. This module builds the rooms (walls,
-- floors, wallpaper patterns), keeps the furniture models in sync with the
-- save data, and shows locked rooms as "for sale".
--
-- Workspace.Plots.Plot_<n>            attributes Owner, OwnerName, Index
--   Rooms.<roomId>                    attributes RoomId, Order, Locked
--     Shell                           floor, walls, decoration
--     Furniture.<uid>                 attributes Uid, Item, RoomId
--   Pets.<petId>                      built by PetService

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Build = require(Shared:WaitForChild("Build"))
local Placement = require(Shared:WaitForChild("Placement"))
local FurnitureModels = require(Shared:WaitForChild("FurnitureModels"))
local Economy = require(Shared:WaitForChild("Economy"))

local Plots = {}

local plotsFolder: Folder
local used: { [number]: boolean } = {}

local V = Vector3.new
local rgb = Color3.fromRGB
local W, D, H = Config.Room.Width, Config.Room.Depth, Config.Room.WallHeight
local WALL = 1

function Plots.Init()
	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace
end

local function part(parent: Instance, props: any): BasePart
	props.Parent = parent
	local p = Build.Part(props)
	p.CanQuery = props.CanQuery ~= false
	return p
end

-- Floor-centre CFrame of a room (index 1..#Config.Rooms) on a plot.
function Plots.RoomCFrame(plot: Model, order: number): CFrame
	local origin = plot:GetAttribute("Origin") :: Vector3
	return CFrame.new(origin + V((order - 1) * Config.Room.Spacing, 0, 0))
end

local function buildWallPattern(shell: Model, wallCF: CFrame, width: number, height: number, style: any)
	-- wallCF: centre of the wall's inner face, facing into the room (+Z of the CFrame).
	local accent = style.Accent
	if style.Pattern == "Stripes" then
		local count = math.floor(width / 2)
		for i = 0, count - 1 do
			if i % 2 == 0 then
				local x = -width / 2 + (i + 0.5) * (width / count)
				part(shell, { Name = "Stripe", Size = V(width / count, height - 1.4, 0.05), CFrame = wallCF * CFrame.new(x, 0.3, 0.03), Color = accent, CanQuery = false })
			end
		end
	elseif style.Pattern == "Dots" or style.Pattern == "Stars" then
		local cols = math.floor(width / 3.5)
		local rows = math.floor(height / 3.2)
		for r = 0, rows - 1 do
			for c = 0, cols - 1 do
				local x = -width / 2 + (c + 0.5 + (r % 2) * 0.5) * (width / cols)
				local y = -height / 2 + (r + 0.7) * (height / rows)
				if x < width / 2 - 0.6 and y < height / 2 - 1.5 then
					if style.Pattern == "Dots" then
						part(shell, { Name = "Dot", Shape = "Cylinder", Size = V(0.7, 0.05, 0.7), CFrame = wallCF * CFrame.new(x, y, 0.03) * CFrame.Angles(math.pi / 2, 0, 0), Color = accent, CanQuery = false })
					else
						local star = part(shell, { Name = "Star", Size = V(0.45, 0.45, 0.05), CFrame = wallCF * CFrame.new(x, y, 0.03) * CFrame.Angles(0, 0, math.rad(45)), Color = accent, Material = Enum.Material.Neon, CanQuery = false })
						star.CastShadow = false
					end
				end
			end
		end
	end
end

local function buildShell(room: Model, roomCF: CFrame, def: any, roomData: any?, locked: boolean)
	local old = room:FindFirstChild("Shell")
	if old then
		old:Destroy()
	end
	local shell = Instance.new("Model")
	shell.Name = "Shell"

	local floorStyle = Config.FloorById(if roomData then roomData.floor else def.Floor) or Config.Floors[1]
	local wallStyle = Config.WallpaperById(if roomData then roomData.wallpaper else def.Wallpaper) or Config.Wallpapers[1]
	if locked then
		floorStyle = { Color = rgb(190, 180, 170), Alt = rgb(190, 180, 170), Material = Enum.Material.WoodPlanks, Pattern = "Plain" }
		wallStyle = { Color = rgb(214, 206, 196), Accent = rgb(200, 190, 180), Pattern = "Plain" }
	end

	-- Floor (top surface at y = 0). Tagged so the decorate tool can raycast it.
	local floor = part(shell, {
		Name = "Floor",
		Size = V(W + WALL * 2, 1, D),
		CFrame = roomCF * CFrame.new(0, -0.5, 0),
		Color = floorStyle.Color,
		Material = floorStyle.Material,
	})
	floor:SetAttribute("RoomFloor", true)
	if floorStyle.Pattern == "Checker" then
		local cell = Config.Room.Cell
		for cx = 0, Placement.Cols - 1 do
			for cz = 0, Placement.Rows - 1 do
				if (cx + cz) % 2 == 1 then
					local tile = part(shell, {
						Name = "Tile",
						Size = V(cell, 0.04, cell),
						CFrame = roomCF * CFrame.new(-W / 2 + (cx + 0.5) * cell, 0.02, -D / 2 + (cz + 0.5) * cell),
						Color = floorStyle.Alt,
						CanQuery = false,
					})
					tile.CastShadow = false
				end
			end
		end
	end
	-- Front edge trim.
	part(shell, { Name = "Trim", Size = V(W + WALL * 2, 1.2, 0.6), CFrame = roomCF * CFrame.new(0, -0.4, D / 2 + 0.3), Color = rgb(250, 246, 236), CanQuery = false })

	if def.Outdoor and not locked then
		-- Garden: picket fence instead of walls, open to the sky.
		local white = rgb(250, 250, 250)
		local function fence(fromCF: CFrame, length: number)
			part(shell, { Name = "Rail", Size = V(length, 0.3, 0.2), CFrame = fromCF * CFrame.new(0, 1.2, 0), Color = white, CanQuery = false })
			part(shell, { Name = "Rail", Size = V(length, 0.3, 0.2), CFrame = fromCF * CFrame.new(0, 2.2, 0), Color = white, CanQuery = false })
			for i = 0, math.floor(length / 1.4) do
				local x = -length / 2 + i * 1.4
				part(shell, { Name = "Picket", Size = V(0.5, 3, 0.25), CFrame = fromCF * CFrame.new(x, 1.5, 0.05), Color = white, CanQuery = false })
			end
		end
		fence(roomCF * CFrame.new(0, 0, -D / 2 - 0.3), W + 2)
		fence(roomCF * CFrame.new(-W / 2 - 0.6, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), D)
		fence(roomCF * CFrame.new(W / 2 + 0.6, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), D)
	else
		local wallColor = wallStyle.Color
		-- Back wall with a window.
		local backCF = roomCF * CFrame.new(0, H / 2, -D / 2 - WALL / 2)
		part(shell, { Name = "Wall", Size = V(W + WALL * 2, H, WALL), CFrame = backCF, Color = wallColor })
		local faceCF = roomCF * CFrame.new(0, H / 2, -D / 2)
		buildWallPattern(shell, faceCF, W, H, wallStyle)
		-- Side walls.
		for _, side in { -1, 1 } do
			part(shell, { Name = "Wall", Size = V(WALL, H, D), CFrame = roomCF * CFrame.new(side * (W / 2 + WALL / 2), H / 2, 0), Color = wallColor })
			local sideFace = roomCF * CFrame.new(side * W / 2, H / 2, 0) * CFrame.Angles(0, -side * math.pi / 2, 0)
			buildWallPattern(shell, sideFace, D, H, wallStyle)
		end
		-- Skirting boards.
		local skirting = rgb(255, 252, 245)
		part(shell, { Name = "Skirting", Size = V(W, 0.6, 0.15), CFrame = roomCF * CFrame.new(0, 0.3, -D / 2 + 0.08), Color = skirting, CanQuery = false })
		for _, side in { -1, 1 } do
			part(shell, { Name = "Skirting", Size = V(0.15, 0.6, D), CFrame = roomCF * CFrame.new(side * (W / 2 - 0.08), 0.3, 0), Color = skirting, CanQuery = false })
		end
		-- Window.
		if not locked then
			local winCF = roomCF * CFrame.new(W * 0.22, H * 0.58, -D / 2 + 0.05)
			part(shell, { Name = "WindowFrame", Size = V(5.4, 4.4, 0.2), CFrame = winCF, Color = rgb(255, 255, 255), CanQuery = false })
			local glass = part(shell, { Name = "Window", Size = V(4.8, 3.8, 0.22), CFrame = winCF, Color = rgb(170, 220, 255), Material = Enum.Material.Neon, CanQuery = false })
			glass.Transparency = 0.15
			part(shell, { Name = "WindowBar", Size = V(0.2, 3.8, 0.26), CFrame = winCF, Color = rgb(255, 255, 255), CanQuery = false })
			part(shell, { Name = "WindowBar", Size = V(4.8, 0.2, 0.26), CFrame = winCF, Color = rgb(255, 255, 255), CanQuery = false })
			part(shell, { Name = "Sill", Size = V(6, 0.3, 0.7), CFrame = winCF * CFrame.new(0, -2.3, 0.3), Color = rgb(255, 255, 255), CanQuery = false })
			-- A ceiling light so rooms aren't gloomy.
			local lamp = part(shell, { Name = "Light", Size = V(1, 0.2, 1), CFrame = roomCF * CFrame.new(0, H - 0.1, -2), Color = rgb(255, 250, 230), Transparency = 1, CanQuery = false })
			local light = Instance.new("PointLight")
			light.Range = 26
			light.Brightness = 0.8
			light.Color = rgb(255, 240, 220)
			light.Shadows = false
			light.Parent = lamp
		end
		-- Roof edge along the top of the back wall.
		part(shell, { Name = "Roof", Size = V(W + WALL * 2 + 1, 0.8, 3), CFrame = roomCF * CFrame.new(0, H + 0.4, -D / 2 + 0.5), Color = rgb(214, 110, 110), CanQuery = false })
	end

	if locked then
		local sign = part(shell, { Name = "LockedSign", Size = V(10, 5, 0.3), CFrame = roomCF * CFrame.new(0, 5, -D / 2 + 0.3), Color = rgb(255, 246, 220), CanQuery = false })
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(400, 200)
		gui.Parent = sign
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = rgb(120, 80, 70)
		label.Text = string.format("🔒 %s\nLevel %d · %d coins", def.Name, def.Level, def.Price)
		label.Parent = gui
		-- The sign faces -Z by default (Front face); turn it to face the camera.
		sign.CFrame = sign.CFrame * CFrame.Angles(0, math.pi, 0)
		-- Boards across the opening.
		for i = 0, 2 do
			part(shell, { Name = "Board", Size = V(W * 0.9, 0.7, 0.3), CFrame = roomCF * CFrame.new(0, 1.5 + i * 3.5, D / 2 - 0.5) * CFrame.Angles(0, 0, (i % 2 - 0.5) * 0.12), Color = rgb(190, 150, 110), Material = Enum.Material.Wood, CanQuery = false })
		end
	end

	shell.Parent = room
end

local function furnitureFolder(room: Model): Folder
	return room:FindFirstChild("Furniture") :: Folder
end

local function placeFurniture(room: Model, roomCF: CFrame, f: any)
	local model = FurnitureModels.Create(f.item)
	model.Name = f.uid
	model:SetAttribute("Uid", f.uid)
	model:SetAttribute("Item", f.item)
	model:SetAttribute("RoomId", room:GetAttribute("RoomId"))
	model:PivotTo(FurnitureModels.PlacementCFrame(roomCF, f.item, f.cx, f.cz, f.rot, Placement))
	model.Parent = furnitureFolder(room)
end

-- Makes the furniture models in a room match the save data.
function Plots.SyncFurniture(plot: Model, roomData: any)
	local room = (plot:FindFirstChild("Rooms") :: Folder):FindFirstChild(roomData.id) :: Model?
	if not room then
		return
	end
	local roomCF = Plots.RoomCFrame(plot, room:GetAttribute("Order"))
	local folder = furnitureFolder(room)
	local wanted = {}
	for _, f in roomData.furniture do
		wanted[f.uid] = f
	end
	for _, model in folder:GetChildren() do
		local f = wanted[model.Name]
		if not f or model:GetAttribute("Item") ~= f.item then
			model:Destroy()
		else
			model:PivotTo(FurnitureModels.PlacementCFrame(roomCF, f.item, f.cx, f.cz, f.rot, Placement))
			wanted[model.Name] = nil
		end
	end
	for _, f in wanted do
		placeFurniture(room, roomCF, f)
	end
end

-- Rebuilds a room's shell (after a wallpaper/floor change or an unlock).
function Plots.RefreshRoom(plot: Model, data: any, roomId: string)
	local def, order = Config.RoomById(roomId)
	local room = (plot:FindFirstChild("Rooms") :: Folder):FindFirstChild(roomId) :: Model?
	if not def or not room then
		return
	end
	local roomData = Economy.GetRoom(data, roomId)
	local locked = roomData == nil
	room:SetAttribute("Locked", locked)
	buildShell(room, Plots.RoomCFrame(plot, order), def, roomData, locked)
	if roomData then
		Plots.SyncFurniture(plot, roomData)
	else
		furnitureFolder(room):ClearAllChildren()
	end
end

local function buildGrounds(plot: Model)
	local origin = plot:GetAttribute("Origin") :: Vector3
	local span = (#Config.Rooms - 1) * Config.Room.Spacing
	local center = origin + V(span / 2, 0, 0)
	local grounds = Instance.new("Model")
	grounds.Name = "Grounds"
	part(grounds, { Name = "Lawn", Size = V(span + 140, 2, 140), CFrame = CFrame.new(center + V(0, -1.2, 10)), Color = rgb(140, 204, 110), Material = Enum.Material.Grass, CanQuery = false })
	part(grounds, { Name = "Path", Size = V(span + 60, 0.2, 6), CFrame = CFrame.new(center + V(0, -0.15, D / 2 + 8)), Color = rgb(236, 220, 190), Material = Enum.Material.Pebble, CanQuery = false })
	-- A few round trees and bushes behind the house.
	local rng = Random.new(7)
	for i = 1, 14 do
		local x = center.X + rng:NextNumber(-span / 2 - 50, span / 2 + 50)
		local z = center.Z - D / 2 - rng:NextNumber(12, 50)
		local s = rng:NextNumber(0.8, 1.6)
		part(grounds, { Name = "Trunk", Shape = "Cylinder", Size = V(1.2 * s, 6 * s, 1.2 * s), CFrame = CFrame.new(x, 3 * s - 0.2, z), Color = rgb(140, 100, 70), Material = Enum.Material.Wood, CanQuery = false })
		part(grounds, { Name = "Leaves", Shape = "Ellipsoid", Size = V(8, 7, 8) * s, CFrame = CFrame.new(x, 8 * s, z), Color = rgb(96 + i * 3, 176, 92), Material = Enum.Material.Grass, CanQuery = false })
	end
	for i = 1, 10 do
		local x = center.X + (i - 5.5) * (span + 40) / 10
		part(grounds, { Name = "Bush", Shape = "Ellipsoid", Size = V(4, 2.6, 3), CFrame = CFrame.new(x, 0.9, origin.Z + D / 2 + 14), Color = rgb(110, 186, 100), Material = Enum.Material.Grass, CanQuery = false })
	end
	grounds.Parent = plot
end

-- Creates a plot for the player and builds every room (locked ones too).
function Plots.Create(player: Player, data: any): Model
	local index = 0
	while used[index] do
		index += 1
	end
	used[index] = true
	local plot = Instance.new("Model")
	plot.Name = "Plot_" .. index
	plot:SetAttribute("Index", index)
	plot:SetAttribute("Owner", player.UserId)
	plot:SetAttribute("OwnerName", player.DisplayName)
	plot:SetAttribute("Origin", V(index * Config.PlotSpacing, 0, 0))

	local rooms = Instance.new("Folder")
	rooms.Name = "Rooms"
	rooms.Parent = plot
	local pets = Instance.new("Folder")
	pets.Name = "Pets"
	pets.Parent = plot

	buildGrounds(plot)
	for order, def in Config.Rooms do
		local room = Instance.new("Model")
		room.Name = def.Id
		room:SetAttribute("RoomId", def.Id)
		room:SetAttribute("Order", order)
		room:SetAttribute("RoomName", def.Name)
		local furniture = Instance.new("Folder")
		furniture.Name = "Furniture"
		furniture.Parent = room
		room.Parent = rooms
		Plots.RefreshRoom(plot, data, def.Id)
	end
	plot.Parent = plotsFolder
	return plot
end

function Plots.Rebuild(plot: Model, data: any)
	for _, def in Config.Rooms do
		Plots.RefreshRoom(plot, data, def.Id)
	end
end

function Plots.Destroy(plot: Model)
	used[plot:GetAttribute("Index") :: number] = nil
	plot:Destroy()
end

return Plots
