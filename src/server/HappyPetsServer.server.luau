-- Happy Pets: main server script.
-- Loads each player's save, builds their home and pets, runs the needs
-- simulation, answers requests from the client and autosaves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local SaveSchema = require(Shared:WaitForChild("SaveSchema"))
local PetRules = require(Shared:WaitForChild("PetRules"))

-- Networking objects must exist before the client looks for them.
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local requestRemote = Instance.new("RemoteFunction")
requestRemote.Name = "Request"
requestRemote.Parent = remotes
local notifyRemote = Instance.new("RemoteEvent")
notifyRemote.Name = "Notify"
notifyRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

local Plots = require(script.Parent:WaitForChild("Plots"))
local PetService = require(script.Parent:WaitForChild("PetService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local Actions = require(script.Parent:WaitForChild("Actions"))

-- No avatars: the game is played with the mouse or touch from a fixed camera.
Players.CharacterAutoLoads = false

-- Soft, sunny lighting.
Lighting.ClockTime = 14.5
Lighting.Brightness = 2.2
Lighting.Ambient = Color3.fromRGB(150, 140, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(170, 165, 175)
Lighting.EnvironmentDiffuseScale = 0.5
Lighting.EnvironmentSpecularScale = 0.3
Lighting.GlobalShadows = true
do
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.12
	cc.Contrast = 0.05
	cc.TintColor = Color3.fromRGB(255, 250, 245)
	cc.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.4
	bloom.Size = 20
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.CelestialBodiesShown = false
	sky.Parent = Lighting
	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.25
	atmo.Color = Color3.fromRGB(220, 230, 255)
	atmo.Decay = Color3.fromRGB(250, 220, 230)
	atmo.Haze = 1
	atmo.Parent = Lighting
end

Plots.Init()

type Session = Actions.Session & { lastTick: number, lastSave: number, lastRequest: number, saving: boolean, profileSent: string? }

local sessions: { [Player]: Session } = {}

local function sessionByUserId(userId: number): Session?
	for player, s in sessions do
		if player.UserId == userId then
			return s
		end
	end
	return nil
end

local function notify(player: Player, message: any)
	if player.Parent then
		notifyRemote:FireClient(player, message)
	end
end

-- What the client sees of its own save. Everything except visit bookkeeping.
local function clientView(s: Session): string
	local d = s.data
	return HttpService:JSONEncode({
		coins = d.coins,
		xp = d.xp,
		level = d.level,
		xpNext = Config.XPToNext(d.level),
		pets = d.pets,
		inventory = d.inventory,
		rooms = d.rooms,
		styles = d.styles,
		births = d.births,
		settings = d.settings,
		stats = d.stats,
		starterDone = d.starterDone,
		dailyReady = d.daily.day ~= Economy.DayIndex(os.time()),
		capacity = Economy.PetCapacity(d),
		petCount = Economy.PetCount(d),
		online = s.online,
		plot = s.plot.Name,
	})
end

local function pushProfile(s: Session)
	local json = clientView(s)
	if json ~= s.profileSent then
		s.profileSent = json
		s.player:SetAttribute("Profile", json)
	end
	s.player:SetAttribute("Coins", s.data.coins)
	s.player:SetAttribute("Level", s.data.level)
end

local function save(s: Session, release: boolean)
	if not s.online then
		s.player:SetAttribute("SaveStatus", "Offline")
		return
	end
	if s.saving and not release then
		return
	end
	s.saving = true
	s.player:SetAttribute("SaveStatus", "Saving")
	local ok = DataService.Save(s.player, s.data, release)
	s.saving = false
	s.lastSave = os.clock()
	if s.player.Parent then
		s.player:SetAttribute("SaveStatus", if ok then "Saved" else "Error")
	end
end

-- Simulates the time a player was away (capped) before their pets appear.
local function catchUp(s: Session)
	local now = os.time()
	local away = math.clamp(now - s.data.lastSeen, 0, Config.MaxOfflineHours * 3600)
	if away > 0 then
		for _, pet in s.data.pets do
			PetRules.Simulate(pet, away, PetService.RoomEnv(s.data, pet.room))
			PetRules.Grow(pet, now)
		end
	end
	s.data.lastSeen = now
	s.lastTick = now
end

local function resetSession(s: any)
	(s.plot:FindFirstChild("Pets") :: Folder):ClearAllChildren()
	DataService.Reset(s.player)
	s.data = SaveSchema.Default(os.time())
	Plots.Rebuild(s.plot, s.data)
	s.dirty = true
	pushProfile(s)
	save(s, false)
	notify(s.player, { kind = "reset" })
end

Actions.Init(notify, sessionByUserId, resetSession)

local function onPlayerAdded(player: Player)
	player:SetAttribute("SaveStatus", "Loading")
	local data, online = DataService.Load(player)
	if not player.Parent then
		if online then
			DataService.Save(player, data, true)
		end
		return
	end
	local s: Session = {
		player = player,
		data = data,
		plot = nil :: any,
		online = online,
		dirty = false,
		busy = false,
		lastTick = os.time(),
		lastSave = os.clock(),
		lastRequest = 0,
		saving = false,
		profileSent = nil,
	}
	catchUp(s)
	s.plot = Plots.Create(player, data)
	PetService.SpawnAll(s.plot, data)
	sessions[player] = s
	player:SetAttribute("Plot", s.plot.Name)
	player:SetAttribute("SaveStatus", if online then "Saved" else "Offline")
	pushProfile(s)
	if online then
		task.spawn(save, s, false)
	end
end

local function onPlayerRemoving(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	sessions[player] = nil
	save(s, true)
	Plots.Destroy(s.plot)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	local pending = 0
	for player, s in sessions do
		pending += 1
		task.spawn(function()
			save(s, true)
			pending -= 1
		end)
	end
	local start = os.clock()
	while pending > 0 and os.clock() - start < 25 do
		task.wait(0.2)
	end
end)

---------------------------------------------------------------------------
-- Requests
---------------------------------------------------------------------------

local HANDLERS = {
	GetAdoption = Actions.GetAdoption,
	RerollAdoption = Actions.RerollAdoption,
	Adopt = Actions.Adopt,
	Care = Actions.Care,
	CollectGift = Actions.CollectGift,
	Rename = Actions.Rename,
	MovePet = Actions.MovePet,
	Buy = Actions.Buy,
	BuyStyle = Actions.BuyStyle,
	SetStyle = Actions.SetStyle,
	UnlockRoom = Actions.UnlockRoom,
	Place = Actions.Place,
	MoveFurniture = Actions.MoveFurniture,
	StoreFurniture = Actions.StoreFurniture,
	Breed = Actions.Breed,
	ClaimBirth = Actions.ClaimBirth,
	ClaimDaily = Actions.ClaimDaily,
	VisitPet = Actions.VisitPet,
	SetSetting = Actions.SetSetting,
	ResetSave = Actions.ResetSave,
}

requestRemote.OnServerInvoke = function(player: Player, name: any, payload: any)
	local s = sessions[player]
	if not s then
		return { ok = false, msg = "Still loading your home..." }
	end
	local handler = typeof(name) == "string" and HANDLERS[name]
	if not handler then
		return { ok = false, msg = "Unknown request." }
	end
	if typeof(payload) ~= "table" then
		payload = {}
	end
	-- One request at a time per player stops double purchases.
	if s.busy or os.clock() - s.lastRequest < 0.08 then
		return { ok = false, msg = "One moment..." }
	end
	s.busy = true
	s.lastRequest = os.clock()
	local ok, result = pcall(handler, s, payload)
	s.busy = false
	if not ok then
		warn("[HappyPets] Request", name, "failed:", result)
		return { ok = false, msg = "Something went wrong. Please try again." }
	end
	if s.dirty then
		pushProfile(s)
	end
	return result
end

---------------------------------------------------------------------------
-- Simulation and autosave
---------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(Config.TickSeconds)
		local now = os.time()
		for _, s in sessions do
			local dt = now - s.lastTick
			if dt > 0 then
				s.lastTick = now
				s.data.lastSeen = now
				PetService.Tick(s.plot, s.data, dt, now)
				s.dirty = true
			end
			if s.dirty then
				s.dirty = false
				pushProfile(s)
			end
			if s.online and not s.saving and os.clock() - s.lastSave >= Config.AutosaveSeconds then
				task.spawn(save, s, false)
			end
		end
	end
end)
