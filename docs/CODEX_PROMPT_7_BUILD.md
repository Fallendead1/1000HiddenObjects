You are connected to Roblox Studio (place "1000 Hidden Objects", placeId 117675182630398).
I approved the concept images from the last job (docs/CODEX_PROMPT_6_CONCEPTS.md); my picks and
changes are in my message. This job BUILDS that art as real 3D models and puts each one in the
slot the game already reads. The code is finished: every slot below falls back to a placeholder
until your art is there, so partial progress is safe.

## Ground rules
- Build every model from MESHES (MeshParts made in Blender and imported with the 3D Importer,
  or Studio's mesh tools), with PBR SurfaceAppearance textures (ColorMap, NormalMap,
  RoughnessMap, MetalnessMap). Never build a model out of Parts, Unions or blocks. The only plain
  Parts allowed are the invisible "Root" parts required below and the rooms' existing collision
  boxes.
- Never create, edit or delete any script. Never touch ReplicatedStorage.Shared,
  ServerScriptService.Server, StarterPlayer.StarterPlayerScripts.Client or
  ServerStorage.LobbyBackup / LobbyBackup_Farm.
- Don't change art you delivered before (ServerStorage.ClutterAssets for the bedroom objects,
  the 5 existing bin props, the 3 bedroom containers, ServerStorage.Rooms.Room001,
  ServerStorage.Targets.GoldenKey) unless my approval message asks for it.
- No Scripts, sounds or lights inside models unless a slot says so. Strip them from anything
  you import.
- Work in the EDIT datamodel. Anything made during Play is thrown away.
- Save the place (Ctrl+S) at the end and remind me to save too: these slots live in the place
  file, not in Git.

## Performance budget (phones must stay at 60 FPS with ~1,800 junk objects on screen)
| What | Budget |
|---|---|
| Clutter object | 1-3 MeshParts; up to 800 triangles (up to 2,000 for the big ones: Microwave, Beanbag, CarTire, Toaster, Suitcase, OldToolbox, RockingHorse, Quilt, CookingPot); textures up to 512 px, shared atlases welcome |
| Bin / container prop | up to 30 MeshParts, 4,000 triangles |
| Hidden object | up to 3,000 triangles, textures up to 1024 px |
| Pet | up to 4,000 triangles, 1 texture set up to 1024 px, up to 30 bones |
| Egg / gift box | up to 2,000 triangles |
| Room shell (Decor) | up to 800 MeshParts (1,000 for the attic); furniture up to 5,000 triangles each, small decor up to 1,000; textures up to 1024 px; no shadow-casting lights, no particles, no SurfaceGuis |
Reuse the same MeshId for repeated pieces so Roblox can instance them.

## Slot A - Clutter: ServerStorage.ClutterAssets.<AssetKey>
A Model (1-3 MeshParts) per key, axis-aligned, authored at the size below (X = length,
Y = height, Z = depth). The game scales the model proportionally to fit this box and centres
it; the pivot doesn't matter.
- Colour variants: give the main coloured MeshPart the attribute `Tintable = true` (boolean).
  The game sets that part's Color per object, so one mesh gives every colour. For a tinted
  part use a SurfaceAppearance with AlphaMode = Overlay and a ColorMap whose tintable area is
  transparent (or no ColorMap on that part). Leave labels, metal and other accents untinted.
- Not tinted: the food (except the apple, which may be tinted red or green), the appliances and
  all treasures (they have one true colour).
