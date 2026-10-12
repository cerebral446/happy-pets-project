-- Pet game rules: creating pets, needs over time, care effects, growing up,
-- coat inheritance and the adoption centre's daily selection.
-- Pure functions (no Roblox APIs) so they're shared and unit-tested.

local Config = require(script.Parent.Config)
local Rng = require(script.Parent.Rng)

local PetRules = {}

export type Look = { color: string, pattern: string, eyes: string }

local function contains(list: { string }, value: string): boolean
	return table.find(list, value) ~= nil
end

local function clampNeed(v: number): number
	return math.clamp(v, 0, 100)
end

function PetRules.NewPet(id: string, species: string, look: Look, name: string, gender: string, stage: string, now: number, roomId: string): any
	return {
		id = id,
		name = name,
		gender = gender,
		species = species,
		color = look.color,
		pattern = look.pattern,
		eyes = look.eyes,
		stage = stage,
		bornAt = now,
		careCount = 0,
		room = roomId,
		x = 0,
		z = 2,
		needs = { Food = 80, Fun = 80, Energy = 90, Clean = 90, Health = 100 },
		sleeping = false,
		lastBredAt = 0,
		lastGiftAt = now,
		cooldowns = {},
		parents = nil,
	}
end

function PetRules.Mood(pet: any): number
	local n = pet.needs
	-- Health counts double: a poorly pet is never "ecstatic".
	return (n.Food + n.Fun + n.Energy + n.Clean + n.Health * 2) / 6
end

function PetRules.MoodLabel(mood: number): (string, string)
	if mood >= 85 then
		return "Ecstatic", "😻"
	elseif mood >= 65 then
		return "Happy", "😊"
	elseif mood >= 45 then
		return "Okay", "🙂"
	elseif mood >= 25 then
		return "Sad", "😢"
	end
	return "Miserable", "😿"
end

-- The need that most wants attention, if any is low.
function PetRules.LowestNeed(pet: any, threshold: number?): string?
	local limit = threshold or 35
	local worst, worstValue = nil, limit
	for _, need in Config.Needs do
		local v = pet.needs[need]
		if v < worstValue then
			worst, worstValue = need, v
		end
	end
	return worst
end

export type Env = { comfort: number, litter: boolean, hasBed: boolean }

-- Advances one pet's needs by dt seconds. Long gaps are simulated in
-- one-minute steps so sleeping and waking happen at the right moments.
-- Returns true if the pet fell asleep or woke up.
function PetRules.Simulate(pet: any, dt: number, env: Env): boolean
	if dt <= 0 then
		return false
	end
	local d = Config.Decay
	local changed = false
	local comfort = math.clamp(env.comfort, 0, d.ComfortCap) / d.ComfortCap
	local funFactor = 1 - d.ComfortMaxSlowdown * comfort
	local cleanFactor = if env.litter then d.LitterFactor else 1
	local remaining = dt
	while remaining > 0 do
		local step = math.min(remaining, 60)
		remaining -= step
		local minutes = step / 60
		local n = pet.needs
		local sleepFactor = if pet.sleeping then d.SleepingFactor else 1
		n.Food = clampNeed(n.Food - d.Food * minutes * sleepFactor)
		n.Fun = clampNeed(n.Fun - d.Fun * minutes * sleepFactor * funFactor)
		n.Clean = clampNeed(n.Clean - d.Clean * minutes * sleepFactor * cleanFactor)
		if pet.sleeping then
			local rate = if env.hasBed then d.EnergySleepBed else d.EnergySleep
			n.Energy = clampNeed(n.Energy + rate * minutes)
			if n.Energy >= 100 then
				pet.sleeping = false
				changed = true
			end
		else
			n.Energy = clampNeed(n.Energy - d.EnergyAwake * minutes)
			if n.Energy <= d.AutoSleepAt then
				pet.sleeping = true
				changed = true
			end
		end
		local low = n.Food < d.LowThreshold or n.Clean < d.LowThreshold or n.Fun < d.LowThreshold
		if low then
			n.Health = math.max(d.HealthMin, n.Health - d.HealthLoss * minutes)
		else
			n.Health = clampNeed(n.Health + d.HealthGain * minutes)
		end
	end
	return changed
end

function PetRules.ApplyEffects(pet: any, effects: { [string]: number })
	for need, amount in effects do
		if pet.needs[need] ~= nil then
			pet.needs[need] = clampNeed(pet.needs[need] + amount)
		end
	end
	-- Eating, bathing and playing keep health up a little too.
	if (effects.Food or 0) > 0 or (effects.Clean or 0) > 0 then
		pet.needs.Health = clampNeed(pet.needs.Health + 2)
	end
end

-- Babies grow up with time or with enough care. Returns true when it happens.
function PetRules.Grow(pet: any, now: number): boolean
	if pet.stage ~= "Baby" then
		return false
	end
	if now - pet.bornAt >= Config.Growth.AdultAfterSeconds or pet.careCount >= Config.Growth.AdultAfterCare then
		pet.stage = "Adult"
		return true
	end
	return false
end

