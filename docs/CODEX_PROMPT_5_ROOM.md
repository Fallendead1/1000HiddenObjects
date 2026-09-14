You are connected to Roblox Studio (place "1000 Hidden Objects", placeId 117675182630398).
This job gives Room #001 "The Messy Bedroom" its final look. Its walls and furniture are still
the grey-box shapes the code builds. The clutter (ServerStorage.ClutterAssets) and the bins and
boxes (ServerStorage.Props) already have final art: leave them exactly as they are.
It runs in phases, and you STOP for my approval after the images.

# PHASE 1 - IMAGES ONLY, THEN STOP
1. References from the real game:
   - Start Play. From the Client datamodel run
     `require(game.ReplicatedStorage.Shared.Utility.Remotes).Event("DevCommand"):FireServer("StartRoom", 1, 1)`
     and wait until ReplicatedStorage.MatchState.State = "Searching".
   - Capture: a wide shot from the door, one shot of each corner (bed, desk + window, closet,
     bookshelf, dresser, laundry corner, toy corner) and one top-down shot of the whole room.
   - Stop Play. Save the shots to output/codex-room/refs/.
2. Three room concepts (A, B, C). Each is one wide shot from the door AND a top-down plan drawn
   over my real layout, so I can see it fits. The layout is fixed (room-local studs, floor 90 x 70,
   26 tall, door on the +Z wall):
   - Bed: back-left, 14 x 22, mattress top at 4.2 studs, nightstand beside the headboard.
   - Desk: back-right. Window: back wall, right of centre. Dresser: back wall, centre.
   - Closet: along the left wall with a clothes rail at 8.9 studs.
   - Bookshelf: along the right wall with shelves at 3.7 / 6.7 / 9.7 / 12.7 studs.
   - Laundry corner front-left, toy corner front-right, beanbag by the bookshelf.
   - The 5 bins and 3 big open boxes (moving box, toy chest, hamper) stay where they are.
   Style for all three: a bright, stylized Roblox kid's bedroom (not realistic), readable from far
   away. Keep walls and furniture mid-saturated so the colourful junk, the bins' bright rims and
   the Golden Key are always the most eye-catching things.
   - A "Sunny Room": sky-blue walls with white trim, cloud and star decals, warm wood.
   - B "Gamer Room": teal and purple, LED strip glow along the ceiling, posters, a big monitor desk.
   - C "Cozy Room": soft green walls, a patterned rug, string lights, plants and a round window.
3. Equipment concept sheet (images only, nothing gets built): five cleaning tools in the same art
   style, each shown held by a blocky Roblox avatar: Bare Hands (today), Work Gloves, Grabber
   Claw, Magnet Glove and Mini Vacuum. This is for me to decide whether to add a tools system.

Save everything to output/codex-room/. Show me and STOP. Phase 2 starts only when I reply
"APPROVED" with my pick and any changes (for example "APPROVED: B, but warmer floor").

# PHASE 2 - BUILD (only after "APPROVED")

## Ground rules
- Never create, edit or delete any script. Don't change Workspace.Lobby, ReplicatedStorage,
  ServerScriptService, StarterPlayer, ServerStorage.ClutterAssets, ServerStorage.Props or
  ServerStorage.Targets.
- Work in the EDIT datamodel. Anything made during Play is thrown away.
- Performance: the room already holds ~5,800 parts while playing and must stay at 60 FPS on
  phones. Budget for everything you add: 800 parts/MeshParts at most, furniture meshes under
  5,000 triangles each, small decor under 1,000, textures 1024 x 1024 at most, no new lights
  with shadows, no particles, no SurfaceGuis, no scripts.

## Step 1 - start from the room the code builds (every position then matches the game)
In the Edit datamodel command bar:
```lua
local config = require(game.ReplicatedStorage.Shared.Config.RoomConfigs.Room001)
local build = require(game.ServerScriptService.Server.Builders.PlaceholderRoomBuilder).Build
local origin = CFrame.new(0, 0, 400) -- away from the lobby while you work
local room = build(config, origin)
room.Parent = workspace
local pivot = Instance.new("Part")
pivot.Name = "RoomOrigin"
pivot.Size = Vector3.new(1, 1, 1)
pivot.CFrame = origin
pivot.Anchored = true
pivot.Transparency = 1
pivot.CanCollide = false
pivot.CanQuery = false
pivot.CanTouch = false
pivot.Parent = room
room.PrimaryPart = pivot -- the game moves the room by this part; keep it at the floor centre
```

## Step 2 - keep (the game reads these; never rename, move, resize or delete them)
- `Structure/` - every part keeps its Name, Size, CFrame and CanCollide. You MAY change its
  Color, Material, MaterialVariant, add Textures or Decals, or set Transparency = 1 where your
  mesh replaces its look. Floor, walls and ceiling stay visible or textured, never removed.
- `Bins/` (5 invisible mouths tagged DepositBin), `Regions/` (12 parts tagged SearchRegion),
  `Sockets/` (64 parts tagged TargetSocket), `RoomSpawn` (tagged RoomSpawn; you may restyle it as
  a doormat at the same size and position), `Props/` (the bin and box art) and `RoomOrigin`.
- Do NOT add a `Clutter` folder. The game fills the room with junk when a match starts.

## Step 3 - add the final art in a new folder `Decor/` at the model root
- Every BasePart in Decor: Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false.
- Furniture reskins sit inside the collision box of the Structure parts they replace (within
  0.2 studs): bed (BedFrame, Mattress, Headboard, BedLeg), nightstand, desk, dresser, closet,
  bookshelf (junk stands on the shelf tops, so keep those heights exactly), window and beanbag.
- Walls, floor and ceiling: wallpaper, trim, rugs and decals, posters, a clock, curtains,
  string lights, a ceiling fan. Anything flat on a surface, or higher than 14 studs.
- NEVER put new solid-looking furniture on the open floor. The game stacks clutter everywhere
  on it, and anything new would clip through the junk.

## Step 4 - hand it over
Move the finished model into `ServerStorage.Rooms` and name it exactly `Room001`. Nothing of it
may be left in Workspace.

## Test (Studio MCP only)
1. Start Play, run the StartRoom command from Phase 1, wait for "Searching".
2. The Output must show `=== ROOM VALIDATION: The Messy Bedroom (001) ===` with
   `Sockets: 64 exposable / 64`, `RESULT: PASS` and between 1,700 and 1,900 movable objects
   (fewer means something is blocking the junk).
3. On the Server, `workspace:GetRealPhysicsFPS()` stays at 58 or more once the room has settled.
4. Workspace.Room001 is where the game puts it (around x = 600), not at z = 400.
5. Fire DevCommand "TargetInfo", then "BurstKeyChunk": the Golden Key is revealed and can be found.
6. Screenshots: wide from the door, every corner, first person inside a pile.
7. Stop Play. Check ServerStorage.Rooms.Room001 exists and Workspace has no leftover room.
   Then tell me to press Ctrl+S.

## Report back
The images, your pick's part and triangle counts, the full ROOM VALIDATION output, the FPS
numbers and the screenshots.
