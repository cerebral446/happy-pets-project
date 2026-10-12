-- Background music and pet voices.
--
-- Music: a shuffled playlist that fades between tracks (or loops a single
-- track). Pet voices: each species has its own sounds for greeting, being
-- loved, playing, eating, feeling sad and sleeping, played from the pet's
-- position so pets in the next room sound further away.
--
-- Sounds come from Config.Audio (asset ids) and/or Sound objects placed in
-- ReplicatedStorage.Assets.Audio. Anything missing simply stays silent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local State = require(script.Parent:WaitForChild("State"))

local Audio = {}

local musicOn = true
local sfxOn = true

local function assetsFolder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Audio")
end

-- A sound "source" is either an asset id string or a Sound to clone.
type Source = string | Sound

local function soundsIn(inst: Instance?): { Sound }
	local list = {}
	if not inst then
		return list
	end
	if inst:IsA("Sound") then
		table.insert(list, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("Sound") then
			table.insert(list, d)
		end
	end
	return list
end

local function validId(id: any): boolean
	return typeof(id) == "string" and string.match(id, "%d%d%d") ~= nil
end

local function makeSound(source: Source, parent: Instance, volume: number): Sound
	local s: Sound
	if typeof(source) == "string" then
		s = Instance.new("Sound")
		s.SoundId = source
	else
		s = (source :: Sound):Clone()
	end
	-- Toolbox sounds default to 0.5 volume; treat that as "normal".
	s.Volume = volume * (if typeof(source) == "string" then 1 else (source :: Sound).Volume * 2)
	s.Parent = parent
	return s
end

---------------------------------------------------------------------------
-- Music
---------------------------------------------------------------------------

local playlist: { Source } = {}
local order: { number } = {}
local position = 0
local current: Sound? = nil
local musicFolder: Folder

local function buildPlaylist()
	playlist = {}
	for _, id in Config.Audio.Music do
		if validId(id) then
			table.insert(playlist, id)
		end
	end
	local folder = assetsFolder()
	for _, s in soundsIn(folder and folder:FindFirstChild("Music")) do
		table.insert(playlist, s)
	end
end

local function shuffle()
	order = {}
	for i = 1, #playlist do
		table.insert(order, i)
	end
	for i = #order, 2, -1 do
		local j = math.random(1, i)
		order[i], order[j] = order[j], order[i]
	end
	position = 0
end

local function fadeOut(s: Sound)
	local tween = TweenService:Create(s, TweenInfo.new(Config.Audio.MusicFade), { Volume = 0 })
	tween.Completed:Connect(function()
		s:Destroy()
	end)
	tween:Play()
end

local playNext: () -> ()

function playNext()
	if not musicOn or #playlist == 0 then
		return
	end
	position += 1
	if position > #order then
		local last = order[#order]
		shuffle()
		-- Don't repeat the track that just finished.
		if #order > 1 and order[1] == last then
			order[1], order[2] = order[2], order[1]
		end
		position = 1
	end
	if current then
		fadeOut(current)
	end
	local s = makeSound(playlist[order[position]], musicFolder, 0)
	s.Name = "Music"
	s.Looped = #playlist == 1
	current = s
	s.Ended:Connect(function()
		if current == s then
			playNext()
		end
	end)
	s:Play()
	TweenService:Create(s, TweenInfo.new(Config.Audio.MusicFade), { Volume = Config.Audio.MusicVolume }):Play()
end

function Audio.SetMusic(on: boolean)
	if on == musicOn and (current ~= nil) == on then
		return
	end
	musicOn = on
	if on then
		if not current then
			playNext()
		end
	elseif current then
		fadeOut(current)
		current = nil
	end
end

function Audio.HasMusic(): boolean
	return #playlist > 0
end

---------------------------------------------------------------------------
-- Pet voices
---------------------------------------------------------------------------

local lastVoice: { [Model]: number } = {}

local function petSources(species: string, kind: string): { Source }
	local list: { Source } = {}
	local cfg = Config.Audio.Pets[species]
	if cfg and cfg[kind] then
		for _, id in cfg[kind] do
			if validId(id) then
				table.insert(list, id)
			end
		end
	end
	local folder = assetsFolder()
	local speciesFolder = folder and folder:FindFirstChild(species)
	for _, s in soundsIn(speciesFolder and speciesFolder:FindFirstChild(kind)) do
		table.insert(list, s)
	end
	return list
end

-- Plays one of the species' sounds of this kind from the pet. `volume` scales
-- the configured pet volume (e.g. quieter snores).
function Audio.PetSound(model: Model, kind: string, volume: number?)
	if not sfxOn or not model.Parent then
		return
	end
	-- Don't let one pet chatter over itself.
	local now = os.clock()
	if now - (lastVoice[model] or 0) < 0.9 then
		return
	end
	local species = model:GetAttribute("Species") :: string?
	if not species then
		return
	end
	local sources = petSources(species, kind)
	if #sources == 0 and kind ~= "Greet" then
		sources = petSources(species, "Greet")
	end
	if #sources == 0 then
		return
	end
	lastVoice[model] = now
	local root = model.PrimaryPart
	if not root then
		return
	end
	local s = makeSound(sources[math.random(1, #sources)], root, Config.Audio.PetVolume * (volume or 1))
	s.Looped = false
	-- Full volume anywhere in the room on screen, fading out next door.
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 45
	s.RollOffMaxDistance = 120
	local pitch = 0.93 + math.random() * 0.14
	if model:GetAttribute("Stage") == "Baby" then
		pitch *= Config.Audio.BabyPitch
	end
	s.PlaybackSpeed = pitch
	s.Ended:Connect(function()
		s:Destroy()
	end)
	s:Play()
	task.delay(12, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

function Audio.Init()
	musicFolder = Instance.new("Folder")
	musicFolder.Name = "HappyPetsMusic"
	musicFolder.Parent = SoundService
	buildPlaylist()
	shuffle()

	local function applySettings(p: any)
		local settings = p and p.settings or {}
		sfxOn = settings.sound ~= false
		Audio.SetMusic(settings.music ~= false)
	end
	State.ProfileChanged:Connect(applySettings)
	applySettings(State.Profile)

	-- Sounds added to Assets.Audio while playing (e.g. in Studio) join in.
	local folder = assetsFolder()
	if folder then
		folder.DescendantAdded:Connect(function(d)
			if d:IsA("Sound") then
				buildPlaylist()
				shuffle()
				if musicOn and not current then
					playNext()
				end
			end
		end)
	end
end

return Audio