function PetRules.DisplaySpecies(pet: any): string
	local def = Config.Species[pet.species]
	if not def then
		return pet.species
	end
	return if pet.stage == "Baby" then def.Baby else def.Name
end

-- Can the cooldown-limited care action run now? Returns seconds left if not.
function PetRules.CooldownLeft(pet: any, action: string, now: number): number
	local care = Config.Care[action]
	if not care or not care.Cooldown then
		return 0
	end
	local last = pet.cooldowns[action] or 0
	return math.max(0, last + care.Cooldown - now)
end

---------------------------------------------------------------------------
-- Rarity and adoption
---------------------------------------------------------------------------

function PetRules.Rarity(species: string, look: Look): string
	local def = Config.Species[species]
	if not def then
		return "Common"
	end
	if contains(def.RareColors, look.color) or contains(def.RarePatterns, look.pattern) or contains(def.RareEyes, look.eyes) then
		return "Rare"
	end
	return "Common"
end

function PetRules.AdoptPrice(species: string, look: Look): number
	local def = Config.Species[species]
	local price = def.Price
	if PetRules.Rarity(species, look) == "Rare" then
		price *= Config.Adoption.RareMultiplier
	end
	return price
end

local function randomLook(rng: Rng.Rng, species: string, rareChance: number): Look
	local def = Config.Species[species]
	local function pick(common: { string }, rare: { string }): string
		if #rare > 0 and rng:Chance(rareChance) then
			return rng:Pick(rare)
		end
		return rng:Pick(common)
	end
	return {
		color = pick(def.Colors, def.RareColors),
		pattern = pick(def.Patterns, def.RarePatterns),
		eyes = pick(def.Eyes, def.RareEyes),
	}
end

-- The adoption centre's pets for one species. The same seed always gives
-- the same list, so the server can re-derive what the player picked.
function PetRules.AdoptionCandidates(seed: number, species: string): { any }
	local rng = Rng.new(Rng.Hash(seed, species))
	local list = {}
	for i = 1, Config.Adoption.PerSpecies do
		local look = randomLook(rng, species, if i == Config.Adoption.PerSpecies then 0.5 else 0.12)
		table.insert(list, {
			index = i,
			species = species,
			look = look,
			rarity = PetRules.Rarity(species, look),
			price = PetRules.AdoptPrice(species, look),
		})
	end
	return list
end

function PetRules.AdoptionSeed(userId: number, day: number, rerolls: number): number
	return Rng.Hash("adopt", userId, day, rerolls)
end

---------------------------------------------------------------------------
-- Breeding
---------------------------------------------------------------------------

function PetRules.CanBreed(a: any, b: any, now: number): (boolean, string?)
	if not a or not b then
		return false, "Pick two pets."
	end
	if a.id == b.id then
		return false, "Pick two different pets."
	end
	if a.species ~= b.species then
		return false, "Both parents must be the same species."
	end
	if a.gender == b.gender then
		return false, "You need a boy and a girl."
	end
	if a.stage ~= "Adult" or b.stage ~= "Adult" then
		return false, "Both parents must be grown up."
	end
	for _, p in { a, b } do
		if now - (p.lastBredAt or 0) < Config.Breeding.Cooldown then
			return false, p.name .. " needs a rest before having more babies."
		end
		if PetRules.Mood(p) < Config.Breeding.MinMood then
			return false, p.name .. " isn't happy enough right now."
		end
	end
	return true, nil
end

-- The baby's look, decided by the stored seed. Each trait comes from one of
-- the parents, with a small chance of a different (sometimes rare) trait.
function PetRules.Inherit(a: any, b: any, seed: number): Look
	local def = Config.Species[a.species]
	local rng = Rng.new(seed)
	local cfg = Config.Breeding
	local function trait(fromA: string, fromB: string, mutation: number, common: { string }, rare: { string }): string
		local roll = rng:Float()
		if roll < mutation then
			-- A third of mutations are rare traits.
			if #rare > 0 and rng:Chance(0.35) then
				return rng:Pick(rare)
			end
			return rng:Pick(common)
		end
		return if rng:Chance(0.5) then fromA else fromB
	end
	return {
		color = trait(a.color, b.color, cfg.ColorMutation, def.Colors, def.RareColors),
		pattern = trait(a.pattern, b.pattern, cfg.PatternMutation, def.Patterns, def.RarePatterns),
		eyes = trait(a.eyes, b.eyes, cfg.EyeMutation, def.Eyes, def.RareEyes),
	}
end

-- Names: trimmed, 1-20 characters, letters/numbers/spaces and a little punctuation.
function PetRules.CleanName(name: any): string?
	if typeof(name) ~= "string" then
		return nil
	end
	local trimmed = string.gsub(string.gsub(name, "^%s+", ""), "%s+$", "")
	trimmed = string.gsub(trimmed, "%s+", " ")
	if #trimmed < 1 or utf8.len(trimmed) == nil or (utf8.len(trimmed) :: number) > 20 then
		return nil
	end
	if string.find(trimmed, "[^%w %-'%.!]") then
		return nil
	end
	return trimmed
end

return PetRules
