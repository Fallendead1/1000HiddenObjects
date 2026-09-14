You are connected to Roblox Studio (place "1000 Hidden Objects", placeId 117675182630398).
This job makes store art only: 3 thumbnails and 1 game icon. It runs in phases, and you STOP for
my approval before the final versions.

## Ground rules
- Never create, edit or delete any script, and don't change anything in the place. The Studio
  steps below only play the game and take screenshots.
- Upload nothing. I put the icon and thumbnails on Roblox myself.
- Save everything under output/creator-hub/. Do NOT overwrite the older Thumbnail_1/2/3.png or
  GameIcon.png files.

# PHASE 1 - REFERENCES
1. In-game references (so the art looks like the real game):
   - Start Play. From the Client datamodel run:
     `require(game.ReplicatedStorage.Shared.Utility.Remotes).Event("DevCommand"):FireServer("StartRoom", 1, 1)`
     and wait until ReplicatedStorage.MatchState.State = "Searching".
   - Capture: a first-person view of the biggest pile, a wide view of the whole messy bedroom,
     each of the 5 bins, and a close-up of the Golden Key. To reveal the key, fire DevCommand
     "TargetInfo" (the Output prints where it is), then DevCommand "BurstKeyChunk".
   - Stop Play. Save the shots to output/creator-hub/refs/.
2. I attached two screenshots of the Roblox home page. Study these tiles and what makes them work:
   - "Look for the Needle" and "Search For The Needle": the closest games to ours (a search in a
     giant pile). A magnifier, a huge haystack, one clear prize.
   - "Clean all the leaves!": one enormous pile fills the frame, so you get the idea instantly.
   - "Load The Truck!": a low camera makes stacks of boxes look massive.
   - "Greedy Growers", "+1 Chop Trees for Treasure": a huge number or "$" callout, and a big arrow.
   - The admin/shushing tile: a big red arrow plus one expressive face.
   - "Dropshipping Tycoon": a before/after split.
   - "Find The Hidden Object": a flat green baseplate with 0 players. This is what NOT to do.
   Common to the winners: ONE clear subject, bright saturated colours, a background that
   contrasts with the subject, big simple shapes, 0-3 words of huge text, and readable at tile size.

# PHASE 2 - DRAFTS, THEN STOP
Make 2 variations (A and B) of each thumbnail and 3 variations (A, B, C) of the icon. Then make
HomeFeedPreview.png: put Thumbnail_1_A and _B into a copy of my home-page screenshot at the same
tile size (about 250 x 140), plus the icons at 100 x 100, so I can see whether they stand out.
Show me everything and STOP. Phase 3 starts only when I reply "APPROVED" with my picks and any
changes (for example "APPROVED: T1 A, T2 B with bigger text, T3 A, Icon C").

## Style for all images
- A glossy Roblox 3D-render look: blocky Roblox-style avatars with big expressive faces, soft
  studio light with a strong rim light, rich saturated colour. Generic avatars only: no real
  players, no famous characters.
- The GOLDEN KEY is the focal point of every image: the brightest, warmest thing, with a white-gold
  glow, sparkles and light rays.
- Backgrounds contrast with gold: sky-blue or teal bedroom walls, purple shadows. Don't let beige
  boxes take over. Fill the piles with colourful junk: red/blue/green clothes, toys, pizza boxes,
  books, sneakers, plushies.
- Text: 0-3 words per image, a huge chunky font, white or yellow with a thick dark outline. It must
  read at 256 x 144. Keep everything important away from the outer 5% of the image.
- Honest to the game. Show only things that exist in it: the messy bedroom, piles of junk, the 5
  bins (blue Laundry Basket, pink Toy Bin, orange Book Cart, green Trash Can, brown Donation Box),
  "+$" cash popups, the Golden Key, and up to 4 players.
- Roblox rules: no Robux symbol, no "FREE", no fake Roblox buttons or ratings, no "#1" claims, no
  real brands or logos, no weapons or violence.

## Thumbnails - 1920 x 1080 PNG (16:9)
Thumbnail_1 - "THE HUNT" (the most important one: it's what shows on the Roblox home page)
- A Roblox avatar buried waist-deep in a MOUNTAIN of colourful junk in a kid's bedroom, mouth wide
  open in shock, pulling a glowing Golden Key out of the pile. Light rays and sparkles burst from
  the key.
- Use a low camera so the pile reaches the ceiling, and a big red curved arrow pointing at the key.
- A: text "FIND IT!" in the top-left. B: no words, only a gold "1 / 1000" badge in the top-right.

Thumbnail_2 - "CLEAN FOR CASH"
- A: An avatar mid-throw, a shirt flying along a dotted arc into a glowing blue Laundry Basket.
  "+$50" and "SWISH!" pop out in gold and green, coins spray around, and more junk flies into the
  pink Toy Bin and green Trash Can behind. Text: "CLEAN IT!"
- B: A before/after split. On the left, "MESSY": a dim room piled to the ceiling. On the right,
  "CLEAN!": a bright sparkling room with the Golden Key glowing on the floor and the avatar
  cheering. A white lightning-bolt divider between them.

Thumbnail_3 - "FRIENDS + KEY BURST"
- 4 Roblox friends around a giant pile. A packed bundle of junk EXPLODES and the Golden Key bursts
  out in a shower of junk, light rays and confetti. The friends react: pointing, jumping,
  cheering.
- A: text "WITH FRIENDS!". B: no text; the key and burst get more of the frame.

## Game icon - 512 x 512 PNG
Roblox shows the icon as small as about 100 x 100 and rounds its corners, so keep everything
inside the central 85% and make it bold. No text, except the number in variant C.
- A: a close-up of a shocked Roblox avatar face (huge eyes, open mouth) popping out of a
  colourful junk pile, holding a glowing Golden Key next to its face. Sky-blue background with
  soft light rays.
- B: just the Golden Key bursting up out of a junk pile, with big rays and sparkles on a
  sky-blue background.
- C: a chunky gold "1000" where one zero is the key's ring, over a small colourful junk pile.
  The same style as the game Logo.

# PHASE 3 - FINALS (after "APPROVED")
Polish the approved picks at full size with my changes. Save them as Thumbnail_1_Final.png,
Thumbnail_2_Final.png, Thumbnail_3_Final.png and GameIcon_Final.png in output/creator-hub/.
Also save each at tile size (256 x 144, and the icon at 150 x 150) so I can check readability.

## Report back
The file list with sizes, the reference shots you used, and a one-line reason for each pick.
