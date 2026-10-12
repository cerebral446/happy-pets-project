-- Small deterministic random number generator (xorshift32).
-- Unlike Roblox's Random, it gives identical results everywhere (server,
-- client, tests), so adoption lists and breeding results are reproducible
-- from a stored seed.

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { s: number }, Rng))

local TWO32 = 4294967296

-- FNV-1a hash of any mix of strings and numbers, as a 32-bit seed.
function Rng.Hash(...: any): number
	local h = 2166136261
	for i = 1, select("#", ...) do
		local text = tostring((select(i, ...)))
		for c = 1, #text do
			h = bit32.bxor(h, string.byte(text, c))
			-- h * 16777619 mod 2^32, split so it stays exact in a double.
			h = (bit32.lshift(h, 24) + h * 403) % TWO32
		end
		h = bit32.bxor(h, 0x2C)
	end
	return h
end

function Rng.new(seed: number): Rng
	local s = math.floor(seed) % TWO32
	if s == 0 then
		s = 0x9E3779B9
	end
	return setmetatable({ s = s }, Rng)
end

function Rng.NextInt(self: Rng): number
	local x = self.s
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.s = x
	return x
end

-- Uniform float in [0, 1).
function Rng.Float(self: Rng): number
	return self:NextInt() / TWO32
end

-- Uniform integer in [a, b].
function Rng.Range(self: Rng, a: number, b: number): number
	return a + self:NextInt() % (b - a + 1)
end

function Rng.Pick<T>(self: Rng, list: { T }): T
	return list[self:Range(1, #list)]
end

function Rng.Chance(self: Rng, p: number): boolean
	return self:Float() < p
end

return Rng
