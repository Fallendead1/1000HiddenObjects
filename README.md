# 1000 Hidden Objects

Roblox game: 1–4 players enter a private room packed with clutter, physically clear it, upgrade their searching, and uncover the ONE hidden object. 1,000 rooms, 1,000 objects.

This repository contains the complete game foundation plus **Room #001 – The Messy Bedroom (Golden Key)**. Rooms #002–#1000 are added as data, not code.

## Getting started

Requires [Rokit](https://github.com/rojo-rbx/rokit) (installs Rojo 7.7).

```bash
rokit install
rojo serve
```

Open the place in Roblox Studio, connect the Rojo plugin, and press Play. With `LobbyPlaceId` / `MatchPlaceId` = 0 the server runs in **Combined** mode: lobby + local matches in one place, no teleports needed.

To build a standalone place file instead:

```bash
rojo build -o "1000 Hidden Objects.rbxlx"
```

## Project layout

```
src/shared     ReplicatedStorage.Shared  – configs (GameConfig, UpgradeConfig, MonetizationConfig,
                                             AudioConfig, UIConfig, RoomConfigs/Room001), TargetData, utilities
src/server     ServerScriptService.Server – Bootstrap + Services (Data, Queue, Teleport, Match, Room, Search,
                                             Economy, Upgrade, Hint, Monetization, Leaderboard, Checkpoint, Dev)
                                           + Builders (placeholder lobby/room/target) + RoomValidator
src/client     StarterPlayerScripts.Client – Controllers (HUD, Search, Upgrades, Shop, Collection, Hints, FX,
                                             Loading/Intro, Results, Tutorial, Lobby boards, Dev panel) + UI toolkit
```

## Development mode

`GameConfig.DevelopmentMode = true` and Studio enable the **DEV** panel (bottom-left):
start Room #001 with any party size, add cash, set room progress, reveal / complete, validate the room,
mock any gamepass / product, reset save data. Missing product/place IDs never block testing.

## Manual setup before production

Edit `src/shared/Config/GameConfig.luau` and `MonetizationConfig.luau`:

- `LobbyPlaceId`, `MatchPlaceId` (publish two places; the match place should be a reserved-server only place)
- Gamepass IDs: DoubleCash, AutoSell, BigBag, FastSearch, WiderReach, VIP
- Developer Product IDs: QuickHint, SuperHint, SearchPower10Min, Cash10Min, TeamSearchSurge, TrashBomb
- Optional Badge IDs
- Audio IDs in `AudioConfig.luau`
- Enable Studio API access in Game Settings to test DataStores in Studio (memory fallback otherwise)

## Adding Room #002

1. Create `src/shared/Config/RoomConfigs/Room002.luau` (copy Room001, change Id/Name/Target, regions, clusters,
   sockets, hint areas). 30+ target sockets required.
2. Register it in `src/shared/Config/RoomConfigs/init.luau`.
3. Add the target to `src/shared/Data/TargetData.luau` (`[2] = { Id = "...", Name = "...", ... }`).
4. (Optional) Drop a final room model at `ServerStorage.Rooms.Room002` following the tagged model contract
   described in `src/server/Builders/PlaceholderRoomBuilder.luau`, and a target model at `ServerStorage.Targets.<TargetId>`.
   Without them, placeholder geometry is generated from the config.
5. Run **Validate Room** from the DEV panel and fix any reported errors.

No gameplay scripts change.