| AssetKey | Size (X, Y, Z) | What it is, and how it lies |
|---|---|---|
| Plate_A | 1.70, 0.14, 1.70 | dinner plate lying flat |
| Bowl_A | 1.20, 0.55, 1.20 | cereal bowl, upright |
| Mug_A | 0.80, 0.70, 0.95 | coffee mug lying on its side, handle toward +Z |
| Fork_A | 0.18, 0.08, 1.30 | fork lying flat, along Z |
| Spoon_A | 0.35, 0.11, 1.35 | spoon lying flat, bowl toward -Z |
| FryingPan_A | 1.80, 0.30, 2.90 | frying pan lying flat, handle toward +Z |
| CookingPot_A | 1.70, 1.30, 2.30 | cooking pot, upright, handles on the +Z and -Z sides |
| CuttingBoard_A | 1.90, 0.18, 1.20 | wooden cutting board |
| CerealBox_A | 1.10, 1.60, 0.45 | cereal box standing up (invented brand) |
| Apple_A | 0.65, 0.65, 0.65 | apple (the skin may be Tintable) |
| Banana_A | 1.30, 0.32, 0.32 | banana along X |
| Bread_A | 1.50, 0.80, 0.85 | bread loaf in a bag |
| EggCarton_A | 1.70, 0.45, 0.80 | closed egg carton |
| MilkJug_A | 0.90, 1.70, 0.90 | plastic milk jug, cap on top |
| GroceryBag_A | 1.60, 1.80, 1.00 | paper grocery bag, upright, groceries poking out |
| Wrapper_A | 0.90, 0.08, 0.60 | crumpled snack wrapper |
| Toaster_A | 1.60, 1.25, 1.10 | toaster, slots on top |
| Blender_A | 1.00, 1.90, 1.00 | blender: base with a jar on top |
| Microwave_A | 2.60, 1.60, 1.84 | microwave, door toward -Z |
| Cushion_A | 2.20, 0.80, 2.00 | sofa cushion lying flat |
| SleepingBag_A | 2.60, 0.90, 0.90 | rolled sleeping bag along X |
| PopcornBucket_A | 1.10, 1.42, 0.90 | striped popcorn bucket lying on its side along X, popcorn spilling toward +X |
| SnackBag_A | 1.00, 1.30, 0.35 | chip bag standing up |
| PictureFrame_A | 1.50, 1.90, 0.22 | framed photo, glass toward -Z |
| FloorLamp_A | 4.45, 1.30, 1.30 | floor lamp LYING DOWN along X: base at -X, shade at +X |
| BoardGame_A | 2.00, 0.45, 1.40 | board game box (invented game) |
| PuzzlePiece_A | 0.70, 0.12, 0.70 | jigsaw puzzle piece |
| GameDisc_A | 0.90, 0.12, 1.20 | game case lying flat |
| GameConsole_A | 1.80, 0.48, 1.30 | generic game console lying flat (no real brand) |
| PlantPot_A | 1.80, 2.75, 1.80 | potted leafy plant, pot at the bottom |
| Beanbag_A | 2.80, 2.80, 2.80 | beanbag chair |
| Hammer_A | 0.30, 0.30, 1.95 | hammer along Z, head at -Z |
| Wrench_A | 0.30, 0.50, 1.80 | adjustable wrench along Z, head at -Z (steel, not gold) |
| Screwdriver_A | 1.30, 0.28, 0.28 | screwdriver along X, tip at +X |
| TapeRoll_A | 0.90, 0.45, 0.90 | roll of duct tape lying flat |
| GardenHose_A | 2.20, 0.50, 2.20 | coiled garden hose lying flat |
| Helmet_A | 1.30, 1.30, 1.30 | bike helmet |
| Skateboard_A | 0.90, 0.35, 2.80 | skateboard along Z, wheels down |
| BaseballBat_A | 2.60, 0.30, 0.30 | baseball bat along X |
| SoccerBall_A | 1.60, 1.60, 1.60 | soccer ball |
| PaintCan_A | 1.20, 1.41, 1.12 | dented paint can with drips (untinted metal, tinted paint drips are fine) |
| OilyRag_A | 1.20, 0.12, 1.00 | stained shop rag lying flat |
| CarTire_A | 2.60, 0.92, 2.60 | car tyre lying flat |
| BikeWheel_A | 2.60, 0.25, 2.60 | bike wheel lying flat |
| OldToolbox_A | 2.80, 1.77, 1.40 | old metal toolbox with a handle on top |
| OldLetter_A | 1.20, 0.08, 0.90 | old envelope with a wax seal |
| PhotoAlbum_A | 1.70, 0.50, 1.40 | old leather photo album |
| Lantern_A | 0.80, 1.30, 0.80 | old oil lantern (glass glows faintly via a lighter ColorMap, no light) |
| Suitcase_A | 2.60, 1.10, 1.80 | vintage suitcase lying flat, handle on top |
| HolidayBox_A | 2.00, 1.40, 1.60 | holiday decorations box, lid on |
| RockingHorse_A | 0.70, 1.52, 2.60 | wooden rocking horse facing -Z |
| Quilt_A | 3.40, 0.60, 2.80 | old patchwork quilt, folded in a heap |
| Treasure_SilverSpoon | 0.40, 0.13, 1.48 | ornate silver spoon along Z |
| Treasure_MovieTicket | 1.30, 0.05, 0.60 | golden movie ticket lying flat |
| Treasure_ToyCarGold | 1.40, 0.73, 0.80 | vintage gold toy car, front +X |
| Treasure_PocketWatch | 0.25, 0.90, 0.90 | gold pocket watch standing on its edge, face along X |
| Treasure_OldCoin | 0.18, 1.00, 1.00 | pirate gold coin standing on its edge, face along X |

