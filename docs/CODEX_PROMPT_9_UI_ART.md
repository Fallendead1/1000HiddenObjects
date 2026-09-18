You are connected to Roblox Studio (place "1000 Hidden Objects", placeId 117675182630398).
This job makes the game's menus and icons look premium. The code is finished: it already reads
every image below from ReplicatedStorage.GameAssets.UIImages the moment it exists, so you only
make art. It runs in two phases, and you STOP for my approval after the images.

## Ground rules
- Never create, edit or delete any script. Don't touch ReplicatedStorage.Shared,
  ServerScriptService, StarterPlayer, ServerStorage or Workspace (except Phase 2 step 3).
- Never use computer control (mouse / keyboard / screen) for anything. If a step needs me
  (saving, publishing), stop and tell me.
- Same icon style as the existing set in UIImages (look at Icon_Cash, Icon_Prod_QuickHint,
  Icon_Prod_Cash10Min, Icon_Gift): chunky, glossy, thick dark outline, bright saturated colours,
  readable at 40 x 40 pixels. Transparent PNG backgrounds. No text inside icons except "XP"/"2X".
- UI images upload the same way as before: upload the PNG, then set a STRING attribute on
  UIImages (name = key, value = "rbxassetid://<id>").

# PHASE 1 - IMAGES ONLY, THEN STOP
Save everything to output/codex-ui/ and show me:

1. **Menu mockups** (1920 x 1080 each, drawn over real screenshots of the game's menus) showing the
   restyled look for: FREE GIFTS, DAILY REWARDS, SHOP, PETS (Index tab) and the lobby HUD tiles.
   Keep the current layout and colours per menu (gold gifts, pink pets, purple shop...), but
   richer: a soft pattern in the menu body, stripes or dots on the coloured header, clearer
   cards. Two options (A, B) for the pattern style.
2. **Icon_XP** (256 x 256): a bright blue star badge with "XP" on it, for XP rewards. Also
   **Icon_Armful** (256 x 256): two arms hugging a small stack of three things (a sock, a toy
   car, a book), purple accent, for the ARM CAPACITY upgrade card (it shows "AR" until then).
3. **MenuPattern** (256 x 256, seamless tile): white shapes on transparent (tiny stars, dots or
   confetti - match option A/B). The game draws it over the dark menu body at 88% transparency,
   so it must be subtle and tile without seams.
4. **HeaderPattern** (128 x 128, seamless tile): white diagonal stripes or dots on transparent.
   The game lays it over each menu's coloured header bar at 80% transparency.
5. **Icon check**: a contact sheet of every icon the menus use (UIImages keys starting Icon_,
   Icon_Prod_, Bin_, Egg_, Gift_Box), marking any whose picture doesn't match its label, with a
   redraw for each one marked. In particular the rewards must read at a glance:
   Icon_Cash = cash, Icon_XP = XP, Icon_Prod_QuickHint = one clue (magnifier + "?"),
   Icon_Prod_SuperHint = a big reveal (magnifier + sparkle), Icon_Prod_Cash10Min = 2X cash,
   Icon_Prod_Strength10Min = 2X strength (arm).
6. **TIME PLAYED board ornament**: the new lobby board Workspace.Lobby.MostPlayedBoard (orange
   frame, Workspace.Lobby.BoardFrames.MostPlayedBoardFrame) still has the "1" ornament on top that
   it copied from TOP FINDERS. Draw a clock ornament for it in the same style as the others.

Show me all of it and STOP. Phase 2 starts only when I reply "APPROVED" with my picks.

# PHASE 2 - BUILD (only after "APPROVED")
1. Upload the approved Icon_XP, MenuPattern, HeaderPattern and every redrawn icon, and set the
   UIImages attributes (same keys; a redrawn icon replaces the old id on its existing key).
2. Nothing else is needed for the menus: the code picks the images up by key.
3. Replace the "1" ornament on MostPlayedBoardFrame with the clock ornament (built from meshes,
   same size and position as the ornament you replace). Don't move or resize the board or frame.
4. Test (Studio MCP only): start Play, open FREE GIFTS, DAILY, SHOP and PETS from the lobby tiles
   and capture each; open a room (workspace:SetAttribute("DevRun", "StartRoom 1 1")) and capture
   the HUD. Check the Output for image load errors. Stop Play.
5. Report the new asset ids per key, the captures, and remind me to save (Ctrl+S) and publish.
