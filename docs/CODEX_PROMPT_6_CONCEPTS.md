You are connected to Roblox Studio (place "1000 Hidden Objects", placeId 117675182630398).
The game just grew: 4 new rooms (#002 Kitchen, #003 Living Room, #004 Garage, #005 Giant Attic),
about 60 new objects, 7 new bins, 4 new hidden objects, 10 helper pets with eggs, a daily spin, free
gifts and new shop items. The code is finished and everything new currently shows as simple
placeholder shapes.

This job makes CONCEPT IMAGES ONLY for all of that art. Nothing gets built yet. When the images
are done you STOP and wait for my approval. A second prompt builds the approved art as real
3D models.

## Ground rules
- Do NOT create, change, upload or delete anything in Studio. The only Studio actions allowed are
  starting and stopping Play and taking screenshots.
- Never touch any script.
- Save every image to output/codex-expansion/concepts/ with exactly the file names below.
- Art direction for everything: REALISTIC, high-quality 3D, as if rendered from real game models
  with PBR materials (believable wood, fabric, metal, plastic, glass). Real-world proportions,
  soft natural light, subtle wear and dust where it fits. No flat cartoon look and no blocky
  "made of Parts" look: everything will be built as detailed meshes.
- It must still read well in a Roblox game: clear silhouettes, and colours that stand out
  inside a big pile of junk. The hidden objects are always the most eye-catching thing.
- No real brands, logos or copyrighted characters.

# STEP 1 - REFERENCES FROM THE GAME
1. Start Play. Start each new room from the Server datamodel with the Studio test hook:
   `workspace:SetAttribute("DevRun", "StartRoom 1 2")` (then `3`, `4`, `5` for the other rooms).
   (If you prefer, from the Client datamodel:
   `require(game.ReplicatedStorage.Shared.Utility.Remotes).Event("DevCommand"):FireServer("StartRoom", 1, 2)`.)
   Wait until ReplicatedStorage.MatchState attribute State = "Searching" and RoomId is right.
2. For each room capture: a wide shot from the door, a top-down shot, and each corner.
3. In the lobby, capture: the right-side menu buttons, and the PETS, SPIN, GIFTS and SHOP
   menus open (tap the buttons on the right).
4. Stop Play. Save the shots to output/codex-expansion/refs/.

# STEP 2 - THE IMAGES

## 1. Style board: StyleBoard.png (1920 x 1080)
The same 6 objects (plate, sneaker, teddy bear, toolbox, cardboard box, the Diamond Ring) and the
Dust Bunny pet, shown two ways side by side:
- A "Realistic": true-to-life materials and proportions.
- B "Soft realistic": realistic materials with slightly rounder, friendlier shapes (like a
  modern animated film).
Both sets sit in a small pile of junk so I can judge how they read. All other images below use A.

## 2. Room concepts: 2 options (A, B) per room
For each option: a wide shot from the door AND a top-down plan drawn over the real layout below.
File names: Room002_Kitchen_A.png, Room002_Kitchen_B.png, Room003_LivingRoom_A.png, ...,
Room005_Attic_A.png, Room005_Attic_B.png (1920 x 1080 each; put both views on one image).
The layouts are FIXED (room-local studs, origin = floor centre, door on the +Z wall). Only the
look changes. Keep walls and furniture a little calmer than the junk so the junk, the bins'
bright rims and the hidden object stand out.

### Room #002 "The Busy Kitchen" (90 x 70, 26 tall) - find Grandma's Diamond Ring
- Back wall: counters with the top at 3.6 studs. Left run x -35..-5 with the sink (a basin rim
  on the counter at x -23.6..-16.4), the stove x -5..1, a short run x 1..13, and a back counter
  x 20..40. Upper cabinets above. A window over the sink.
- Fridge in the back-left corner (x -44..-38, 11 tall).
- Walk-in pantry: tall shelves along the left wall (z -13..5), shelf tops at 3.2 / 6.2 / 9.2.
  A big open pantry crate in front of it (x -33.8..-26.2, z -7.8..-0.2).
- Kitchen island in the middle-back (x -15.5..3.5, z -12.5..-3.5, top 3.6) with two wobbly
  plate towers on it.
- Dining table on the right (x 15..29, z -8..0, top 3.25, closed to the floor, with a
  tablecloth and chairs).
- Breakfast nook on the right wall (table x 30..38, z 9..15, top 3; bench against the wall).
- Recycling corner front-right: a big open recycling crate (x 30.2..41.8, z 23.7..32.3).
- Bins: Dish Rack (-17.5, 30), Recycling (17.5, 30), Pantry Shelf (-33, 24), Trash (14, -16),
  Donation box (9, 31).
- Look: cream cabinets, mint tiles, a checkered floor, pendant lamps over the island.

### Room #003 "The Cozy Living Room" (90 x 70, 26 tall) - find the Golden TV Remote
- TV wall at the back: console x -10..10 (z -34.5..-30.5, top 2.6), a big TV above, speakers.
- Big sofa facing the TV: seat x -11..11, z -15.5..-8.5, seat top 2.2, back at z -8, arms at
  x = -12 and 12. The cushions piled on the seat are real junk.
- Coffee table x -5..5, z -24.5..-19.5, top 1.8.
- Fireplace on the left wall (x -45..-41, z -24..-12, 8 tall, mantel top 8.5, a chimney above).
- Bookcase on the right wall (z -16..4, 13 tall, shelf tops 3.5 / 6.5 / 9.5 / 12.5).
- Window seat in the back-right (x 28..40, top 2.4) under a window with curtains.
- The BLANKET FORT, front-left: sheet walls around x -26..-14, z 8..18 (4 tall), poles, and a
  sheet roof at 7.5. It is the deepest pile in the room.
- Game chest front-right (open, x 30.2..41.8, z 22.7..31.3). Plant box front-left
  (x -41.8..-32.2, z 21.7..30.3). A rug in the middle, fairy lights, a floor lamp.
- Bins: Laundry (-17.5, 30), Toys (17.5, 30), Book Cart (30, 8), Game Shelf (24, 18),
  Trash (-30, -8), Donation (9, 31).
- Look: warm wood, fireplace glow, a sleepover movie night.

### Room #004 "The Dusty Garage" (90 x 70, 30 tall) - find the Golden Wrench
- A covered car in the middle-back (body x -4.5..4.5, z -22..-6, 4.2 tall; cabin up to 6.8;
  a tarp over it), in front of a roll-up garage door on the back wall (26 wide).
- Workbench back-left (x -39..-21, z -34.5..-29.5, top 3.4) with a pegboard of tools above.
  A tool pegboard along the left wall too.
- Tall storage shelves along the right wall (z -20..4, 16 tall, 4 deep, shelf tops 4 / 8 / 12)
  with boxes on them. Box piles in front of them tumble when pulled.
- Bike rack back-right. A chest freezer on the right (x 34..43, z 5.5..10.5, top 3.4).
- Paint crate front-left (x -41.8..-30.2, z 22.7..31.3), sports crate front-right
  (x 30.2..41.8, z 21.7..30.3), a big junk box left-centre (x -18.3..-9.7, z 5.7..14.3).
- Bins: Toolbox (-17.5, 30), Sports Bin (17.5, 30), Recycling (28, 14), Trash (-26, -12),
  Donation (9, 31).
- Look: concrete floor with an oil stain, warm work lights, old posters.

### Room #005 "The Giant Attic" - MEGA ROOM (110 x 86, 32 tall) - find the Treasure Map
- Two levels. A loft along the back (z -43..-17), floor top at 10.5, a wooden rail along its
  front edge (x -43..43), three posts under it at z -18 (x -30, 0, 30), lamps under it.
- Ramps up both side walls: x 47..55 and x -55..-47, from z 7 (floor) up to z -17 (loft).
- Old steamer trunks you dig into: ground (-30, 4) and (26, 10); loft (-28, -32) and (26, -34).
- Wardrobe on the left wall (x -54.5..-50.5, z 15..25, 12 tall), a sheet-covered sofa in the
  middle (x -5..5, z 9..15, 4 tall), a dollhouse front-right (x 44..52, z 27.5..32.5, 6 tall),
  a rocking chair under the loft, a dress form, cobwebs, roof beams, and a dusty window above
  the loft with light shafts.
- Bins: Laundry (-20, 38), Toys (20, 38), Book Cart (38, 16), Trash (-12, -10),
  Donation (9, 39), and the Keepsakes trunk-bin UP ON THE LOFT (0, -22).
- Extra image: Room005_Attic_Loft.png, the view from the top of a ramp across the loft.

## 3. Object sheets (1920 x 1080 each, a labelled grid, 3/4 view, neutral background)
Each object is shown alone and labelled with its key and its size box (X x Y x Z studs).
- Clutter_Kitchen.png: Plate_A, Bowl_A, Mug_A, Fork_A, Spoon_A, FryingPan_A, CookingPot_A,
  CuttingBoard_A, CerealBox_A, Apple_A, Banana_A, Bread_A, EggCarton_A, MilkJug_A,
  GroceryBag_A, Wrapper_A, Toaster_A, Blender_A, Microwave_A.
- Clutter_LivingRoom.png: Cushion_A, SleepingBag_A, PopcornBucket_A, SnackBag_A,
  PictureFrame_A, FloorLamp_A, BoardGame_A, PuzzlePiece_A, GameDisc_A, GameConsole_A,
  PlantPot_A, Beanbag_A.
- Clutter_Garage.png: Hammer_A, Wrench_A, Screwdriver_A, TapeRoll_A, GardenHose_A, Helmet_A,
  Skateboard_A, BaseballBat_A, SoccerBall_A, PaintCan_A, OilyRag_A, CarTire_A, BikeWheel_A,
  OldToolbox_A.
- Clutter_Attic.png: OldLetter_A, PhotoAlbum_A, Lantern_A, Suitcase_A, HolidayBox_A,
  RockingHorse_A, Quilt_A.
- Treasures.png: Treasure_SilverSpoon, Treasure_MovieTicket (a golden movie ticket),
  Treasure_ToyCarGold (a vintage gold toy car), Treasure_PocketWatch, Treasure_OldCoin
  (a pirate coin). These glint and look valuable.
- HiddenObjects.png: the 4 hidden objects, each as a hero shot and as a "half-buried in junk"
  shot: Grandma's Diamond Ring, the Golden TV Remote, the Golden Wrench, the Treasure Map
  (rolled parchment with a red X). Same premium gold quality as the existing Golden Key.
- Bins_Containers.png: the 7 new bins, each with a bright rim in its colour so it reads from
  across a room: Dish Rack (light blue), Pantry Shelf (warm yellow), Recycling Bin (blue),
  Game Shelf (purple), Toolbox (red), Sports Bin (orange), Old Trunk "Keepsakes" (brown/brass).
  Plus the open containers: sink basin rim, pantry crate, recycling crate, blanket fort walls,
  game chest, plant box, paint crate, sports crate, junk box, and an open steamer trunk.

## 4. Pets (the helpers that follow the player and carry junk to the bins)
One turnaround sheet per pet: front, side, back and 3/4, plus a close-up of the face.
File names: Pet_<Key>.png. Each pet is cute and appealing in the realistic style (think of a
high-end animated film), about the size of a small dog next to a Roblox avatar.
| Key | Rarity (colour) | Idea |
|---|---|---|
| DustBunny | Common (silver) | a fluffy grey dust-ball bunny, pink inner ears, a tiny feather-duster tail |
| SockPuppy | Common (silver) | a puppy made from a white striped sock, button eyes |
| SoapSlime | Common (silver) | a translucent light-blue soap slime with bubbles inside and around it |
| MopPup | Uncommon (green) | a cream mop-haired dog (mop strings as fur), blue bandana |
| BroomBird | Uncommon (green) | a yellow bird with broom-bristle wings and tail (it flies) |
| LaundryFrog | Rare (blue) | a green frog with a clothespin on its head and a tiny laundry basket |
| VacuumCat | Rare (blue) | a grey cat with a vacuum-hose snout and a little canister body |
| DusterParrot | Epic (purple) | a red-and-blue parrot with a feather-duster crest (it flies) |
| RoombaTurtle | Epic (purple) | a turtle whose shell is a robot vacuum with a teal glowing ring |
| GoldenBroomDragon | Legendary (gold) | a small gold dragon riding a broomstick, orange wings, sparkles (it flies) |
- PetLineup.png: all 10 side by side to scale, with a Roblox avatar for size, each on a small
  platform in its rarity colour.
- Eggs.png: the Dusty Egg (tan, dusty), Shiny Egg (glossy cyan, sparkles), Royal Egg (purple
  with a gold crown band), Attic Egg (an antique egg with brass bands, only won in the attic),
  and a GiftBox (pink box, gold ribbon) used when a pet is a gift.
- PetAnimations.png: storyboard frames (4 to 6 keyframes each) of the 5 animations for the
  Dust Bunny, the Broom Bird and the Golden Broom Dragon:
  Idle (breathing, looking around), Walk (hopping or running; fliers flap and hover),
  Carry (clutching a piece of junk that hangs just below its body while it moves),
  Hatch (pops out of the egg or box, shakes itself off, looks around), Celebrate (a happy jump
  or spin).

## 5. UI images: UI_Icons.png
One sheet with every new icon, each drawn at 256 x 256 on transparent in the SAME style as the
game's existing icons (full colour, thick dark outline, readable at 24 px). Label each with its key.
- Menu buttons: Icon_Spin (prize wheel), Icon_Gift (gift box), Icon_Pets (paw print).
- Gift_Box (a gift box for the gift cards and pop-ups).
- Egg_Dusty, Egg_Shiny, Egg_Royal (egg pictures for the shop cards).
- Hidden objects: Icon_Ring, Icon_Remote, Icon_Wrench, Icon_Map (match the existing Icon_Key).
- Bins (match the existing Bin_Laundry badge style): Bin_DishRack, Bin_Pantry, Bin_Recycling,
  Bin_GameShelf, Bin_Toolbox, Bin_SportsBin, Bin_Keepsakes.
- Shop items: Icon_Prod_SpeedBoost10Min (sneaker with "2X" and a clock),
  Icon_Prod_DoubleXP15Min (blue "XP" star with "2X"), Icon_Prod_LiftItNow (a glove lifting a
  heavy box), Icon_Prod_JunkBlaster (a burst of junk), Icon_Prod_TreasureRadar (a radar with a
  gold blip), Icon_Prod_StarterPack (a gift crate with a pet paw), Icon_Prod_PetSnack (a pet
  treat bone), Icon_Prod_DoubleXP (a big "XP" with "2X"), Icon_Prod_RainbowTrail (a rainbow
  swoosh), Icon_Prod_PetVacuumCat, Icon_Prod_PetGoldenDragon (the pets' faces),
  Icon_Prod_PetSlot (a paw with a plus), Icon_Prod_FasterPets (a winged paw).
- Spin wheel: SpinWheel.png, a 1024 x 1024 round wheel face with 8 equal slices, the first
  centred at the top and going clockwise in this order: lime, cyan, green, purple, orange,
  pink, red, gold. NO text on it (the game writes the prizes). A gold rim with light bulbs.
  SpinPointer.png, 128 x 140, a pointer that points DOWN at the wheel.

## 6. Store art (files for Creator Hub)
- StoreArt.png: every game pass and product icon (512 x 512 each) in ONE consistent style: a bold
  realistic 3D object on a radial glow in the item's colour, a white outline. Colours:
  2x Cash lime (stack of bills), Stronger Hands orange (flexed glove), Fast Hands cyan
  (lightning glove), Throw Boost purple (arcing ball), VIP gold (crown with a magnifier),
  +1 Pet Slot pink (paw with a plus), Faster Pets teal (winged paw), 2x XP blue, Rainbow Trail
  rainbow, Vacuum Cat and Golden Broom Dragon (their faces, rarity colours). Products: 2x Speed,
  2x XP (15 min), Lift It Now, Junk Blaster, Treasure Radar, Starter Pack, Pet Snack.
  Show next to each how its shop card looks with a ribbon: BEST VALUE on VIP, POPULAR on 2x Cash,
  NEW PET on the pets.
- Badges.png: round 512 x 512 badges: Room002Speed (ring + stopwatch), Room003Speed (remote +
  stopwatch), Room004Speed (wrench + stopwatch), Room005Speed (map + stopwatch), Room005Clear
  ("Attic Explorer": a lantern and the map).

## 7. The lobby Pet Shop: Lobby_PetShop_A.png and Lobby_PetShop_B.png
Two ideas for a small pet shop corner in the current lobby: a sign, and three pedestals
with the Dusty, Shiny and Royal eggs on them (players walk up to a pedestal to hatch). One view
from the spawn and one close-up per idea. It must fit the lobby's current look (see your refs).

## 8. HUD_Mockup.png
Paint the new icons into a screenshot of the real lobby HUD (the 3 x 3 menu buttons on the
right with PETS, SPIN and GIFTS, the saved-Cash pill under the level badge, and the PLAY NOW
button at the bottom), so I can see them in place.

# STEP 3 - STOP
Show me every image with its file name. Then STOP and wait. The build starts only when I reply
"APPROVED" with my picks and changes (for example: "APPROVED: style A, Kitchen B, Living Room A,
Garage A, Attic B, Lobby Pet Shop A, make the Sock Puppy fluffier").

## Report back
The file list, and for each room option one line on what makes it different.
