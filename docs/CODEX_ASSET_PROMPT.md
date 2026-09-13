You are connected to Roblox Studio (place "1000 Hidden Objects", placeId 117675182630398).
Job: fill the game with ALL its art and sound. Asset work only - never create, edit or delete any script.

## Ground rules
- Code is synced from Git by Rojo. Never touch: ReplicatedStorage.Shared, ServerScriptService.Server, StarterPlayer.StarterPlayerScripts.Client, Workspace.Lobby, ServerStorage.LobbyBackup.
- Put art ONLY in the five slots below. The code reads them automatically; anything missing falls back to placeholders, so partial progress is safe.
- Do NOT build any ScreenGui or UI layout. The code builds every screen and scales it for phone/tablet/PC. You only supply images, which the code places.
- No Scripts, lights, ParticleEmitters or sounds inside models. Strip them from anything you insert.
- Every part you add: Anchored = true, CanCollide = false, CanTouch = false (the code handles physics).
- Style for everything: bright, chunky, toy-like "messy kid's bedroom", soft bevels, bold dark outline on icons. Readable at a glance.
- Save the place (Ctrl+S) at the end, and tell me to save too: these slots live in the place file, not Git.

## Slot 1 - Clutter meshes: ServerStorage.ClutterAssets.<AssetKey>
A Model (1-3 MeshParts) or a single MeshPart per key.
- Author it at the size listed (X = length, Y = height/thickness, Z = depth), axis-aligned. The game scales it proportionally to fit that box and centres it by its bounding box (pivot doesn't matter).
- Give the main coloured surface MeshPart the attribute `Tintable = true` (boolean). The game recolours it per object, so ONE neutral light-grey mesh gives every colour variant. Leave accents (labels, zips, eyes) untinted.
- Same-shape variants (marked =): build the first, then duplicate it under the other names.

| AssetKey | Size (X,Y,Z) | Notes |
|---|---|---|
| Paper_A | 1.4, 0.15, 1.9 | loose sheet, slight curl |
| Magazine_A | 1.6, 0.2, 2.1 | = Paper_A thicker, printed cover accent |
| Notebook_A | 1.2, 0.2, 1.6 | spiral edge |
| Pencil_A | 1.3, 0.2, 0.2 | length along X |
| Sock_A | 1.1, 0.45, 0.45 | length along X |
| Shirt_A | 2.2, 0.35, 1.8 | lying flat, crumpled |
| Hoodie_A | 2.6, 0.6, 2.2 | = Shirt_A bulkier, hood |
| Cup_A | 0.9, 0.7, 0.7 | lying on its side, axis X |
| Can_A | 0.9, 0.5, 0.5 | soda can on its side, axis X |
| Cable_A | 2.4, 0.2, 0.2 | coiled charger along X |
| ToyBlock_A | 1, 1, 1 | letter block |
| Remote_A | 0.5, 0.25, 1.6 | TV remote |
| ToyDuck_A | 1.1, 1.45, 1.4 | rubber duck, faces -Z |
| Book_A | 1.6, 0.4, 1.2 | closed book lying flat |
| Book_B | 2.0, 0.5, 1.4 | = Book_A |
| Book_C | 1.5, 0.6, 1.9 | = Book_A |
| Shoe_A | 1.9, 0.95, 0.8 | sneaker, toe -X |
| Bottle_A | 1.6, 0.55, 0.55 | water bottle on its side, axis X |
| PizzaBox_A | 2.6, 0.3, 2.6 | closed, greasy stain accent |
| Plush_A | 1.4, 1.4, 1.4 | round plush animal |
| ToyCar_A | 1.7, 0.85, 0.9 | toy car, front +X |
| Controller_A | 1.65, 0.3, 1.0 | game controller, grips toward +Z |
| Headphones_A | 1.95, 0.9, 0.8 | band on top, cups hanging down |
| Camera_A | 1.3, 0.8, 1.05 | compact camera, lens -Z |
| Pillow_A | 2.8, 0.9, 1.9 | |
| Blanket_A | 3.4, 0.7, 2.8 | folded-ish heap |
| TeddyBear_A | 1.6, 2.55, 1.6 | sitting bear |
| Basketball_A | 2, 2, 2 | |
| Backpack_A | 1.8, 2.2, 1.25 | upright, front pocket toward -Z |
| Laptop_A | 2.2, 1.4, 1.7 | open, screen at the +Z edge |
| CardboardBox_A | 2, 1.6, 2 | taped box |
| CardboardBox_B | 2.6, 2.25, 2.6 | = CardboardBox_A |
| HeavyBox_A | 3, 2.65, 3 | = CardboardBox_A, wooden crate look, not tinted |
| Basket_A | 2.6, 1.8, 2.0 | plastic laundry basket |
| StorageBin_A | 3.1, 2.15, 2.3 | plastic tub with lid |
| JunkChunk_A | 2.65, 1.6, 2.4 | "packed junk": a compressed bundle of clothes, papers, toys poking out |
| JunkChunk_B | 3.0, 1.8, 2.6 | = JunkChunk_A |
| JunkChunk_C | 3.4, 2.0, 3.0 | = JunkChunk_A |
| Treasure_Coin | 0.2, 1.0, 1.0 | gold coin standing on edge, face along X. Not tinted |
| Treasure_Phone | 0.7, 0.14, 1.4 | smartphone, glowing screen. Not tinted |
| Treasure_Watch | 0.3, 0.9, 2.1 | wristwatch with strap. Not tinted |
| Treasure_Trophy | 0.8, 1.85, 1.2 | small gold trophy. Not tinted |

## Slot 2 - Bin and box props: ServerStorage.Props.<Key>
Visual shells only (the game keeps its own invisible collision walls). Open top, hollow inside, pivot at the bounding-box centre, max 30 parts. The game fits each into this outer box:

| Key | Outer size (X,Y,Z) | Look |
|---|---|---|
| Bin_Laundry | 5.5, 2.85, 5.5 | blue plastic laundry basket |
| Bin_Toys | 5.5, 2.85, 5.5 | pink toy bin with stars |
| Bin_Books | 5.1, 2.65, 5.1 | orange rolling book cart |
| Bin_Trash | 5.1, 3.05, 5.1 | green trash can, no lid |
| Bin_Donation | 7.4, 1.65, 5.9 | low wooden crate labelled DONATE |
| Container_MovingBox | 9.4, 3.6, 9.4 | giant open cardboard moving box |
| Container_ToyChest | 12.4, 3.2, 9.4 | big open wooden toy chest (no lid) |
| Container_Hamper | 11.4, 3.4, 9.4 | huge white wicker hamper |

Bins must read from across the room: a bright rim in the bin's colour.

## Slot 3 - UI images: ReplicatedStorage.GameAssets.UIImages
Create Folder `ReplicatedStorage.GameAssets`, and inside it a Configuration named `UIImages`. For every image, upload it and set a STRING attribute on UIImages: name = key, value = "rbxassetid://<id>".

Frames: WHITE on a transparent background, 256 x 256, used as 9-slice.
- The rounded corners and border must sit inside a 64 px margin. The centre area (64,64)-(192,192) must be flat so it stretches.
- The code tints each frame, so one white image serves every colour. That is also why they scale cleanly to any screen size, including phones.

| Key | Description |
|---|---|
| Panel | rounded panel, soft inner bevel, 6 px darker border |
| Button | chunky pill button with a bottom lip/shadow |
| ButtonRound | perfect circle button with a bottom lip (mobile GRAB/THROW/DROP) |
| BarTrack | rounded progress-bar track |
| BarFill | rounded progress-bar fill with a subtle top shine |

Icons: 256 x 256, transparent background, full colour, thick dark outline, centred, must read at 24 px.

| Key | Description |
|---|---|
| Icon_Cash | green cash stack / coin |
| Icon_Weight | kettlebell |
| Icon_Upgrades | up-arrow |
| Icon_Shop | shopping bag |
| Icon_Hint | lightbulb |
| Icon_Settings | gear |
| Icon_Collection | trophy shelf |
| Icon_Close | X |
| Icon_Key | golden key |
| Icon_Streak | flame |
| Icon_Strength | flexed arm |
| Icon_ThrowPower | ball with motion lines |
| Icon_MoveSpeed | sneaker with speed lines |
| Bin_Laundry | shirt in a basket |
| Bin_Toys | teddy |
| Bin_Books | book stack |
| Bin_Trash | soda can |
| Bin_Donation | cardboard box with heart |
| Crosshair | WHITE, 64 x 64, small dot inside a thin ring (the code tints it) |

Variants to save work: Icon_Strength / Icon_ThrowPower / Icon_MoveSpeed share one style; the five Bin_* icons share one badge style.

## Slot 4 - Sounds: SoundService.GameSounds
Create Folder `SoundService.GameSounds`, and in it one Sound per key: Name = key, SoundId set, Volume 0.3-0.8. Use short, royalty-free Toolbox audio.
- UI: UIClick, UIClose, Notification, Hint, UpgradePurchase, UpgradeDenied, TooHeavy.
- Queue: QueueEnter, QueueLeave, Countdown, TeleportWhoosh.
- Handling: Grab, Throw (whoosh), Land, LandSoft (cloth thud), LandPaper (paper slap), LandHard (plastic/box clunk).
- Cash: Deposit (plop), DepositMatch (brighter plop + chime), Swish (basketball swish), Streak (rising ding), Treasure (sparkle fanfare), CashAward.
- Digging: ChunkBurst (soft poof of junk), KeyRattle (tiny key jingle), BinHover (soft tick), HotColdPing.
- Key: TargetReveal, TargetFound, VictorySting.
- Music (Looped = true, Volume 0.25): LobbyAmbience (upbeat, light), RoomAmbience (playful, low-key).

Variant: LandSoft/LandPaper/LandHard may be the same clip at different PlaybackSpeed; Deposit/DepositMatch likewise.

## Slot 5 - Golden Key
Already done (ServerStorage.Targets.GoldenKey). Do not change it.

## Order of work
1. UI frames + icons (Slot 3).
2. Bins + boxes (Slot 2).
3. The most common clutter first: Shirt_A, Hoodie_A, Paper_A, Magazine_A, Book_A, PizzaBox_A, Sock_A, Shoe_A, JunkChunk_A, CardboardBox_A. Then the rest of Slot 1.
4. Sounds (Slot 4).

## Test (Studio MCP only)
After each slot:
1. Start Play, then from the Client datamodel run:
   `require(game.ReplicatedStorage.Shared.Utility.Remotes).Event("DevCommand"):FireServer("StartRoom", 1, 1)`
2. Wait until `ReplicatedStorage.MatchState` attribute `State` is `Searching`.
3. Check the Output room validation says `RESULT: PASS`, with no errors from your assets.
4. Capture the HUD, a bin and a pile.

UI images are read when the client starts, so restart Play after adding them. Stop Play when done.

## Report back
Per slot: keys done, keys skipped (with reason), part counts, screenshots, and any Output errors.
