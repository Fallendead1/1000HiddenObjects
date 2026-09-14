You are connected to Roblox Studio (place "1000 Hidden Objects", placeId 117675182630398).
Your first delivery (clutter, props, sounds, 24 UI images) is installed and verified. This job adds ONLY what is still missing.
Asset and Studio-setup work only - never create, edit or delete any script.

## Ground rules (same as before)
- Never touch: ReplicatedStorage.Shared, ServerScriptService.Server, StarterPlayer.StarterPlayerScripts.Client, ServerStorage.LobbyBackup.
- Workspace.Lobby: ONLY the tagging/board work in Part C. Do not move, delete or restyle anything else in it.
- Do not change anything you already delivered unless it is listed here.
- Do NOT build ScreenGuis or UI layouts. The code places every image and animates it (glow, shine sweeps, pulses) for phone, tablet and PC.
- Save the place (Ctrl+S) at the end and remind me to save.

## Part A - More UI images: ReplicatedStorage.GameAssets.UIImages
Same method as before: upload the image, then set a STRING attribute on UIImages (name = key, value = "rbxassetid://<id>").

Effect images: WHITE on transparent; the code tints them.

| Key | Size | What it is |
|---|---|---|
| Glow | 256x256 | Soft round glow: a white centre fading smoothly to fully transparent at the edge. No hard rim. Used behind panels, icons and buttons. |
| Rays | 512x512 | Sunburst of 16 soft tapered light rays from the centre, fading outward. It spins behind the found object in the victory ceremony. |

Art images: full colour.

| Key | Size | What it is |
|---|---|---|
| Logo | 1024x440, transparent | Game wordmark "1000 HIDDEN OBJECTS". Chunky, playful, gold-and-white letters with a thick dark outline. A small golden key worked into one of the zeros. |
| LoadingBackground | 1920x1080, opaque | Illustrated messy kid's bedroom, soft-focus, a little dark (text sits on top), warm lamp light, a faint golden glint hidden in a pile. No text. |

Notification icons: 128x128, transparent, white symbol on nothing. The code puts each on a coloured circle.

| Key | Symbol |
|---|---|
| Icon_Notify_Info | i |
| Icon_Notify_Success | check mark |
| Icon_Notify_Warning | ! |
| Icon_Notify_Error | X |
| Icon_Notify_Premium | star |

Variants: these five share one stroke style.

Shop product icons: 256x256, transparent, full colour, thick dark outline, same style as your existing icon set.

| Key | Picture |
|---|---|
| Icon_Prod_DoubleCash | two cash stacks with "2X" |
| Icon_Prod_StrongerHands | flexed arm with a plus badge |
| Icon_Prod_FastHands | glove with speed lines |
| Icon_Prod_ThrowBoost | ball with a big motion trail and an up arrow |
| Icon_Prod_VIP | gold crown with "VIP" |
| Icon_Prod_Strength10Min | flexed arm with "2X" and a small clock |
| Icon_Prod_Cash10Min | cash stack with "2X" and a small clock |
| Icon_Prod_TeamMuscleBoost | three flexed arms together |
| Icon_Prod_QuickHint | lightbulb with a lightning bolt |
| Icon_Prod_SuperHint | magnifying glass over a glowing gold spot |

Variants: the 2X-clock pair share one layout; reuse your Icon_Strength / Icon_Cash / Icon_Hint as bases.

## Part B - Creator Hub images (FILES ONLY, do not upload as gamepasses/products)
I create passes, products and badges myself. Save these PNGs to output/creator-hub/ with exactly these names:
- Gamepass icons (512x512, circular-safe centre): Pass_DoubleCash, Pass_StrongerHands, Pass_FastHands, Pass_ThrowBoost, Pass_VIP.
  Reuse the matching Icon_Prod_ art on a bright rounded background.
- Developer product icons (512x512): Product_QuickHint, Product_SuperHint, Product_Strength10Min, Product_Cash10Min, Product_TeamMuscleBoost.
- Badges (512x512, circular): Badge_FirstObject (golden key), Badge_TenObjects, Badge_HundredObjects, Badge_FiveHundredObjects, Badge_ThousandObjects (trophies getting bigger), Badge_FirstFinderWin (hand holding the key), Badge_Room001Speed (key with a stopwatch).
- Game icon: GameIcon (512x512). The golden key bursting out of a pile of junk, logo-style.
- Game thumbnails (1920x1080): Thumbnail_1 (first-person view digging through a huge colourful pile, the golden key glinting); Thumbnail_2 (a player throwing a shirt into a glowing laundry basket, "+$" popping); Thumbnail_3 (4 friends in a messy bedroom, the key revealed with light rays). Bold, readable at small size, no tiny text.

## Part C - Lobby boards (the code is already written; it only needs tagged parts)
Inside Workspace.Lobby, near LobbySpawn, add these and tag them with CollectionService.
- CollectionBoard: one flat Part (about 14 x 8 x 0.5 studs), standing, facing the spawn. Tag "CollectionBoard". Attribute Face (string) = the NormalId facing the players, e.g. "Front". The code draws "YOUR COLLECTION 0/1000" and a VIEW button on it.
- Two leaderboards: flat Parts (about 12 x 14 x 0.5), standing side by side. Tag both "Leaderboard".
  - One gets attribute Kind = "TopFinders".
  - The other gets Kind = "Fastest".
  - Both get Face as above.
- ShopStand: tag one existing visible part of Workspace.Lobby.UpgradeShop (a counter or roof) "ShopStand". The code adds a SHOP sign and an "Open Shop" prompt.
- FutureDoor: a closed door model or Part near the queue circles. Tag "FutureDoor". Attribute Label = "MORE ROOMS COMING SOON".
- LobbyKeyDeco: a 3x-size copy of ServerStorage.Targets.GoldenKey as a Model, hovering about 8 studs up in the lobby centre, anchored, no collision. Tag the Model "LobbyKeyDeco". The code spins and bobs it.

Give the boards a frame in the existing lobby style: dark trim, soft light. No scripts.

## Test (Studio MCP only)
1. Start Play. The client is in the lobby.
   - Check the collection board, both leaderboards ("No entries yet" is fine in Studio), the SHOP sign and prompt, the door sign and the spinning key.
   - Capture it.
2. From the Client datamodel run:
   `require(game.ReplicatedStorage.Shared.Utility.Remotes).Event("DevCommand"):FireServer("StartRoom", 1, 1)`
   - Wait until MatchState.State = "Searching".
   - Check the Output says RESULT: PASS.
   - Capture the HUD.
3. Stop Play.

UI images are read when the client starts, so restart Play after adding them.

## Report back
Part A keys added; Part B file list; Part C what you tagged (full paths); screenshots; any Output errors.
