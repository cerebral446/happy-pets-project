# Happy Pets (Roblox)

A cosy virtual-pet game for Roblox, inspired by the 2009 Facebook game *Happy Pets*.
Adopt kittens, puppies, bunnies, foxes and pandas. Feed, pet, play with and bathe
them, collect the coin gifts happy pets leave, decorate their rooms, unlock more
of the house, breed babies with inherited coats, and visit other players' pets.

Everything is built from code: the house, pets, furniture, UI and effects. The
game needs no uploaded assets, models or plugins.

## Open it in Roblox Studio

### Option A: open the place file (easiest)

1. Download `HappyPets.rbxlx` from this folder.
2. In Roblox Studio choose **File → Open from File…** and pick `HappyPets.rbxlx`.
3. Press **Play** (F5). To try visiting, use **Test → Clients and Servers** with 2+ players.
4. To keep saves, publish the place (**File → Publish to Roblox As…**) and turn on
   **Game Settings → Security → Enable Studio Access to API Services**.

### Option B: Rojo (live-sync while you edit the code)

1. Install [Rojo](https://rojo.space/) and its Studio plugin.
2. Run `rojo serve` in this `happy-pets` folder.
3. In Studio, open a new **Baseplate** place, delete the Baseplate and SpawnLocation,
   and click **Connect** in the Rojo plugin. The project file turns off
   `Workspace.StreamingEnabled` and sets Lighting to *Future*.

After you change files in `src/`, rebuild the place file with
`python3 tools/build_place.py`.

## How to play

| Input | Action |
| --- | --- |
| Click / tap a pet | Select it and open its care panel. Click again to pet it |
| Click a 🪙 above a pet | Collect its gift |
| ◀ ▶, A/D or the arrow keys | Switch rooms |
| Mouse wheel / pinch | Zoom |
| Right-drag or Q/E | Swing the view a little |
| R (decorating) | Rotate the furniture you're holding |
| Esc (decorating) | Drop what you're holding, or leave Decorate mode |

The first time you play, the Adoption Centre opens with a free kitten.

### Caring for pets

Every pet has five needs from 0 to 100: **Food, Fun, Energy, Clean and Health**.
They drop slowly in real time, and keep dropping while you're away (up to 48
hours). Pets never die or run away. A neglected pet just looks sad, and health
never falls below 20.

| Action | Effect |
| --- | --- |
| ✋ Pet | +Fun. Small reward every 20 s |
| 🍖 Feed | Uses food from your items. The pet walks to the nearest bowl. Its favourite food (⭐) gives bonus fun |
| 🎾 Play | +Fun, −Energy. Needs a toy in the room. The pet runs over and plays with it |
| 🪮 Brush | +Clean, free, once a minute |
| 🧴 Care | Bath (shampoo), treats, energy snacks, vitamins |
| 💤 Sleep / ☀️ Wake | Tired pets also nap by themselves, in the nearest bed if there is one (beds restore energy faster) |

Low needs show up as thought bubbles (🍖 💤 🫧 🎾). Pets with a good mood leave a
**coin gift** every 3 minutes. Each care action gives XP and a few coins.

### Progress

- **Levels** unlock new species (Dog at level 2, Bunny at 4, Fox at 6, Panda at 9),
  shop items and styles. Each level-up pays coins.
- **Daily bonus**: the 🎁 button in the status bar.
- **Rooms**: Living Room (start), Bedroom (level 3), Kitchen (level 5) and
  Garden (level 8). Each room holds 4–6 pets.
- **Decorations** add *comfort*, which slows how fast pets get bored. A litter tray
  keeps a room's pets clean twice as long.
- **Rare coats** (✨) appear in adoption and through breeding.

### Breeding

Choose a grown-up boy and girl of the same species. Both need to be happy and not
bred in the last 30 minutes. It costs 100 coins, and the baby arrives 2 minutes
later. Each trait (coat colour, pattern and eye colour) comes from one parent,
with a small chance of a mutation, sometimes a rare one. The result is decided by
a stored seed, so it can't be rerolled. Babies grow up after an hour or 12 care
actions.

### Visiting

**Visit** lists the other players on the server. While visiting, click their pets
to pet them. Each pet pays you 5 coins once a day (up to 20 a day), and their
owner gets a message.

## Where saves live

The server saves each player to a DataStore named `HappyPetsSave_v1` under the key
`player_<UserId>`. It saves every 60 seconds, when the player leaves, and when the
server shuts down. The status bar shows ✓ Saved, 💾 Saving…, or ⚠ Not saving when
DataStores are unavailable (for example in an unpublished place). In that case
the game still runs, but nothing is kept.

- The save is versioned (`Config.SaveVersion`). When you change the layout, bump the
  version and add a migration to `MIGRATIONS` in `src/shared/SaveSchema.luau`.
- `SaveSchema.Load` repairs missing or corrupted fields instead of failing. For example,
  furniture that no longer fits goes back to the inventory, and unknown pets and items
  are dropped.
