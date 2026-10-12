-- Builds pet models out of parts, coloured by species, coat colour, pattern
-- and eye colour. Used by the server (pets in the world) and the client
-- (adoption previews and portraits).
--
-- Animation rig: every part has a "Group" attribute (Body, Head, Tail, LegFL,
-- LegFR, LegBL, LegBR) and a "Rest" CFrame relative to that group's joint.
-- The model stores each joint as an attribute "Joint_<Group>" relative to the
-- invisible "Root" part at floor level. Head and Tail hang off the Body; legs
-- hang off the Root. The client's PetAnimator poses the groups.
--
-- Pets face -Z. To use real artwork instead, put a model named after the
-- species in ReplicatedStorage.Assets.Pets with the same part groups (see
-- the README); it is cloned and tinted instead of the built-in shapes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local Build = require(script.Parent.Build)

local PetModels = {}

local WHITE = Color3.fromRGB(250, 248, 244)
local PINK = Color3.fromRGB(240, 150, 170)
local DARK = Color3.fromRGB(40, 34, 38)

-- Body proportions per species (studs at scale 1).
local SHAPES = {
	Cat = { body = Vector3.new(1.6, 1.45, 2.3), head = Vector3.new(1.75, 1.55, 1.5), leg = 0.95, ears = "Pointy", tail = "Long", snout = 0 },
	Dog = { body = Vector3.new(1.75, 1.6, 2.5), head = Vector3.new(1.8, 1.6, 1.6), leg = 1.05, ears = "Floppy", tail = "Wag", snout = 0.45 },
	Bunny = { body = Vector3.new(1.7, 1.6, 2.0), head = Vector3.new(1.6, 1.5, 1.45), leg = 0.6, ears = "Long", tail = "Puff", snout = 0 },
	Fox = { body = Vector3.new(1.55, 1.4, 2.4), head = Vector3.new(1.7, 1.45, 1.5), leg = 1.0, ears = "Big", tail = "Bushy", snout = 0.55 },
	Panda = { body = Vector3.new(2.1, 1.9, 2.5), head = Vector3.new(2.0, 1.8, 1.7), leg = 0.85, ears = "Round", tail = "Stub", snout = 0.25 },
}

-- Spots on the body surface for "Spotted" and "Calico" (unit body space).
local SPOTS = {
	Vector3.new(0.35, 0.35, -0.3),
	Vector3.new(-0.4, 0.3, 0.2),
	Vector3.new(0.1, 0.45, 0.35),
	Vector3.new(-0.2, 0.42, -0.05),
	Vector3.new(0.45, 0.1, 0.3),
}

type Builder = {
	model: Model,
	scale: number,
	add: (self: Builder, group: string, name: string, shape: string, size: Vector3, pos: Vector3, rot: CFrame?, color: Color3, material: Enum.Material?) -> BasePart,
}

local function colorsFor(species: string, colorName: string, pattern: string)
	local base = Config.Colors[colorName] or Config.Colors.Orange
	local c = {
		coat = base,
		accent = Build.Shade(base, -0.35),
		belly = Build.Shade(base, 0.35),
		paws = base,
		muzzle = Build.Shade(base, 0.3),
		ears = base,
		tail = base,
		earInner = PINK,
	}
	if pattern == "Tuxedo" then
		c.belly, c.paws, c.muzzle = WHITE, WHITE, WHITE
	elseif pattern == "Socks" then
		c.paws = if species == "Fox" then DARK else WHITE
	elseif pattern == "Points" then
		c.coat = Build.Shade(base, 0.6)
		c.belly = Build.Shade(base, 0.7)
		local point = Build.Shade(base, -0.3)
		c.paws, c.muzzle, c.ears, c.tail = point, point, point, point
	elseif pattern == "Calico" then
		c.coat, c.belly, c.paws, c.muzzle = WHITE, WHITE, WHITE, WHITE
	elseif pattern == "Panda" then
		local dark = if colorName == "Brown" then Config.Colors.Chocolate else DARK
		c.coat, c.belly, c.muzzle, c.tail = WHITE, WHITE, WHITE, WHITE
		c.paws, c.ears, c.accent = dark, dark, dark
		c.earInner = dark
	end
	if species == "Fox" and pattern ~= "Points" then
		c.belly = WHITE
		c.muzzle = WHITE
		c.earInner = DARK
	end
	if species == "Bunny" then
		c.earInner = PINK
	end
	return c
end

