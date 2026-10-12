-- Shared tuning data for Happy Pets.
-- Everything you may want to rebalance (prices, needs, levels, species, items)
-- lives here. Prices and rates are new balancing values, not the original
-- game's formulas.

local Config = {}

Config.GameName = "Happy Pets"

-- Bump SaveVersion and add a migration in SaveSchema when the save layout changes.
Config.SaveVersion = 1
Config.DataStoreName = "HappyPetsSave_v1"
Config.AutosaveSeconds = 60
-- How often the server advances every pet's needs.
Config.TickSeconds = 5
-- Needs keep changing while you're away, up to this many hours.
Config.MaxOfflineHours = 48

---------------------------------------------------------------------------
-- Player start and progression
---------------------------------------------------------------------------

Config.Start = {
	Coins = 500,
	Inventory = { kibble = 5, tuna = 1, treat = 2, shampoo = 1 },
	-- Placed in the Living Room for new players. Cells are 2x2 studs, counted
	-- from the back-left corner of the room.
	Furniture = {
		{ item = "food_bowl", cx = 2, cz = 6, rot = 0 },
		{ item = "pet_bed", cx = 10, cz = 2, rot = 0 },
		{ item = "yarn_ball", cx = 6, cz = 7, rot = 0 },
		{ item = "rug_round", cx = 5, cz = 3, rot = 0 },
		{ item = "potted_plant", cx = 0, cz = 0, rot = 0 },
	},
}

Config.MaxLevel = 50

-- XP needed to go from `level` to `level + 1`.
function Config.XPToNext(level: number): number
	return 80 + 40 * level
end

-- Coins awarded on reaching `level`.
function Config.LevelReward(level: number): number
	return 50 + 25 * level
end

Config.Daily = { Coins = 100, PerLevel = 10, XP = 10 }

---------------------------------------------------------------------------
-- Needs
---------------------------------------------------------------------------

-- All needs are 0..100 where 100 is fully cared for.
Config.Needs = { "Food", "Fun", "Energy", "Clean", "Health" }
Config.NeedInfo = {
	Food = { Label = "Food", Icon = "🍖", Color = Color3.fromRGB(242, 160, 70), Low = "hungry" },
	Fun = { Label = "Fun", Icon = "🎾", Color = Color3.fromRGB(240, 110, 160), Low = "bored" },
	Energy = { Label = "Energy", Icon = "💤", Color = Color3.fromRGB(120, 150, 240), Low = "sleepy" },
	Clean = { Label = "Clean", Icon = "🫧", Color = Color3.fromRGB(90, 200, 220), Low = "dirty" },
	Health = { Label = "Health", Icon = "❤️", Color = Color3.fromRGB(110, 200, 110), Low = "unwell" },
}

-- Points per minute.
Config.Decay = {
	Food = 0.35,
	Fun = 0.3,
	Clean = 0.18,
	EnergyAwake = 0.25,
	EnergySleep = 2.5,
	EnergySleepBed = 4.5,
	-- Food, fun and cleanliness drop at this fraction of the rate while asleep.
	SleepingFactor = 0.5,
	-- A tired pet dozes off by itself at this energy and wakes when full.
	AutoSleepAt = 10,
	-- Health drops while any need is below LowThreshold, recovers otherwise.
	HealthLoss = 0.15,
	HealthGain = 0.3,
	LowThreshold = 25,
	-- Pets never get sicker than this, so a long break is never a disaster.
	HealthMin = 20,
	-- Each comfort point (decorations) slows fun loss, up to this many points.
	ComfortCap = 20,
	ComfortMaxSlowdown = 0.4,
	-- A litter tray in the room halves cleanliness loss.
	LitterFactor = 0.5,
}