## Slot B - Bin and container props: ServerStorage.Props.<Key>
Visual shells only (the game keeps its own invisible collision walls). Open top, hollow inside,
pivot at the bounding-box centre. The game fits each model into this outer box (bins are then
made a bit bigger in rooms). Bins need a bright rim in their colour so they read from far away.
| Key | Outer size (X, Y, Z) | Look |
|---|---|---|
| Bin_DishRack | 5.5, 2.85, 5.5 | dish rack / washing tub, light blue rim |
| Bin_Pantry | 5.5, 2.85, 5.5 | open pantry basket, warm yellow rim |
| Bin_Recycling | 5.5, 2.85, 5.5 | recycling bin with the arrows symbol, blue rim |
| Bin_GameShelf | 5.5, 2.85, 5.5 | low open game cubby, purple rim |
| Bin_Toolbox | 5.5, 2.85, 5.5 | big open red tool chest |
| Bin_SportsBin | 5.5, 2.85, 5.5 | mesh sports bin, orange rim |
| Bin_Keepsakes | 5.9, 2.65, 5.1 | open antique trunk, brass rim (it stands on the attic loft) |
| Container_SinkBasin | 8.0, 1.4, 4.6 | the kitchen sink basin rim (it sits ON the counter) |
| Container_PantryCrate | 8.4, 3.4, 8.4 | big wooden pantry crate |
| Container_RecycleCrate | 12.4, 3.4, 9.4 | big blue recycling crate |
| Container_BlanketFort | 12.8, 4.0, 10.8 | the blanket fort's sheet walls (draped sheets on chairs); leave the top open |
| Container_GameChest | 12.4, 3.2, 9.4 | open wooden game chest |
| Container_PlantBox | 10.4, 2.6, 9.4 | wooden planter box |
| Container_PaintCrate | 12.4, 3.2, 9.4 | metal crate for paint cans |
| Container_SportsCrate | 12.4, 3.4, 9.4 | sports equipment crate |
| Container_JunkBox | 9.4, 3.6, 9.4 | huge taped cardboard box, flaps open |
| Container_TrunkLeft | 9.4, 3.4, 6.4 | open steamer trunk, lid open behind it |
| Container_TrunkRight, Container_TrunkLoftL, Container_TrunkLoftR | 9.4, 3.4, 6.4 | duplicates of Container_TrunkLeft |

## Slot C - Hidden objects: ServerStorage.Targets.<Id>
One Model per object, with PrimaryPart set (the game puts the "Find" prompt on it), every
BasePart Anchored = true, CanCollide = false. Author it STANDING in the XY plane (like
ServerStorage.Targets.GoldenKey): the game lays it flat on the floor with a random turn.
About the Golden Key's size (about 2.2 studs across). Premium, glowing gold where it fits.
| Id | Object |
|---|---|
| GrandmasRing | Grandma's Diamond Ring: gold band, a big sparkling diamond (ring seen from the front) |
| GoldenRemote | the Golden TV Remote |
| GoldenWrench | the Golden Wrench |
| TreasureMap | Great-Grandpa's Treasure Map: parchment with a red X and rolled ends |

