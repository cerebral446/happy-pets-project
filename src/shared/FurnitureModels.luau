-- Builds furniture models out of parts. Each model is centred on its
-- footprint with its base on the floor (y = 0) and its front facing +Z
-- (toward the camera) at rotation 0. Its pivot is that floor centre.
--
-- To use real artwork, put a model named after the item id (e.g. "pet_bed")
-- in ReplicatedStorage.Assets.Furniture, with its pivot at the floor centre.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local Build = require(script.Parent.Build)

local FurnitureModels = {}

local Mat = Enum.Material
local rgb = Color3.fromRGB

local function P(model: Model, shape: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?, rot: CFrame?, transparency: number?, name: string?): BasePart
	return Build.Part({
		Name = name or "Part",
		Shape = shape,
		Size = size,
		CFrame = CFrame.new(pos) * (rot or CFrame.identity),
		Color = color,
		Material = material,
		Transparency = transparency,
		Parent = model,
	})
end

local V = Vector3.new

local function bowl(m: Model, outer: Color3, fill: Color3, fillMaterial: Enum.Material?, fillTransparency: number?)
	P(m, "Cylinder", V(1.7, 0.55, 1.7), V(0, 0.28, 0), outer)
	P(m, "Cylinder", V(1.95, 0.12, 1.95), V(0, 0.5, 0), Build.Shade(outer, 0.25))
	P(m, "Cylinder", V(1.35, 0.1, 1.35), V(0, 0.55, 0), fill, fillMaterial, nil, fillTransparency, "Fill")
end

