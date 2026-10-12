-- Furniture placement on a room's floor grid. Pure functions shared by the
-- server (which validates every move) and the client (which tints the preview
-- green or red as you drag).
--
-- A room is Cols x Rows cells. Cell (0, 0) is the back-left corner; columns
-- run left to right (+X) and rows run back to front (+Z, toward the camera).
-- An item's (cx, cz) is the cell under its back-left corner.

local Config = require(script.Parent.Config)

local Placement = {}

Placement.Cols = Config.Room.Width // Config.Room.Cell
Placement.Rows = Config.Room.Depth // Config.Room.Cell

-- Footprint in cells after rotating by rot * 90 degrees.
function Placement.Footprint(itemId: string, rot: number): (number, number)
	local item = Config.Items[itemId]
	local w, d = item.Footprint[1], item.Footprint[2]
	if rot % 2 == 1 then
		return d, w
	end
	return w, d
end

function Placement.Layer(itemId: string): string
	return Config.Items[itemId].Layer or "Object"
end

-- Room-local stud position of an item's centre (floor level).
function Placement.CellToLocal(itemId: string, cx: number, cz: number, rot: number): (number, number)
	local w, d = Placement.Footprint(itemId, rot)
	local cell = Config.Room.Cell
	local x = -Config.Room.Width / 2 + (cx + w / 2) * cell
	local z = -Config.Room.Depth / 2 + (cz + d / 2) * cell
	return x, z
end

-- Nearest cell for an item centred at room-local (x, z), clamped into the room.
function Placement.LocalToCell(itemId: string, x: number, z: number, rot: number): (number, number)
	local w, d = Placement.Footprint(itemId, rot)
	local cell = Config.Room.Cell
	local cx = math.floor((x + Config.Room.Width / 2) / cell - w / 2 + 0.5)
	local cz = math.floor((z + Config.Room.Depth / 2) / cell - d / 2 + 0.5)
	cx = math.clamp(cx, 0, Placement.Cols - w)
	cz = math.clamp(cz, 0, Placement.Rows - d)
	return cx, cz
end

local function overlaps(ax, az, aw, ad, bx, bz, bw, bd): boolean
	return ax < bx + bw and bx < ax + aw and az < bz + bd and bz < az + ad
end

-- Checks that an item fits at (cx, cz, rot) among the room's other furniture.
-- ignoreUid skips the item being moved.
function Placement.Validate(furniture: { any }, itemId: string, cx: number, cz: number, rot: number, ignoreUid: string?): (boolean, string?)
	local item = Config.Items[itemId]
	if not item or item.Kind ~= "Furniture" then
		return false, "That item can't be placed."
	end
	if typeof(cx) ~= "number" or typeof(cz) ~= "number" or cx ~= math.floor(cx) or cz ~= math.floor(cz) then
		return false, "Invalid position."
	end
	if rot ~= 0 and rot ~= 1 and rot ~= 2 and rot ~= 3 then
		return false, "Invalid rotation."
	end
	local w, d = Placement.Footprint(itemId, rot)
	if cx < 0 or cz < 0 or cx + w > Placement.Cols or cz + d > Placement.Rows then
		return false, "It doesn't fit there."
	end
	local layer = Placement.Layer(itemId)
	for _, f in furniture do
		if f.uid ~= ignoreUid and Config.Items[f.item] and Placement.Layer(f.item) == layer then
			local fw, fd = Placement.Footprint(f.item, f.rot)
			if overlaps(cx, cz, w, d, f.cx, f.cz, fw, fd) then
				return false, "Something is already there."
			end
		end
	end
	return true, nil
end

-- First free spot, scanning from the back of the room. Returns nil if full.
function Placement.FindFreeSpot(furniture: { any }, itemId: string): (number?, number?, number?)
	for _, rot in { 0, 1 } do
		local w, d = Placement.Footprint(itemId, rot)
		for cz = 0, Placement.Rows - d do
			for cx = 0, Placement.Cols - w do
				if Placement.Validate(furniture, itemId, cx, cz, rot) then
					return cx, cz, rot
				end
			end
		end
	end
	return nil, nil, nil
end

-- Total comfort of a room's furniture (decorations keep pets happy longer).
function Placement.Comfort(furniture: { any }): number
	local total = 0
	for _, f in furniture do
		local item = Config.Items[f.item]
		if item then
			total += item.Comfort or 0
		end
	end
	return total
end

function Placement.HasRole(furniture: { any }, role: string): boolean
	for _, f in furniture do
		local item = Config.Items[f.item]
		if item and item.Role == role then
			return true
		end
	end
	return false
end

-- Nearest furniture with the given role to room-local (x, z).
function Placement.NearestWithRole(furniture: { any }, role: string, x: number, z: number): any
	local best, bestDist = nil, math.huge
	for _, f in furniture do
		local item = Config.Items[f.item]
		if item and item.Role == role then
			local fx, fz = Placement.CellToLocal(f.item, f.cx, f.cz, f.rot)
			local dist = (fx - x) ^ 2 + (fz - z) ^ 2
			if dist < bestDist then
				best, bestDist = f, dist
			end
		end
	end
	return best
end

return Placement