- A light session lock stops two servers from overwriting each other's copy when a
  player hops between servers quickly.
- **Settings → Reset save** wipes a player's progress (with two confirmations).

## Project layout

```
src/shared/Config.luau          All tuning: needs, prices, levels, species, items, rooms, styles
src/shared/PetRules.luau        Needs simulation, care effects, growth, rarity, adoption, inheritance
src/shared/Economy.luau         Coins, XP/levels, capacity, inventory helpers, unlock lists
src/shared/Placement.luau       Furniture grid: footprints, rotation, overlap and bounds checks
src/shared/SaveSchema.luau      Default save, migrations, repair of bad data
src/shared/Rng.luau             Deterministic RNG (same results on server, client and in tests)
src/shared/PetModels.luau       Builds pets from parts, with an animation rig
src/shared/FurnitureModels.luau Builds furniture from parts
src/shared/Build.luau           Part-building helpers
src/server/HappyPetsServer.server.luau  Player lifecycle, request dispatch, simulation tick, autosave
src/server/Actions.luau         Every client request, validated (adopt, care, buy, place, breed, visit…)
src/server/Plots.luau           Each player's house: rooms, walls, wallpaper, floors, furniture models
src/server/PetService.luau      Pet models and the attributes clients animate from
src/server/DataService.luau     DataStore load/save with retries and session lock
src/server/Names.luau           Pet name validation and Roblox text filtering
src/client/Client.client.luau   Start-up, clicking pets/furniture, notifications
src/client/State.luau           Profile, current room/home, selection, server requests
src/client/UI.luau              The cosy UI kit: glossy buttons, windows, bars, tooltips, sounds
src/client/Hud.luau             Status bar, nav bar, room switcher, toasts, rewards, level-up
src/client/PetPanel.luau        Selected pet's portrait, needs and actions
src/client/Windows.luau         Adopt, My Pets, Shop, Items, Breed, Rooms, Visit, Settings
src/client/Decorate.luau        Furniture placement with a green/red preview
src/client/PetAnimator.luau     Wandering, walking, sitting, sleeping, eating, playing, hearts
src/client/CameraController.luau Dollhouse camera
src/client/Audio.luau           Lo-fi music playlist and per-species pet voices
tests/run.luau                  Unit tests for the game rules
tests/models.luau               Builds every pet look and furniture item
tests/server.luau               Headless run of the server logic (adopt → care → decorate → breed → visit → save)
tools/build_place.py            Builds HappyPets.rbxlx from src/ (with empty Assets/Audio folders)
tools/make_lofi.py              Synthesises the original lo-fi tracks in assets/audio/
assets/audio/                   The two lo-fi tracks, ready to upload to Roblox
```