local builders: { [string]: (Model) -> () } = {
	food_bowl = function(m)
		bowl(m, rgb(240, 120, 150), rgb(170, 110, 60), Mat.Pebble)
	end,
	water_bowl = function(m)
		bowl(m, rgb(110, 160, 230), rgb(150, 210, 250), Mat.Glass, 0.25)
	end,
	pet_bed = function(m)
		P(m, "Ellipsoid", V(3.8, 1.3, 3.8), V(0, 0.5, 0), rgb(236, 120, 160), Mat.Fabric)
		P(m, "Ellipsoid", V(3.0, 0.8, 3.0), V(0, 0.75, 0), rgb(252, 214, 228), Mat.Fabric, nil, nil, "Cushion")
		P(m, "Ellipsoid", V(0.6, 0.35, 0.6), V(0.9, 1.1, 0.5), rgb(255, 255, 255), Mat.Fabric)
	end,
	cushion = function(m)
		P(m, "Ellipsoid", V(1.9, 0.6, 1.9), V(0, 0.3, 0), rgb(170, 130, 220), Mat.Fabric, nil, nil, "Cushion")
		P(m, "Ellipsoid", V(0.25, 0.2, 0.25), V(0, 0.6, 0), rgb(240, 210, 100))
	end,
	yarn_ball = function(m)
		P(m, "Ball", V(1.1, 1.1, 1.1), V(0, 0.55, 0), rgb(226, 70, 90), Mat.Fabric)
		for i = 0, 2 do
			P(m, "Cylinder", V(1.14, 0.08, 1.14), V(0, 0.55, 0), rgb(250, 120, 140), Mat.Fabric, CFrame.Angles(i * 1.05, i * 0.7, 0.4))
		end
		P(m, "Block", V(0.08, 0.06, 0.9), V(0.3, 0.04, 0.75), rgb(226, 70, 90), Mat.Fabric, CFrame.Angles(0, 0.5, 0))
	end,
	toy_ball = function(m)
		P(m, "Ball", V(1.2, 1.2, 1.2), V(0, 0.6, 0), rgb(80, 150, 240))
		P(m, "Cylinder", V(1.24, 0.3, 1.24), V(0, 0.6, 0), rgb(255, 230, 90), nil, CFrame.Angles(0, 0, math.pi / 2))
	end,
	mouse_toy = function(m)
		P(m, "Ellipsoid", V(0.65, 0.5, 1.0), V(0, 0.25, 0), rgb(170, 170, 180), Mat.Fabric)
		P(m, "Ball", V(0.3, 0.3, 0.3), V(-0.2, 0.5, -0.3), rgb(250, 180, 200))
		P(m, "Ball", V(0.3, 0.3, 0.3), V(0.2, 0.5, -0.3), rgb(250, 180, 200))
		P(m, "Ball", V(0.1, 0.1, 0.1), V(0, 0.28, -0.5), rgb(240, 120, 150))
		P(m, "Block", V(0.06, 0.06, 0.9), V(0, 0.1, 0.9), rgb(240, 160, 180), nil, CFrame.Angles(0, 0.3, 0))
	end,
	scratching_post = function(m)
		P(m, "Block", V(1.9, 0.3, 1.9), V(0, 0.15, 0), rgb(200, 170, 130), Mat.Fabric)
		P(m, "Cylinder", V(0.75, 3.4, 0.75), V(0, 2.0, 0), rgb(214, 186, 140), Mat.Fabric, nil, nil, "Post")
		P(m, "Block", V(1.4, 0.25, 1.4), V(0, 3.8, 0), rgb(200, 170, 130), Mat.Fabric)
		P(m, "Block", V(0.05, 0.9, 0.05), V(0.6, 3.25, 0.6), rgb(240, 240, 240))
		P(m, "Ball", V(0.35, 0.35, 0.35), V(0.6, 2.7, 0.6), rgb(240, 90, 140), Mat.Fabric)
	end,
	cat_tree = function(m)
		local carpet = rgb(196, 170, 220)
		P(m, "Block", V(3.8, 0.35, 3.8), V(0, 0.18, 0), carpet, Mat.Fabric)
		P(m, "Cylinder", V(0.7, 5.0, 0.7), V(-1.1, 2.8, -1.1), rgb(214, 186, 140), Mat.Fabric)
		P(m, "Cylinder", V(0.7, 3.0, 0.7), V(1.1, 1.8, 1.0), rgb(214, 186, 140), Mat.Fabric)
		P(m, "Block", V(2.0, 0.3, 2.0), V(1.0, 3.4, 1.0), carpet, Mat.Fabric)
		P(m, "Block", V(2.2, 0.3, 2.2), V(-0.9, 5.4, -0.9), carpet, Mat.Fabric)
		P(m, "Block", V(1.8, 1.6, 1.8), V(-0.9, 1.15, 0.9), carpet, Mat.Fabric)
		P(m, "Cylinder", V(1.0, 0.05, 1.0), V(-0.9, 1.1, 1.8), rgb(80, 60, 90), nil, CFrame.Angles(math.pi / 2, 0, 0))
	end,
	litter_tray = function(m)
		P(m, "Block", V(3.6, 0.6, 1.8), V(0, 0.3, 0), rgb(120, 190, 220))
		P(m, "Block", V(3.3, 0.1, 1.5), V(0, 0.6, 0), rgb(230, 214, 170), Mat.Sand)
		P(m, "Block", V(0.6, 0.08, 0.3), V(1.1, 0.68, 0.3), rgb(255, 255, 255))
	end,
	sofa = function(m)
		local fabric = rgb(110, 196, 190)
		P(m, "Block", V(5.8, 1.1, 1.8), V(0, 0.55, 0), fabric, Mat.Fabric)
		P(m, "Block", V(5.8, 1.6, 0.5), V(0, 1.6, -0.65), fabric, Mat.Fabric)
		P(m, "Block", V(0.5, 1.6, 1.8), V(-2.65, 1.0, 0), Build.Shade(fabric, -0.1), Mat.Fabric)
		P(m, "Block", V(0.5, 1.6, 1.8), V(2.65, 1.0, 0), Build.Shade(fabric, -0.1), Mat.Fabric)
		P(m, "Block", V(2.35, 0.35, 1.3), V(-1.2, 1.25, 0.15), Build.Shade(fabric, 0.3), Mat.Fabric, nil, nil, "Cushion")
		P(m, "Block", V(2.35, 0.35, 1.3), V(1.2, 1.25, 0.15), Build.Shade(fabric, 0.3), Mat.Fabric)
		P(m, "Ellipsoid", V(0.9, 0.9, 0.35), V(-2.0, 1.7, -0.3), rgb(250, 200, 220), Mat.Fabric)
	end,
	dog_house = function(m)
		local wood = rgb(214, 90, 80)
		P(m, "Block", V(3.4, 2.6, 3.4), V(0, 1.3, 0), wood, Mat.Wood)
		-- A wedge's tall face is at its back (+Z), so the front half is turned around.
		P(m, "Wedge", V(3.8, 1.4, 1.95), V(0, 3.3, 0.95), rgb(90, 80, 120), nil, CFrame.Angles(0, math.pi, 0))
		P(m, "Wedge", V(3.8, 1.4, 1.95), V(0, 3.3, -0.95), rgb(90, 80, 120))
		P(m, "Ellipsoid", V(1.6, 2.0, 0.1), V(0, 0.95, 1.7), rgb(50, 40, 40))
		P(m, "Block", V(1.2, 0.4, 0.1), V(0, 2.25, 1.72), rgb(255, 240, 200))
	end,
	potted_plant = function(m)
		P(m, "Cylinder", V(1.2, 1.1, 1.2), V(0, 0.55, 0), rgb(214, 120, 80))
		P(m, "Cylinder", V(1.35, 0.2, 1.35), V(0, 1.1, 0), rgb(196, 104, 70))
		local leaf = rgb(90, 170, 90)
		P(m, "Ellipsoid", V(1.3, 1.6, 1.3), V(0, 2.0, 0), leaf, Mat.Grass)
		P(m, "Ellipsoid", V(0.9, 1.2, 0.9), V(0.45, 2.5, 0.2), Build.Shade(leaf, 0.15), Mat.Grass)
		P(m, "Ellipsoid", V(0.9, 1.1, 0.9), V(-0.4, 2.6, -0.2), Build.Shade(leaf, -0.1), Mat.Grass)
	end,
	rug_round = function(m)
		P(m, "Cylinder", V(5.8, 0.06, 5.8), V(0, 0.03, 0), rgb(150, 200, 240), Mat.Fabric)
		P(m, "Cylinder", V(4.4, 0.07, 4.4), V(0, 0.04, 0), rgb(250, 250, 255), Mat.Fabric)
		P(m, "Cylinder", V(3.2, 0.08, 3.2), V(0, 0.05, 0), rgb(150, 200, 240), Mat.Fabric)
	end,
	rug_heart = function(m)
		local pink = rgb(246, 150, 190)
		P(m, "Cylinder", V(3.0, 0.06, 3.0), V(-1.0, 0.03, -0.9), pink, Mat.Fabric)
		P(m, "Cylinder", V(3.0, 0.06, 3.0), V(1.0, 0.03, -0.9), pink, Mat.Fabric)
		P(m, "Block", V(3.0, 0.06, 3.0), V(0, 0.03, 0.4), pink, Mat.Fabric, CFrame.Angles(0, math.rad(45), 0))
		P(m, "Cylinder", V(1.4, 0.07, 1.4), V(-0.9, 0.04, -0.9), rgb(255, 210, 225), Mat.Fabric)
	end,
	floor_lamp = function(m)
		P(m, "Cylinder", V(1.1, 0.15, 1.1), V(0, 0.08, 0), rgb(90, 80, 70), Mat.Metal)
		P(m, "Cylinder", V(0.15, 4.5, 0.15), V(0, 2.3, 0), rgb(90, 80, 70), Mat.Metal)
		local shade = P(m, "Cylinder", V(1.5, 1.1, 1.5), V(0, 4.8, 0), rgb(255, 236, 170), Mat.Fabric, nil, nil, "Shade")
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 214, 150)
		light.Range = 14
		light.Brightness = 1.4
		light.Shadows = true
		light.Parent = shade
	end,
	toy_chest = function(m)
		P(m, "Block", V(3.6, 1.6, 1.7), V(0, 0.8, 0), rgb(240, 180, 90), Mat.Wood)
		P(m, "Block", V(3.7, 0.35, 1.8), V(0, 1.75, 0), rgb(220, 90, 90), Mat.Wood)
		P(m, "Block", V(0.5, 0.4, 0.08), V(0, 1.35, 0.88), rgb(250, 220, 90), Mat.Metal)
		P(m, "Block", V(0.25, 1.6, 0.06), V(-1.2, 0.8, 0.87), rgb(110, 170, 230))
		P(m, "Block", V(0.25, 1.6, 0.06), V(1.2, 0.8, 0.87), rgb(110, 170, 230))
		P(m, "Ball", V(0.8, 0.8, 0.8), V(1.0, 2.1, -0.2), rgb(200, 150, 100), Mat.Fabric)
	end,
	bookshelf = function(m)
		local wood = rgb(170, 120, 80)
		P(m, "Block", V(3.6, 5.0, 0.2), V(0, 2.5, -0.75), Build.Shade(wood, -0.15), Mat.Wood)
		P(m, "Block", V(0.2, 5.0, 1.7), V(-1.7, 2.5, 0), wood, Mat.Wood)
		P(m, "Block", V(0.2, 5.0, 1.7), V(1.7, 2.5, 0), wood, Mat.Wood)
		local colors = { rgb(230, 90, 90), rgb(90, 140, 230), rgb(250, 200, 80), rgb(120, 200, 130), rgb(190, 130, 220) }
		for shelf = 0, 3 do
			local y = 0.1 + shelf * 1.6
			P(m, "Block", V(3.3, 0.15, 1.6), V(0, y, 0), wood, Mat.Wood)
			if shelf < 3 then
				local x = -1.4
				for i = 1, 6 do
					local w = 0.32 + ((i + shelf) % 3) * 0.06
					local h = 0.95 + ((i * 7 + shelf) % 4) * 0.1
					P(m, "Block", V(w, h, 1.1), V(x + w / 2, y + 0.08 + h / 2, 0.1), colors[(i + shelf) % #colors + 1])
					x += w + 0.06
				end
			end
		end
	end,
	fish_tank = function(m)
		P(m, "Block", V(3.7, 1.6, 1.7), V(0, 0.8, 0), rgb(110, 90, 80), Mat.Wood)
		P(m, "Block", V(3.6, 2.0, 1.6), V(0, 2.6, 0), rgb(170, 220, 250), Mat.Glass, nil, 0.55)
		P(m, "Block", V(3.4, 1.6, 1.4), V(0, 2.45, 0), rgb(90, 170, 230), Mat.SmoothPlastic, nil, 0.6)
		P(m, "Block", V(3.4, 0.2, 1.4), V(0, 1.7, 0), rgb(230, 210, 160), Mat.Sand)
		P(m, "Ellipsoid", V(0.6, 0.35, 0.18), V(-0.7, 2.6, 0.2), rgb(250, 140, 40), nil, nil, nil, "Fish")
		P(m, "Ellipsoid", V(0.5, 0.3, 0.16), V(0.8, 2.2, -0.1), rgb(250, 220, 60), nil, nil, nil, "Fish")
		P(m, "Ellipsoid", V(0.2, 0.9, 0.2), V(1.3, 2.2, -0.3), rgb(80, 180, 90))
		P(m, "Block", V(3.7, 0.15, 1.7), V(0, 3.65, 0), rgb(60, 60, 70))
	end,
	flower_bed = function(m)
		P(m, "Block", V(3.6, 0.9, 1.6), V(0, 0.45, 0), rgb(200, 140, 100), Mat.Wood)
		P(m, "Block", V(3.3, 0.1, 1.3), V(0, 0.92, 0), rgb(110, 80, 60), Mat.Ground)
		local petals = { rgb(240, 80, 120), rgb(250, 200, 60), rgb(240, 120, 200), rgb(250, 130, 70), rgb(200, 120, 240) }
		for i = 1, 5 do
			local x = -1.4 + (i - 1) * 0.7
			P(m, "Cylinder", V(0.1, 1.0, 0.1), V(x, 1.4, (i % 2) * 0.3 - 0.15), rgb(80, 160, 80))
			P(m, "Ellipsoid", V(0.45, 0.55, 0.45), V(x, 2.0, (i % 2) * 0.3 - 0.15), petals[i])
		end
	end,
	garden_tree = function(m)
		P(m, "Cylinder", V(0.8, 3.0, 0.8), V(0, 1.5, 0), rgb(140, 100, 70), Mat.Wood)
		P(m, "Ellipsoid", V(3.6, 3.0, 3.6), V(0, 4.0, 0), rgb(100, 180, 90), Mat.Grass)
		P(m, "Ellipsoid", V(2.4, 2.2, 2.4), V(0.6, 5.2, 0.3), rgb(120, 196, 100), Mat.Grass)
		P(m, "Ball", V(0.35, 0.35, 0.35), V(1.2, 3.6, 1.3), rgb(230, 60, 60))
		P(m, "Ball", V(0.35, 0.35, 0.35), V(-1.1, 4.4, 1.0), rgb(230, 60, 60))
	end,
	fountain = function(m)
		local stone = rgb(214, 214, 224)
		P(m, "Cylinder", V(3.9, 0.9, 3.9), V(0, 0.45, 0), stone, Mat.Marble)
		P(m, "Cylinder", V(3.3, 0.1, 3.3), V(0, 0.88, 0), rgb(120, 190, 240), Mat.Glass, nil, 0.2)
		P(m, "Cylinder", V(0.6, 2.2, 0.6), V(0, 1.9, 0), stone, Mat.Marble)
		P(m, "Cylinder", V(1.8, 0.35, 1.8), V(0, 3.0, 0), stone, Mat.Marble)
		P(m, "Cylinder", V(0.25, 1.0, 0.25), V(0, 3.6, 0), rgb(160, 220, 255), Mat.Glass, nil, 0.3)
		P(m, "Ball", V(0.6, 0.6, 0.6), V(0, 4.15, 0), rgb(160, 220, 255), Mat.Glass, nil, 0.3)
	end,
}

-- A plain box sized to the footprint, used when an item has no builder.
local function fallback(m: Model, itemId: string)
	local item = Config.Items[itemId]
	local w, d = item.Footprint[1] * Config.Room.Cell, item.Footprint[2] * Config.Room.Cell
	P(m, "Block", V(w - 0.2, 1, d - 0.2), V(0, 0.5, 0), rgb(220, 200, 240))
end

-- Builds the item at the origin. The pivot is the floor centre.
function FurnitureModels.Create(itemId: string): Model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Furniture")
	local custom = folder and folder:FindFirstChild(itemId)
	if custom and custom:IsA("Model") then
		local m = custom:Clone()
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
			end
		end
		m:PivotTo(CFrame.identity)
		return m
	end
	local m = Instance.new("Model")
	m.Name = itemId
	local build = builders[itemId]
	if build then
		build(m)
	else
		fallback(m, itemId)
	end
	m.WorldPivot = CFrame.identity
	return m
end

-- World CFrame for an item at (cx, cz, rot) in a room whose floor centre is roomCF.
function FurnitureModels.PlacementCFrame(roomCF: CFrame, itemId: string, cx: number, cz: number, rot: number, Placement: any): CFrame
	local x, z = Placement.CellToLocal(itemId, cx, cz, rot)
	return roomCF * CFrame.new(x, 0, z) * CFrame.Angles(0, -rot * math.pi / 2, 0)
end

return FurnitureModels