## Slot D - Pets: ReplicatedStorage.GameAssets.Pets.<Key>
Create Folder ReplicatedStorage.GameAssets.Pets. One Model per pet, named by its key:
DustBunny, SockPuppy, SoapSlime, MopPup, BroomBird, LaundryFrog, VacuumCat, DusterParrot,
RoombaTurtle, GoldenBroomDragon.
- PrimaryPart = a Part named "Root": Transparency 1, sized to the pet's bounding box, centred on
  it. (The code rests the pet on the ground using Root's height: the pet's lowest point must be
  Root.Size.Y / 2 below Root's centre.) The pet FACES -Z.
- Height: Dust Bunny, Soap Slime about 1.6 studs; Sock Puppy, Broom Bird 1.7; Mop Pup,
  Laundry Frog 1.9; Vacuum Cat, Duster Parrot 2.0; Roomba Turtle 2.2; Golden Broom Dragon 2.6.
- Rig it: skinned MeshParts with Bones (or MeshParts joined by Motor6D) attached to Root. Inside
  the model: an AnimationController with an Animator.
- Animations: a Folder named "Animations" in the model with 5 Animation objects:
  Idle (loop), Walk (loop; fliers flap and hover), Carry (loop; the code hangs the carried junk
  just BELOW the pet's body, so it clutches downward), Hatch (one shot, about 1.5 s: pops out,
  shakes off, looks around) and Celebrate (one shot, about 1.5-2 s).
  Publish each animation with the Animation Editor to the SAME creator that owns this
  experience (a group-owned game needs group-owned animations, or they won't play), and put the
  published id in AnimationId. If publishing needs me, stop and tell me which ones.
- The code moves pets itself (they follow the player and fly to junk): no scripts, no
  Humanoid, no physics. Every part: CanCollide = false, CanQuery = false, CanTouch = false.
- Epic and Legendary pets may have ONE small ParticleEmitter (sparkles, Rate 4 or less) on Root.

## Slot E - Eggs: ReplicatedStorage.GameAssets.Eggs.<Key>
Folder ReplicatedStorage.GameAssets.Eggs with Models Dusty, Shiny, Royal, Attic and GiftBox
(GiftBox is used when a pet is a gift: the welcome pet, the Starter Pack, pet passes).
PrimaryPart = invisible "Root" sized to the egg (about 2 x 2.6 x 2 studs). Upright, no scripts.
The code shakes and spins them itself.

## Slot F - UI images: ReplicatedStorage.GameAssets.UIImages
Same method as before: upload each image, then set a STRING attribute on UIImages
(name = key, value = "rbxassetid://<id>"). 256 x 256 transparent unless noted, same icon style
as the existing set.
- Icon_Spin, Icon_Gift, Icon_Pets (menu buttons), Gift_Box.
- Egg_Dusty, Egg_Shiny, Egg_Royal (egg renders for the shop cards).
- Icon_Ring, Icon_Remote, Icon_Wrench, Icon_Map (hidden objects, like Icon_Key).
- Bin_DishRack, Bin_Pantry, Bin_Recycling, Bin_GameShelf, Bin_Toolbox, Bin_SportsBin,
  Bin_Keepsakes (same badge style as Bin_Laundry).
- Icon_Prod_SpeedBoost10Min, Icon_Prod_DoubleXP15Min, Icon_Prod_LiftItNow,
  Icon_Prod_JunkBlaster, Icon_Prod_TreasureRadar, Icon_Prod_StarterPack, Icon_Prod_PetSnack,
  Icon_Prod_DoubleXP, Icon_Prod_RainbowTrail, Icon_Prod_PetVacuumCat,
  Icon_Prod_PetGoldenDragon, Icon_Prod_PetSlot, Icon_Prod_FasterPets.
- Spin_Wheel (1024 x 1024): the approved wheel face, 8 slices, the first centred at the top,
  clockwise lime, cyan, green, purple, orange, pink, red, gold, no text.
- Spin_Pointer (128 x 140): the pointer, pointing down.

## Slot G - Room shells: ServerStorage.Rooms.Room002 ... Room005
Same method as the bedroom (docs/CODEX_PROMPT_5_ROOM.md, steps 1-4), once per room, with that
room's config: `RoomConfigs.Room002` (Kitchen), `Room003` (Living Room), `Room004` (Garage),
`Room005` (Giant Attic). Build each at its own spot (for example CFrame.new(0, 0, 400),
(0, 0, 600), (0, 0, 800), (0, 0, 1000)) so they don't overlap.
- Keep: Structure/ (every part keeps its Name, Size, CFrame and CanCollide; you may restyle it or
  set Transparency = 1 where your mesh replaces its look), Bins/, Regions/, Sockets/,
  RoomSpawn, Props/, Wayfinding/ if present, and RoomOrigin.
- Add your meshes in a new Decor/ folder (Anchored, CanCollide = false, CanQuery = false,
  CanTouch = false). Furniture meshes sit inside the collision box of the Structure parts they
  replace, within 0.2 studs. Keep every surface junk stands on at its exact height (counter
  tops, the island, the dining table, shelf tops, the sofa seat, the coffee table, the mantel,
  the window seat, the workbench, the freezer, the car roof, the loft floor, the ramps).
- Never put new solid-looking furniture on the open floor: the game covers it with junk.
- Do NOT add a Clutter folder. Move each finished model into ServerStorage.Rooms and name it
  exactly Room002, Room003, Room004, Room005. Nothing may be left in Workspace.

## Slot H - The lobby Pet Shop (Workspace.Lobby, the approved design)
Build it inside Workspace.Lobby near the spawn, out of meshes, anchored, walkable:
- Three pedestals with the Dusty, Shiny and Royal egg models on top as decoration. Tag ONE
  part of each pedestal "EggPedestal" (CollectionService) with a STRING attribute Egg = "Dusty",
  "Shiny" or "Royal". The code adds a "Hatch" prompt to it.
- A shop sign or counter: tag one visible part "PetShop". The code adds a "Pet Shop" prompt.
- Keep every existing tagged lobby part (circles, boards, shop stand, spinning key, spawn)
  exactly as it is. Stay within the lobby's current part budget.

## Slot I - Creator Hub images (FILES ONLY, upload nothing)
Save the approved finals to output/creator-hub/ at 512 x 512:
- Pass_DoubleCash, Pass_StrongerHands, Pass_FastHands, Pass_ThrowBoost, Pass_VIP (restyled in the
  colour system), Pass_DoubleXP, Pass_RainbowTrail, Pass_PetVacuumCat, Pass_PetGoldenDragon,
  Pass_PetSlot, Pass_FasterPets.
- Product_SpeedBoost10Min, Product_DoubleXP15Min, Product_LiftItNow, Product_JunkBlaster,
  Product_TreasureRadar, Product_StarterPack, Product_PetSnack.
- Badge_Room002Speed, Badge_Room003Speed, Badge_Room004Speed, Badge_Room005Speed,
  Badge_Room005Clear.

## Order of work
1. Slot F (UI images), then Slot C (hidden objects).
2. Slot A: the most common objects first (Plate_A, Mug_A, Cushion_A, OilyRag_A, OldLetter_A,
   Quilt_A, CardboardBox-sized ones), then the rest. Slot B.
3. Slot D and E (pets, eggs, animations).
4. Slot G (rooms), one at a time, testing each.
5. Slot H, then Slot I.

## Test (Studio MCP only; restart Play after adding UI images)
Start rooms from the Server datamodel with the Studio test hook
`workspace:SetAttribute("DevRun", "<command>")`, for example "StartRoom 1 2". Other commands:
"ValidateRoom 3", "TargetInfo", "RevealTarget", "BurstKeyChunk", "GiveEgg Royal",
"GivePet DustBunny", "AddWallet 5000", "ResetPets", "ResetRetention".
1. Rooms: for each of rooms 2-5, start it and wait until ReplicatedStorage.MatchState.State is
   "Searching". The Output must show that room's ROOM VALIDATION with RESULT: PASS and:
   Room002 64 sockets and 1,650-1,900 movable objects; Room003 56 sockets and 1,500-1,750;
   Room004 53 sockets and 1,600-1,850; Room005 63 sockets and 1,600-1,850. Fewer objects means
   your art is blocking the junk. `workspace:GetRealPhysicsFPS()` on the Server stays at 58 or
   more once the room has settled. Run "RevealTarget": your hidden object lies flat on the floor.
   Screenshots: wide from the door, each corner, first person inside a pile, the loft (attic).
2. Clutter and bins: in each room, capture a pile close up and every bin. No placeholder
   shapes should be left for the keys in Slot A.
3. Pets: in the lobby run "GiveEgg Royal" a few times and "GivePet GoldenBroomDragon". The hatch
   scene plays with your egg and pet; open PETS (right side) and check EGGS, MY PETS and INDEX
   show your models. Walk around: the equipped pets follow and animate (Walk, Idle). Start a
   room and move around for a minute: pets fly to junk and carry it into bins (Carry).
   Check Output for any "Animation" or permission errors.
4. UI: capture the lobby HUD, the SPIN menu (the wheel must line up: the first prize is at the
   top), the GIFTS menu, and the shop's Pets tab.
5. Lobby: walk up to each egg pedestal and the Pet Shop sign; the prompts appear and open PETS.
6. Clean up my test save: run "ResetPets" and "ResetRetention", wait 10 seconds, stop Play.
7. Check Workspace has no leftover rooms or previews. Save (Ctrl+S) and remind me to save.

## Report back
Per slot: keys done, keys skipped (with the reason), triangle and part counts, the animation
asset ids, the ROOM VALIDATION output and FPS for each room, screenshots, and any Output errors.
