-- Smoke test: builds every pet look and every furniture item with Lune's
-- Roblox instance library, which rejects unknown classes and properties.
-- Run from the happy-pets folder with:  lune run tests/models

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any
local process = require("@lune/process")

local game = roblox.Instance.new("DataModel")
local cache = {}

local function loadModule(name: string): any
	if cache[name] ~= nil then
		return cache[name]
	end
	local parent = setmetatable({}, { __index = function(_, child) return { __module = child } end })
	local env = setmetatable({
		script = { Parent = parent, Name = name },
		require = function(target) return loadModule(target.__module) end,
		game = game,
		Instance = roblox.Instance,
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		UDim2 = roblox.UDim2,
		UDim = roblox.UDim,
		Enum = roblox.Enum,
	}, { __index = _G })
	local result = luau.load(fs.readFile("src/shared/" .. name .. ".luau"), { debugName = name, environment = env })()
	cache[name] = result
	return result
end

local Config = loadModule("Config")
local PetModels = loadModule("PetModels")
local FurnitureModels = loadModule("FurnitureModels")

local failures = 0
local built = 0
local function try(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		built += 1
	else
		failures += 1
		print("FAIL " .. label .. ": " .. tostring(err))
	end
end

for species, def in Config.Species do
	local patterns = table.clone(def.Patterns)
	for _, p in def.RarePatterns do
		table.insert(patterns, p)
	end
	for _, pattern in patterns do
		for _, stage in { "Adult", "Baby" } do
			try(species .. " " .. pattern .. " " .. stage, function()
				local m = PetModels.Build({ species = species, color = def.Colors[1], pattern = pattern, eyes = def.Eyes[1], stage = stage, name = "Test" })
				assert(m.PrimaryPart and m.PrimaryPart.Name == "Root", "missing root")
				local groups = {}
				for _, p in m:GetChildren() do
					local g = p:GetAttribute("Group")
					if g then
						groups[g] = true
						assert(typeof(p:GetAttribute("Rest")) == "CFrame", "missing rest")
						assert(typeof(m:GetAttribute("Joint_" .. g)) == "CFrame", "missing joint " .. g)
					end
				end
				for _, g in { "Body", "Head", "Tail", "LegFL", "LegFR", "LegBL", "LegBR" } do
					assert(groups[g], "no parts in group " .. g)
				end
			end)
		end
	end
end

for itemId, item in Config.Items do
	if item.Kind == "Furniture" then
		try(itemId, function()
			local m = FurnitureModels.Create(itemId)
			assert(#m:GetChildren() > 0, "empty model")
		end)
	end
end

print(string.format("%d models built, %d failed", built, failures))
if failures > 0 then
	process.exit(1)
end
