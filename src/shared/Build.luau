-- Tiny helpers for building models out of parts.

local Build = {}

export type PartSpec = {
	Name: string?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Shape: string?, -- "Block" (default), "Ellipsoid", "Cylinder" (axis along Y), "Ball", "Wedge"
	Transparency: number?,
	Parent: Instance,
}

function Build.Part(spec: PartSpec): BasePart
	local part: BasePart
	if spec.Shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
	end
	part.Name = spec.Name or "Part"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = spec.Material or Enum.Material.SmoothPlastic
	part.Color = spec.Color
	part.Transparency = spec.Transparency or 0
	local cf = spec.CFrame
	if spec.Shape == "Ellipsoid" then
		part.Size = spec.Size
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	elseif spec.Shape == "Cylinder" then
		-- Roblox cylinders run along X; stand them up so Size.Y is the height.
		local p = part :: Part
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(spec.Size.Y, spec.Size.X, spec.Size.Z)
		cf = cf * CFrame.Angles(0, 0, math.pi / 2)
	elseif spec.Shape == "Ball" then
		local p = part :: Part
		p.Shape = Enum.PartType.Ball
		p.Size = spec.Size
	else
		part.Size = spec.Size
	end
	part.CFrame = cf
	part.Parent = spec.Parent
	return part
end

-- Darker / lighter versions of a colour.
function Build.Shade(c: Color3, amount: number): Color3
	if amount < 0 then
		return c:Lerp(Color3.new(0, 0, 0), -amount)
	end
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

return Build