local function newBuilder(model: Model, scale: number): Builder
	local b = { model = model, scale = scale } :: any
	function b.add(self: Builder, group: string, name: string, shape: string, size: Vector3, pos: Vector3, rot: CFrame?, color: Color3, material: Enum.Material?): BasePart
		local rest = CFrame.new(pos * self.scale) * (rot or CFrame.identity)
		local joint = self.model:GetAttribute("Joint_" .. group) :: CFrame
		local part = Build.Part({
			Name = name,
			Shape = shape,
			Size = size * self.scale,
			CFrame = joint * rest,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Parent = self.model,
		})
		part:SetAttribute("Group", group)
		part:SetAttribute("Rest", rest)
		-- Cylinders are rotated inside Build.Part; record what was actually used.
		if shape == "Cylinder" then
			part:SetAttribute("Rest", rest * CFrame.Angles(0, 0, math.pi / 2))
		end
		part.CastShadow = false
		return part
	end
	return b
end

-- Builds a pet at the origin (floor level, facing -Z). `pet` needs species,
-- color, pattern, eyes and stage.
function PetModels.Build(pet: any): Model
	local species = pet.species
	local def = Config.Species[species] or Config.Species.Cat
	local shape = SHAPES[species] or SHAPES.Cat
	local baby = pet.stage == "Baby"
	local scale = def.Scale * (if baby then 0.7 else 1)
	local headBoost = if baby then 1.12 else 1
	local c = colorsFor(species, pet.color, pet.pattern)

	local model = Instance.new("Model")
	model.Name = pet.name or species

	local body, head = shape.body, shape.head * headBoost
	local legLen = shape.leg
	local hipY = legLen
	local bodyY = hipY + body.Y * 0.35
	local halfZ = body.Z / 2

	local joints = {
		Body = CFrame.new(0, bodyY * scale, 0),
		Head = CFrame.new(0, (bodyY + body.Y * 0.55) * scale, (-halfZ - head.Z * 0.05) * scale),
		Tail = CFrame.new(0, (bodyY + body.Y * 0.1) * scale, (halfZ - 0.15) * scale),
		LegFL = CFrame.new(-body.X * 0.27 * scale, hipY * scale, -halfZ * 0.55 * scale),
		LegFR = CFrame.new(body.X * 0.27 * scale, hipY * scale, -halfZ * 0.55 * scale),
		LegBL = CFrame.new(-body.X * 0.27 * scale, hipY * scale, halfZ * 0.55 * scale),
		LegBR = CFrame.new(body.X * 0.27 * scale, hipY * scale, halfZ * 0.55 * scale),
	}
	if species == "Bunny" then
		-- Bunnies sit upright-ish with the head tucked low and close.
		joints.Head = CFrame.new(0, (bodyY + body.Y * 0.5) * scale, (-halfZ + 0.15) * scale)
	end
	for group, cf in joints do
		model:SetAttribute("Joint_" .. group, cf)
	end

	-- Invisible root: floor-level pivot and click hitbox.
	local totalH = (bodyY + body.Y * 0.55 + head.Y * 0.9) * scale
	local root = Build.Part({
		Name = "Root",
		Size = Vector3.new(body.X + 0.4, totalH, body.Z + head.Z * 0.6) * Vector3.new(scale, 1, scale),
		CFrame = CFrame.new(0, totalH / 2, 0),
		Color = c.coat,
		Transparency = 1,
		Parent = model,
	})
	root:SetAttribute("Height", totalH)
	-- Pivot at floor level so PivotTo places the paws on the floor.
	root.PivotOffset = CFrame.new(0, -totalH / 2, 0)
	model.PrimaryPart = root

	local b = newBuilder(model, scale)

	-- Body
	b:add("Body", "Torso", "Ellipsoid", body, Vector3.zero, nil, c.coat)
	b:add("Body", "Belly", "Ellipsoid", Vector3.new(body.X * 0.7, body.Y * 0.7, body.Z * 0.45), Vector3.new(0, -body.Y * 0.12, -halfZ * 0.62), nil, c.belly)

	if pet.pattern == "Tabby" then
		for i = -1, 1 do
			b:add("Body", "Stripe", "Ellipsoid", Vector3.new(body.X * 1.04, body.Y * 0.55, 0.22), Vector3.new(0, body.Y * 0.2, i * body.Z * 0.24), nil, c.accent)
		end
	elseif pet.pattern == "Spotted" then
		for i, s in SPOTS do
			if i <= 4 then
				b:add("Body", "Spot", "Ellipsoid", Vector3.new(0.55, 0.45, 0.55), s * body, nil, c.accent)
			end
		end
	elseif pet.pattern == "Calico" then
		local patches = { Config.Colors.Orange, DARK, Config.Colors.Orange, DARK }
		for i = 1, 4 do
			b:add("Body", "Patch", "Ellipsoid", Vector3.new(0.85, 0.65, 0.85), SPOTS[i] * body, nil, patches[i])
		end
	elseif pet.pattern == "Panda" then
		b:add("Body", "Band", "Ellipsoid", Vector3.new(body.X * 1.04, body.Y * 1.02, body.Z * 0.32), Vector3.new(0, 0.02, -halfZ * 0.35), nil, c.accent)
	end

	-- Legs and paws
	for _, g in { "LegFL", "LegFR", "LegBL", "LegBR" } do
		local back = string.sub(g, 4, 4) == "B"
		local len = if species == "Bunny" and back then legLen * 1.1 else legLen
		local legColor = if pet.pattern == "Panda" or pet.pattern == "Points" then c.paws else c.coat
		local thick = if species == "Panda" then 0.62 else 0.48
		b:add(g, "Leg", "Ellipsoid", Vector3.new(thick, len + 0.25, thick), Vector3.new(0, -len / 2, 0), nil, legColor)
		b:add(g, "Paw", "Ellipsoid", Vector3.new(thick + 0.08, 0.3, thick + 0.22), Vector3.new(0, -len + 0.13, -0.08), nil, c.paws)
	end

	-- Head
	local hx, hy, hz = head.X, head.Y, head.Z
	b:add("Head", "Skull", "Ellipsoid", head, Vector3.zero, nil, c.coat)
	if pet.pattern == "Tabby" then
		b:add("Head", "Stripe", "Ellipsoid", Vector3.new(0.18, hy * 0.5, hz * 0.6), Vector3.new(0, hy * 0.28, -hz * 0.15), nil, c.accent)
		b:add("Head", "Stripe", "Ellipsoid", Vector3.new(0.14, hy * 0.42, hz * 0.6), Vector3.new(-0.28, hy * 0.26, -hz * 0.12), nil, c.accent)
		b:add("Head", "Stripe", "Ellipsoid", Vector3.new(0.14, hy * 0.42, hz * 0.6), Vector3.new(0.28, hy * 0.26, -hz * 0.12), nil, c.accent)
	elseif pet.pattern == "Calico" then
		b:add("Head", "Patch", "Ellipsoid", Vector3.new(hx * 0.6, hy * 0.6, hz * 0.9), Vector3.new(-hx * 0.22, hy * 0.18, 0), nil, Config.Colors.Orange)
	elseif pet.pattern == "Points" then
		b:add("Head", "Mask", "Ellipsoid", Vector3.new(hx * 0.62, hy * 0.62, hz * 0.4), Vector3.new(0, -hy * 0.08, -hz * 0.32), nil, c.muzzle)
	end

	-- Muzzle / snout
	local snout = shape.snout
	local muzzleZ = -hz * 0.42 - snout * 0.5
	b:add("Head", "Muzzle", "Ellipsoid", Vector3.new(hx * 0.5, hy * 0.36, hz * 0.4 + snout), Vector3.new(0, -hy * 0.2, muzzleZ), nil, c.muzzle)
	b:add("Head", "Nose", "Ellipsoid", Vector3.new(0.26, 0.18, 0.18), Vector3.new(0, -hy * 0.1, muzzleZ - (hz * 0.4 + snout) / 2 + 0.04), nil, if species == "Panda" or species == "Dog" or species == "Fox" then DARK else PINK)

	-- Eyes (open) and closed-eye lines for sleeping
	local eyeColor = Config.EyeColors[pet.eyes] or Config.EyeColors.Brown
	for _, side in { -1, 1 } do
		local ex, ey, ez = side * hx * 0.22, hy * 0.06, -hz * 0.43
		if pet.pattern == "Panda" then
			b:add("Head", "EyePatch", "Ellipsoid", Vector3.new(0.6, 0.75, 0.3), Vector3.new(ex, ey - 0.05, ez + 0.03), CFrame.Angles(0, 0, side * 0.5), c.accent)
		end
		local iris = b:add("Head", "Iris", "Ellipsoid", Vector3.new(0.36, 0.44, 0.16), Vector3.new(ex, ey, ez - 0.02), nil, eyeColor)
		local pupil = b:add("Head", "Pupil", "Ellipsoid", Vector3.new(0.22, 0.32, 0.12), Vector3.new(ex, ey - 0.02, ez - 0.07), nil, DARK)
		local shine = b:add("Head", "Shine", "Ellipsoid", Vector3.new(0.1, 0.1, 0.06), Vector3.new(ex + side * 0.05, ey + 0.09, ez - 0.12), nil, Color3.new(1, 1, 1))
		for _, p in { iris, pupil, shine } do
			p:SetAttribute("Eye", true)
		end
		local closed = b:add("Head", "EyeClosed", "Ellipsoid", Vector3.new(0.34, 0.07, 0.1), Vector3.new(ex, ey - 0.04, ez - 0.05), nil, DARK)
		closed:SetAttribute("EyeClosed", true)
		closed.Transparency = 1
		-- Rosy cheeks.
		b:add("Head", "Cheek", "Ellipsoid", Vector3.new(0.3, 0.16, 0.12), Vector3.new(side * hx * 0.33, -hy * 0.16, -hz * 0.36), nil, Build.Shade(PINK, 0.35))
	end

	-- Ears
	local earStyle = shape.ears
	for _, side in { -1, 1 } do
		if earStyle == "Pointy" or earStyle == "Big" then
			local s = if earStyle == "Big" then 0.75 else 0.55
			local pos = Vector3.new(side * hx * 0.3, hy * 0.36, -hz * 0.02)
			local tilt = CFrame.Angles(0, 0, side * -0.2) * CFrame.Angles(0, 0, math.rad(45))
			b:add("Head", "Ear", "Block", Vector3.new(s, s, 0.16), pos, tilt, c.ears)
			b:add("Head", "EarInner", "Block", Vector3.new(s * 0.6, s * 0.6, 0.06), pos + Vector3.new(0, 0.02, -0.07), tilt, c.earInner)
		elseif earStyle == "Floppy" then
			b:add("Head", "Ear", "Ellipsoid", Vector3.new(0.35, 0.95, 0.6), Vector3.new(side * hx * 0.47, hy * 0.02, 0.05), CFrame.Angles(0, 0, side * 0.25), Build.Shade(c.ears, -0.15))
		elseif earStyle == "Long" then
			local rot = CFrame.Angles(-0.15, 0, side * -0.12)
			b:add("Head", "Ear", "Ellipsoid", Vector3.new(0.42, 1.5, 0.28), Vector3.new(side * hx * 0.2, hy * 0.85, 0.08), rot, c.ears)
			b:add("Head", "EarInner", "Ellipsoid", Vector3.new(0.24, 1.2, 0.1), Vector3.new(side * hx * 0.2, hy * 0.85, -0.02), rot, c.earInner)
		elseif earStyle == "Round" then
			b:add("Head", "Ear", "Ellipsoid", Vector3.new(0.55, 0.55, 0.3), Vector3.new(side * hx * 0.36, hy * 0.38, 0.05), nil, c.ears)
		end
	end

	-- Tail
	local tail = shape.tail
	if tail == "Long" then
		b:add("Tail", "Tail", "Ellipsoid", Vector3.new(0.3, 0.3, 1.2), Vector3.new(0, 0.3, 0.45), CFrame.Angles(math.rad(-50), 0, 0), c.tail)
		b:add("Tail", "TailTip", "Ellipsoid", Vector3.new(0.28, 0.28, 0.95), Vector3.new(0, 1.0, 0.8), CFrame.Angles(math.rad(-80), 0, 0), if pet.pattern == "Tabby" then c.accent else c.tail)
	elseif tail == "Wag" then
		b:add("Tail", "Tail", "Ellipsoid", Vector3.new(0.3, 0.3, 1.1), Vector3.new(0, 0.35, 0.35), CFrame.Angles(math.rad(-55), 0, 0), c.tail)
	elseif tail == "Puff" then
		b:add("Tail", "Tail", "Ellipsoid", Vector3.new(0.65, 0.65, 0.6), Vector3.new(0, 0, 0.1), nil, WHITE)
	elseif tail == "Bushy" then
		b:add("Tail", "Tail", "Ellipsoid", Vector3.new(0.75, 0.75, 1.7), Vector3.new(0, 0.2, 0.75), CFrame.Angles(math.rad(-25), 0, 0), c.tail)
		b:add("Tail", "TailTip", "Ellipsoid", Vector3.new(0.6, 0.6, 0.6), Vector3.new(0, 0.6, 1.5), CFrame.Angles(math.rad(-25), 0, 0), WHITE)
	elseif tail == "Stub" then
		b:add("Tail", "Tail", "Ellipsoid", Vector3.new(0.45, 0.45, 0.4), Vector3.new(0, 0, 0.05), nil, c.tail)
	end

	return model
end

-- Uses a replacement model from ReplicatedStorage.Assets.Pets if one exists
-- for this species, tinting parts named Coat / Accent / Eye.
function PetModels.Create(pet: any): Model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Pets")
	local custom = folder and folder:FindFirstChild(pet.species)
	if custom and custom:IsA("Model") and custom.PrimaryPart then
		local model = custom:Clone()
		local coat = Config.Colors[pet.color] or Config.Colors.Orange
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				if p.Name == "Coat" then
					p.Color = coat
				elseif p.Name == "Accent" then
					p.Color = Build.Shade(coat, -0.35)
				elseif p.Name == "Eye" then
					p.Color = Config.EyeColors[pet.eyes] or p.Color
				end
			end
		end
		model.Name = pet.name or pet.species
		return model
	end
	return PetModels.Build(pet)
end

return PetModels