The game rules (`PetRules`, `Economy`, `Placement`, `SaveSchema`) don't use any
Roblox engine APIs, so they're shared by the server and client and run in tests.
The server owns all data. Clients only ask for actions through one
`RemoteFunction`, and the server re-checks prices, ownership, positions and
cooldowns, and processes one request at a time per player (so double clicks
can't buy something twice).

## Running the tests

The tests run with [Lune](https://lune-org.github.io/docs) (0.8+), from this
folder:

```
lune run tests/run       # game rules
lune run tests/models    # every pet and furniture model builds with valid properties
lune run tests/server    # server actions end-to-end, with engine methods shimmed
```

They don't replace a play-test in Studio: the camera, UI and animation only run in
the real engine.

## Adding a new pet species

1. In `src/shared/Config.luau`, add an entry to `Config.Species` (name, baby name,
   unlock level, price, colours, patterns, eye colours, favourite food, scale) and
   add its id to `Config.SpeciesOrder`. Any new colour names go in `Config.Colors`
   or `Config.EyeColors`.
2. In `src/shared/PetModels.luau`, add its proportions to `SHAPES` (body and head
   size, leg length, ear style `Pointy`/`Big`/`Floppy`/`Long`/`Round`, tail style
   `Long`/`Wag`/`Puff`/`Bushy`/`Stub`, snout length). Species without an entry use
   the cat's shape.
3. Run `lune run tests/run` and `lune run tests/models` to check it's well formed, then
   rebuild the place.

New furniture works the same way: add the item to `Config.Items` with a
`Footprint`, optional `Role` (`Bowl`, `Bed`, `Toy`, `Litter`) and `Comfort`, then
add a builder function in `FurnitureModels.luau`. Items without a builder appear
as a plain box.

## Replacing the placeholder artwork

All art is made from parts, so the game works without any uploads. To swap in
real models, create `ReplicatedStorage/Assets` with two folders:

- **`Assets/Furniture/<itemId>`**: a Model per item, with its pivot at the centre of
  the footprint on the floor and its front facing +Z. It's cloned instead of the
  built-in shape.
- **`Assets/Pets/<Species>`**: a Model per species (for example `Cat`) with a `PrimaryPart`
  at floor level, facing −Z. Parts named `Coat`, `Accent` and `Eye` are tinted to each
  pet's colours. To be animated, parts need a `Group` attribute (`Body`, `Head`,
  `Tail`, `LegFL`, `LegFR`, `LegBL`, `LegBR`) and a `Rest` CFrame, and the model needs
  `Joint_<Group>` attributes, as written by `PetModels.Build`.

Asset manifest (ids used by the code):

| Pets (`Assets/Pets/…`) | Unlock level |
| --- | --- |
| `Cat` | 1 |
| `Dog` | 2 |
| `Bunny` | 4 |
| `Fox` | 6 |
| `Panda` | 9 |

| Furniture id (`Assets/Furniture/…`) | Name | Shop tab | Pets use it as |
| --- | --- | --- | --- |
| `yarn_ball` | Yarn Ball | Toys | Toy |
| `toy_ball` | Bouncy Ball | Toys | Toy |
| `mouse_toy` | Toy Mouse | Toys | Toy |
| `scratching_post` | Scratching Post | Toys | Toy |
| `cat_tree` | Cat Tree | Toys | Toy |
| `food_bowl` | Food Bowl | Furniture | Bowl |
| `water_bowl` | Water Bowl | Furniture | Bowl |
| `pet_bed` | Pet Bed | Furniture | Bed |
| `cushion` | Cushion | Furniture | Bed |
| `litter_tray` | Litter Tray | Furniture | Litter |
| `sofa` | Sofa | Furniture | Bed |
| `dog_house` | Dog House | Furniture | Bed |
| `potted_plant` | Potted Plant | Decor | - |
| `rug_round` | Round Rug | Decor | - |
| `floor_lamp` | Floor Lamp | Decor | - |
| `toy_chest` | Toy Chest | Decor | - |
| `rug_heart` | Heart Rug | Decor | - |
| `bookshelf` | Bookshelf | Decor | - |
| `fish_tank` | Fish Tank | Decor | - |
| `flower_bed` | Flower Bed | Decor | - |
| `garden_tree` | Little Tree | Decor | - |
| `fountain` | Fountain | Decor | - |

Interface clicks use Roblox's built-in `rbxasset://sounds/…` files.

## Music and pet sounds

The game has a lo-fi hip hop music player, and every species has its own
voice. Cats meow and purr, dogs bark and whine, and so on. Roblox only plays
audio that's been uploaded to Roblox, so you need to connect the sounds once,
in Studio. Until then the game is simply quiet. Nothing breaks.

**When pets make sounds** (6 kinds per species):

| Kind | Plays when… | Cat | Dog | Bunny | Fox | Panda |
| --- | --- | --- | --- | --- | --- | --- |
| `Greet` | you click it, bath, vitamins | meow | bark | squeak | yip | bleat |
| `Love` | you pet it, brush it, give a treat | purr | happy pant | soft purr | chatter | happy squeak |
| `Play` | it plays with a toy | trill / chirp | excited bark | thump | playful yip | squeal |
| `Eat` | it eats | crunch | crunch | nibble | crunch | munch |
| `Sad` | it's hungry, tired, bored or dirty | sad meow | whine | thump | whimper | whine |
| `Sleep` | it falls asleep, and snoozes now and then | soft purr | snore | — | snore | snore |

Babies sound higher pitched, and every sound varies a little each time. A
missing kind falls back to that species' `Greet` sound. Pets only make noise in
the room you're looking at.

### 1. Add the music

`assets/audio/` has two original lo-fi tracks made for this game:
`lofi_sunny_window.ogg` and `lofi_rainy_nap.ogg`, about 2 minutes each. They
were synthesised by `tools/make_lofi.py`, so you're free to upload them.

1. In Studio, open **View → Asset Manager**, click **Bulk Import**, and pick both `.ogg`
   files. You can also upload them at **create.roblox.com → Creations → Audio**.
2. Once they're approved, right-click each one, choose **Copy Asset ID**, and paste
   the ids into `Config.Audio.Music` in `src/shared/Config.luau`:
   ```lua
   Music = { "rbxassetid://1111111111", "rbxassetid://2222222222" },
   ```
   Or drag the uploaded sounds straight into **ReplicatedStorage → Assets → Audio →
   Music** in the Explorer.

Tracks shuffle and fade into each other. Players can turn music off in
**⚙️ Settings**, separately from the other sounds.

### 2. Add the animal sounds

The place file already has a folder for every species and kind:
**ReplicatedStorage → Assets → Audio → Cat → Greet**, and so on.

1. Open the **Toolbox** (View → Toolbox), choose the **Audio** tab, and search for, say,
   `cat meow`. Sounds uploaded by **Roblox** (shown as the creator) can be used in any
   experience.
2. Drag a sound you like into the matching folder, for example `Assets/Audio/Cat/Greet`.
   Put several in one folder and the game picks one at random each time.
3. Press Play and click a cat. 🐱

You can also paste ids into `Config.Audio.Pets` instead of using the folders.

To make your own music variations, change the chords, tempo or seed in
`tools/make_lofi.py` and run `python3 tools/make_lofi.py`. It needs numpy and ffmpeg.