---------------------------------------------------------------------------
-- Care actions (things you do to a pet that don't use up an item)
---------------------------------------------------------------------------

Config.Care = {
	Pet = { Cooldown = 20, Effects = { Fun = 8 }, XP = 2, Coins = 1, Duration = 2.5 },
	Play = {
		Cooldown = 40,
		Effects = { Fun = 25, Energy = -10, Clean = -4 },
		XP = 6,
		Coins = 3,
		Duration = 7,
		MinEnergy = 15,
	},
	Brush = { Cooldown = 60, Effects = { Clean = 15, Fun = 3 }, XP = 3, Coins = 1, Duration = 4 },
	-- Using an item (food, treat, shampoo, vitamins).
	Item = { XP = 5, Coins = 2, Duration = 5 },
	-- Bonus fun when a pet eats its favourite food.
	FavoriteFun = 10,
}

-- Happy pets leave a little gift (coins) to collect every so often.
Config.Gift = { Interval = 180, MinMood = 65, Coins = 5, CoinsPerLevel = 1, XP = 2 }

-- Babies grow up after this long, or after this many care actions, whichever first.
Config.Growth = { AdultAfterSeconds = 3600, AdultAfterCare = 12 }

Config.Breeding = {
	Cost = 100,
	Duration = 120, -- seconds until the baby arrives
	Cooldown = 1800, -- seconds before a parent can breed again
	MinMood = 50,
	XP = 40,
	-- Chances that the baby doesn't simply take a parent's trait.
	ColorMutation = 0.1,
	PatternMutation = 0.15,
	EyeMutation = 0.05,
	MaxPending = 3,
}

-- Petting a neighbour's pet while visiting their home.
Config.Visit = { Coins = 5, XP = 3, Fun = 10, PerDay = 20 }

Config.Adoption = { PerSpecies = 4, RerollCost = 25, XP = 25, RareMultiplier = 2 }

---------------------------------------------------------------------------
-- Species and looks
---------------------------------------------------------------------------

Config.Colors = {
	Orange = Color3.fromRGB(240, 156, 72),
	Cream = Color3.fromRGB(245, 222, 178),
	Gray = Color3.fromRGB(150, 155, 165),
	Black = Color3.fromRGB(55, 52, 58),
	White = Color3.fromRGB(250, 248, 244),
	Brown = Color3.fromRGB(150, 100, 65),
	Chocolate = Color3.fromRGB(105, 70, 50),
	Golden = Color3.fromRGB(232, 182, 92),
	Lilac = Color3.fromRGB(196, 176, 214),
	Blue = Color3.fromRGB(138, 160, 196),
	Red = Color3.fromRGB(214, 98, 50),
	Silver = Color3.fromRGB(200, 205, 215),
	Pink = Color3.fromRGB(246, 176, 200),
	Arctic = Color3.fromRGB(236, 244, 250),
	Panda = Color3.fromRGB(248, 248, 248),
	Bamboo = Color3.fromRGB(196, 214, 140),
}

Config.EyeColors = {
	Green = Color3.fromRGB(90, 180, 90),
	Blue = Color3.fromRGB(80, 150, 230),
	Amber = Color3.fromRGB(230, 160, 40),
	Brown = Color3.fromRGB(110, 70, 40),
	Violet = Color3.fromRGB(160, 100, 220),
}

-- Order is the order shown in the adoption centre.
Config.SpeciesOrder = { "Cat", "Dog", "Bunny", "Fox", "Panda" }

Config.Species = {
	Cat = {
		Name = "Cat",
		Baby = "Kitten",
		Level = 1,
		Price = 200,
		Colors = { "Orange", "Cream", "Gray", "Black", "White", "Brown" },
		RareColors = { "Lilac", "Silver" },
		Patterns = { "Solid", "Tabby", "Tuxedo", "Socks" },
		RarePatterns = { "Calico", "Points" },
		Eyes = { "Green", "Amber", "Blue" },
		RareEyes = { "Violet" },
		Favorite = "tuna",
		Scale = 1,
	},
	Dog = {
		Name = "Dog",
		Baby = "Puppy",
		Level = 2,
		Price = 250,
		Colors = { "Golden", "Brown", "Black", "Cream", "White", "Chocolate" },
		RareColors = { "Blue", "Red" },
		Patterns = { "Solid", "Socks", "Spotted", "Tuxedo" },
		RarePatterns = { "Points", "Calico" },
		Eyes = { "Brown", "Amber" },
		RareEyes = { "Blue" },
		Favorite = "meaty_bone",
		Scale = 1.1,
	},
	Bunny = {
		Name = "Bunny",
		Baby = "Kit",
		Level = 4,
		Price = 300,
		Colors = { "White", "Brown", "Gray", "Cream", "Black" },
		RareColors = { "Lilac", "Pink" },
		Patterns = { "Solid", "Spotted", "Socks" },
		RarePatterns = { "Points" },
		Eyes = { "Brown", "Blue" },
		RareEyes = { "Violet" },
		Favorite = "fresh_veg",
		Scale = 0.9,
	},
	Fox = {
		Name = "Fox",
		Baby = "Cub",
		Level = 6,
		Price = 500,
		Colors = { "Red", "Orange", "Brown" },
		RareColors = { "Arctic", "Silver", "Black" },
		Patterns = { "Socks", "Tuxedo" },
		RarePatterns = { "Spotted" },
		Eyes = { "Amber", "Brown" },
		RareEyes = { "Blue" },
		Favorite = "meaty_bone",
		Scale = 1.05,
	},
	Panda = {
		Name = "Panda",
		Baby = "Cub",
		Level = 9,
		Price = 900,
		Colors = { "Panda" },
		RareColors = { "Brown" },
		Patterns = { "Panda" },
		RarePatterns = {},
		Eyes = { "Brown" },
		RareEyes = { "Blue" },
		Favorite = "bamboo",
		Scale = 1.25,
	},
}

---------------------------------------------------------------------------
-- Rooms and styles
---------------------------------------------------------------------------

-- Interior size in studs. Cells are Cell x Cell studs.
Config.Room = { Width = 28, Depth = 20, WallHeight = 12, Cell = 2, Spacing = 32 }
Config.PlotSpacing = 500

-- Rooms unlock in this order.
Config.Rooms = {
	{ Id = "living", Name = "Living Room", Level = 1, Price = 0, Capacity = 4, Wallpaper = "cream", Floor = "oak" },
	{ Id = "bedroom", Name = "Bedroom", Level = 3, Price = 1000, Capacity = 4, Wallpaper = "lavender", Floor = "pink_carpet" },
	{ Id = "kitchen", Name = "Kitchen", Level = 5, Price = 2000, Capacity = 4, Wallpaper = "mint", Floor = "checker" },
	{ Id = "garden", Name = "Garden", Level = 8, Price = 3500, Capacity = 6, Outdoor = true, Wallpaper = "cream", Floor = "grass" },
}

Config.Wallpapers = {
	{ Id = "cream", Name = "Buttercream", Color = Color3.fromRGB(250, 238, 210), Accent = Color3.fromRGB(240, 220, 180), Pattern = "Plain", Price = 0, Level = 1 },
	{ Id = "lavender", Name = "Lavender", Color = Color3.fromRGB(222, 206, 240), Accent = Color3.fromRGB(205, 186, 230), Pattern = "Plain", Price = 0, Level = 1 },
	{ Id = "mint", Name = "Mint", Color = Color3.fromRGB(206, 238, 218), Accent = Color3.fromRGB(184, 226, 200), Pattern = "Plain", Price = 0, Level = 1 },
	{ Id = "bubblegum", Name = "Bubblegum Stripes", Color = Color3.fromRGB(252, 214, 228), Accent = Color3.fromRGB(246, 184, 208), Pattern = "Stripes", Price = 150, Level = 2 },
	{ Id = "sky", Name = "Sky Stripes", Color = Color3.fromRGB(212, 232, 252), Accent = Color3.fromRGB(184, 214, 246), Pattern = "Stripes", Price = 150, Level = 3 },
	{ Id = "polka", Name = "Peach Polka", Color = Color3.fromRGB(255, 226, 204), Accent = Color3.fromRGB(250, 190, 160), Pattern = "Dots", Price = 250, Level = 4 },
	{ Id = "starry", Name = "Starry Night", Color = Color3.fromRGB(60, 70, 130), Accent = Color3.fromRGB(255, 226, 120), Pattern = "Stars", Price = 400, Level = 6 },
}

Config.Floors = {
	{ Id = "oak", Name = "Oak Boards", Color = Color3.fromRGB(196, 146, 98), Alt = Color3.fromRGB(180, 132, 86), Material = Enum.Material.WoodPlanks, Pattern = "Plain", Price = 0, Level = 1 },
	{ Id = "pink_carpet", Name = "Pink Carpet", Color = Color3.fromRGB(240, 186, 206), Alt = Color3.fromRGB(240, 186, 206), Material = Enum.Material.Fabric, Pattern = "Plain", Price = 0, Level = 1 },
	{ Id = "checker", Name = "Checker Tiles", Color = Color3.fromRGB(250, 250, 250), Alt = Color3.fromRGB(150, 200, 230), Material = Enum.Material.SmoothPlastic, Pattern = "Checker", Price = 0, Level = 1 },
	{ Id = "grass", Name = "Lawn", Color = Color3.fromRGB(126, 196, 96), Alt = Color3.fromRGB(116, 186, 88), Material = Enum.Material.Grass, Pattern = "Plain", Price = 0, Level = 1 },
	{ Id = "mint_tile", Name = "Mint Tiles", Color = Color3.fromRGB(210, 240, 220), Alt = Color3.fromRGB(180, 226, 200), Material = Enum.Material.SmoothPlastic, Pattern = "Checker", Price = 200, Level = 3 },
	{ Id = "cherry", Name = "Cherry Wood", Color = Color3.fromRGB(150, 80, 70), Alt = Color3.fromRGB(140, 72, 64), Material = Enum.Material.WoodPlanks, Pattern = "Plain", Price = 250, Level = 4 },
	{ Id = "sky_carpet", Name = "Cloud Carpet", Color = Color3.fromRGB(200, 224, 250), Alt = Color3.fromRGB(200, 224, 250), Material = Enum.Material.Fabric, Pattern = "Plain", Price = 200, Level = 5 },
}

---------------------------------------------------------------------------
-- Shop items
---------------------------------------------------------------------------
-- Kind:
--   "Consumable": stacks in the inventory and is used up on a pet (Action says how).
--   "Furniture": placed in a room. Footprint is in cells {w, d}. Layer "Floor"
--                items (rugs) only collide with other rugs. Role makes pets use it.
-- Wallpapers and floors are sold from Config.Wallpapers / Config.Floors.

Config.ShopTabs = { "Food", "Care", "Toys", "Furniture", "Decor", "Styles" }

Config.Items = {
	-- Food
	kibble = { Name = "Kibble", Kind = "Consumable", Tab = "Food", Action = "Feed", Price = 10, Level = 1, Effects = { Food = 35 }, Icon = "🥣", Desc = "Everyday pet food." },
	tuna = { Name = "Tuna Can", Kind = "Consumable", Tab = "Food", Action = "Feed", Price = 25, Level = 1, Effects = { Food = 60, Fun = 5 }, Icon = "🐟", Desc = "Cats adore it." },
	meaty_bone = { Name = "Meaty Bone", Kind = "Consumable", Tab = "Food", Action = "Feed", Price = 25, Level = 2, Effects = { Food = 55, Fun = 8 }, Icon = "🍖", Desc = "Dogs and foxes love a bone." },
	fresh_veg = { Name = "Fresh Veggies", Kind = "Consumable", Tab = "Food", Action = "Feed", Price = 20, Level = 4, Effects = { Food = 50, Health = 5 }, Icon = "🥕", Desc = "Crunchy carrots and greens." },
	bamboo = { Name = "Bamboo Shoots", Kind = "Consumable", Tab = "Food", Action = "Feed", Price = 30, Level = 9, Effects = { Food = 70, Health = 5 }, Icon = "🎋", Desc = "A panda's favourite snack." },
	feast = { Name = "Gourmet Feast", Kind = "Consumable", Tab = "Food", Action = "Feed", Price = 60, Level = 5, Effects = { Food = 100, Fun = 15, Health = 10 }, Icon = "🍱", Desc = "Fills any tummy." },

	-- Care
	treat = { Name = "Treat", Kind = "Consumable", Tab = "Care", Action = "Treat", Price = 15, Level = 1, Effects = { Fun = 20, Food = 10 }, Icon = "🍪", Desc = "A tasty reward." },
	shampoo = { Name = "Shampoo", Kind = "Consumable", Tab = "Care", Action = "Bath", Price = 20, Level = 1, Effects = { Clean = 70 }, Icon = "🧴", Desc = "Bath time! Bubbles included." },
	vitamins = { Name = "Vitamins", Kind = "Consumable", Tab = "Care", Action = "Medicine", Price = 40, Level = 2, Effects = { Health = 40 }, Icon = "💊", Desc = "Perks up an unwell pet." },
	energy_snack = { Name = "Energy Snack", Kind = "Consumable", Tab = "Care", Action = "Treat", Price = 35, Level = 3, Effects = { Energy = 40, Food = 5 }, Icon = "🍯", Desc = "Honey biscuit for a quick boost." },

	-- Toys (pets play with these)
	yarn_ball = { Name = "Yarn Ball", Kind = "Furniture", Tab = "Toys", Role = "Toy", Price = 50, Level = 1, Footprint = { 1, 1 }, Comfort = 1, Icon = "🧶", Desc = "Pets bat it around." },
	toy_ball = { Name = "Bouncy Ball", Kind = "Furniture", Tab = "Toys", Role = "Toy", Price = 50, Level = 1, Footprint = { 1, 1 }, Comfort = 1, Icon = "⚽", Desc = "Chase it!" },
	mouse_toy = { Name = "Toy Mouse", Kind = "Furniture", Tab = "Toys", Role = "Toy", Price = 45, Level = 2, Footprint = { 1, 1 }, Comfort = 1, Icon = "🐭", Desc = "Squeaks when pounced on." },
	scratching_post = { Name = "Scratching Post", Kind = "Furniture", Tab = "Toys", Role = "Toy", Price = 120, Level = 3, Footprint = { 1, 1 }, Comfort = 2, Icon = "🪵", Desc = "Saves the sofa." },
	cat_tree = { Name = "Cat Tree", Kind = "Furniture", Tab = "Toys", Role = "Toy", Price = 300, Level = 5, Footprint = { 2, 2 }, Comfort = 4, Icon = "🌳", Desc = "Climb, perch and play." },

	-- Furniture
	food_bowl = { Name = "Food Bowl", Kind = "Furniture", Tab = "Furniture", Role = "Bowl", Price = 40, Level = 1, Footprint = { 1, 1 }, Comfort = 0, Icon = "🍽️", Desc = "Pets eat here." },
	water_bowl = { Name = "Water Bowl", Kind = "Furniture", Tab = "Furniture", Role = "Bowl", Price = 30, Level = 1, Footprint = { 1, 1 }, Comfort = 1, Icon = "💧", Desc = "Fresh water." },
	pet_bed = { Name = "Pet Bed", Kind = "Furniture", Tab = "Furniture", Role = "Bed", Price = 100, Level = 1, Footprint = { 2, 2 }, Comfort = 2, Icon = "🛏️", Desc = "Pets sleep faster in a bed." },
	cushion = { Name = "Cushion", Kind = "Furniture", Tab = "Furniture", Role = "Bed", Price = 60, Level = 1, Footprint = { 1, 1 }, Comfort = 1, Icon = "🟣", Desc = "A comfy spot for a nap." },
	litter_tray = { Name = "Litter Tray", Kind = "Furniture", Tab = "Furniture", Role = "Litter", Price = 80, Level = 2, Footprint = { 2, 1 }, Comfort = 0, Icon = "🧺", Desc = "Pets in this room stay clean twice as long." },
	sofa = { Name = "Sofa", Kind = "Furniture", Tab = "Furniture", Role = "Bed", Price = 250, Level = 3, Footprint = { 3, 1 }, Comfort = 4, Icon = "🛋️", Desc = "Everyone's favourite nap spot." },
	dog_house = { Name = "Dog House", Kind = "Furniture", Tab = "Furniture", Role = "Bed", Price = 350, Level = 5, Footprint = { 2, 2 }, Comfort = 4, Icon = "🏠", Desc = "A cosy kennel." },

	-- Decor (comfort keeps pets happier for longer)
	potted_plant = { Name = "Potted Plant", Kind = "Furniture", Tab = "Decor", Price = 60, Level = 1, Footprint = { 1, 1 }, Comfort = 2, Icon = "🪴", Desc = "A touch of green." },
	rug_round = { Name = "Round Rug", Kind = "Furniture", Tab = "Decor", Layer = "Floor", Price = 90, Level = 1, Footprint = { 3, 3 }, Comfort = 2, Icon = "⭕", Desc = "Soft underfoot." },
	floor_lamp = { Name = "Floor Lamp", Kind = "Furniture", Tab = "Decor", Price = 80, Level = 2, Footprint = { 1, 1 }, Comfort = 2, Icon = "💡", Desc = "A warm glow." },
	toy_chest = { Name = "Toy Chest", Kind = "Furniture", Tab = "Decor", Price = 150, Level = 3, Footprint = { 2, 1 }, Comfort = 3, Icon = "🧸", Desc = "Tidy toys away." },
	rug_heart = { Name = "Heart Rug", Kind = "Furniture", Tab = "Decor", Layer = "Floor", Price = 150, Level = 4, Footprint = { 3, 3 }, Comfort = 3, Icon = "💗", Desc = "Pink and lovely." },
	bookshelf = { Name = "Bookshelf", Kind = "Furniture", Tab = "Decor", Price = 180, Level = 4, Footprint = { 2, 1 }, Comfort = 3, Icon = "📚", Desc = "Pets can't read, but it looks nice." },
	fish_tank = { Name = "Fish Tank", Kind = "Furniture", Tab = "Decor", Price = 400, Level = 6, Footprint = { 2, 1 }, Comfort = 6, Icon = "🐠", Desc = "Hours of entertainment." },
	flower_bed = { Name = "Flower Bed", Kind = "Furniture", Tab = "Decor", Price = 100, Level = 7, Footprint = { 2, 1 }, Comfort = 3, Icon = "🌷", Desc = "Tulips in a planter." },
	garden_tree = { Name = "Little Tree", Kind = "Furniture", Tab = "Decor", Price = 250, Level = 8, Footprint = { 2, 2 }, Comfort = 5, Icon = "🌲", Desc = "Shade for a summer nap." },
	fountain = { Name = "Fountain", Kind = "Furniture", Tab = "Decor", Price = 600, Level = 8, Footprint = { 2, 2 }, Comfort = 8, Icon = "⛲", Desc = "The pride of any garden." },
}

-- Look up a room / style by id.
function Config.RoomById(id: string): any
	for i, room in Config.Rooms do
		if room.Id == id then
			return room, i
		end
	end
	return nil, nil
end

function Config.WallpaperById(id: string): any
	for _, w in Config.Wallpapers do
		if w.Id == id then
			return w
		end
	end
	return nil
end

function Config.FloorById(id: string): any
	for _, f in Config.Floors do
		if f.Id == id then
			return f
		end
	end
	return nil
end

return Config
