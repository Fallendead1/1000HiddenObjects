You are connected to Roblox Studio (place "1000 Hidden Objects", placeId 117675182630398).
This job re-themes the lobby and adds a few small missing pieces. It runs in TWO PHASES.

# PHASE 1 - IMAGES ONLY, THEN STOP
In Phase 1 you only make pictures. Do NOT change, add, move, upload or delete anything in Studio.
Do NOT create any model, part or asset yet.

Save every image to output/codex-concepts/ and then show me all of them.

When you are done, STOP and wait. Phase 2 starts only when I reply with "APPROVED" plus my choice
(for example "APPROVED: Lobby B, boards as shown, icons as shown"). If I ask for changes, redo the
images and wait again.

## 1. Lobby concepts (3 options)
The game: players dig through a HUGE messy kid's bedroom, throw junk into bins, and hunt for one
hidden golden object per room (1000 rooms). Today the lobby is a farm (Garden, ChickenBarn,
ClassShop, UpgradeShop), which doesn't fit. Give me 3 different directions that fit the game:
bright, cartoony, playful, readable on a phone.

Some ideas to start from (mix or replace them):
- A cosy neighbourhood street in front of a giant cartoon house. The front door is the way into
  the rooms. Oversized junk around the yard: a giant laundry basket, towering box stacks, a huge
  sock, toys.
- "The Lost & Found Club" HQ: a clubhouse full of shelves of found treasures, with a big golden
  key sign.
- A giant attic/bedroom floor seen at tiny scale: players stand on a rug between books the size
  of buildings.

For EACH option make:
- LobbyConcept_<A/B/C>_Overview.png - 1920x1080, three-quarter view from above of the whole lobby.
- LobbyConcept_<A/B/C>_Spawn.png - 1920x1080, what a player sees standing at the spawn.

Every option must visibly show the pieces the game needs (they stay, see "Keep" below):
the 4 glowing matchmaking circles, the 3 leaderboard boards plus the collection board, the shop
stand, the "more rooms coming soon" door, and the big spinning golden key in the middle.

## 2. Boards
- Boards_Concept.png - the collection board and the THREE leaderboards (TOP OBJECT FINDERS,
  FASTEST ROOM #001, MOST CLEANED) together, framed in the new style. The text is drawn by the
  game, so just show where it goes.

## 3. Two HUD icons
Same size, stroke and style as your existing Icon_Collection / Icon_Shop images.
- Icon_Challenges.png - a clipboard checklist with a small star.
- Icon_Invite.png - two friends' heads with a plus sign.

# PHASE 2 - BUILD (only after I reply "APPROVED")

## Ground rules
- Never create, edit or delete any script. Never touch ReplicatedStorage.Shared,
  ServerScriptService.Server, StarterPlayer.StarterPlayerScripts.Client or ServerStorage.LobbyBackup.
- FIRST make a backup: duplicate the whole current Workspace.Lobby into ServerStorage and name
  it LobbyBackup_Farm. Do not change the backup.
- Build only inside Workspace.Lobby. The lobby's buildings and decor are static scenery:
  Anchored = true, sensible collisions, everything walkable, no loose physics props.
- Keep roughly the same footprint (about 132 x 128 studs). Keep the spawn area open.
- Stay light enough for phones: no more parts than the farm lobby has now (about 3,000
  instances in total). Reuse meshes and parts where you can.
- Don't change Lighting, the sky or the camera unless my approved concept needs it; if so, tell me.

## Keep (these make the game work - restyle around them, but keep every name, tag and attribute)
| What | Path | Tags / attributes |
|---|---|---|
| Spawn | Workspace.Lobby.LobbySpawn | tag LobbySpawn |
| 4 matchmaking circles | Workspace.Lobby.MatchmakingZones.Queue01..Queue04 | each QueueZone part: tag QueueZone, QueueId, Radius = 8.5. Keep each Visual folder (GlowRim, GlowDisc, GlowCore, SparklePlane) |
| Collection board | Workspace.Lobby.CollectionBoard | tag CollectionBoard, Face = "Front" |
| Leaderboards | Workspace.Lobby.TopFindersBoard, Workspace.Lobby.FastestBoard | tag Leaderboard, Kind = "TopFinders" / "Fastest", Face = "Front" |
| Board frames | Workspace.Lobby.BoardFrames | restyle to the new look |
| Future door | Workspace.Lobby.FutureDoor (+ FutureDoorFrame) | tag FutureDoor, Label = "MORE ROOMS COMING SOON" |
| Spinning key | Workspace.Lobby.LobbyKeyDeco | tag LobbyKeyDeco (anchored, no collision) |
| Shop | tag ShopStand is on Workspace.Lobby.UpgradeShop.AwningValance | if the shop is replaced, move the ShopStand tag to one visible part of the new shop (a counter or sign) |

You may move these pieces to fit the new layout. The circles must stay reachable, flat on the
ground, and at least 20 studs apart. Every board's Face attribute must be the side that faces
the players.

## Replace
Garden, ChickenBarn, ClassShop, UpgradeShop, Ground and Fence become the approved theme.

## Add
- MostCleanedBoard: a flat Part the same size as the other leaderboards (about 12 x 14 x 0.5),
  standing next to them. Tag "Leaderboard", attributes Kind = "MostCleaned" and
  Face = "Front" (or whichever side faces the players). Give it the same frame as the other boards.
- The two icons: upload them and set STRING attributes on ReplicatedStorage.GameAssets.UIImages:
  Icon_Challenges and Icon_Invite = "rbxassetid://<id>".

## Test (Studio MCP only)
1. In Edit mode, list every tagged part inside Workspace.Lobby with its attributes, and check the
   table above is all still there, plus the new MostCleanedBoard.
2. Start Play. The client is in the lobby.
   - Capture the view from the spawn, and one overview.
   - Check all 4 boards show text (in Studio, "No entries yet" is fine), the SHOP sign, the door
     sign, and the spinning key.
   - Check the CHALLENGES and INVITE buttons (right side) show your new icons.
   - Walk the character into Queue01's circle and check the "Choose a room" panel appears.
3. Check Output: no new errors. The DataStore "Studio access to APIs" lines are known and fine.
4. Stop Play. Save the place (Ctrl+S) and remind me to save.

## Report back
Which concept you built, the backup path, every tagged part (full path + attributes), the new
UIImages keys, screenshots, the total instance count of Workspace.Lobby, and any Output errors.
