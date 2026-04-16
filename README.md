# [B42] RV Interior Manager

A companion admin panel for **PROJECT RV Interior** (and its expansion mods). Gives server admins full visibility and control over every vehicle-to-room assignment in the save, with real-time position tracking, sorting, filtering, and manual assignment tools.

---

## Requirements

| Mod | Workshop ID |
|---|---|
| PROJECT RV Interior | [3543229299](https://steamcommunity.com/sharedfiles/filedetails/?id=3543229299) |

Optional but recognised:
- RV Interior Update 1 (rvupdate)
- RV Interior Update 2 (rvupdate2)

---

## Features

### Admin Panel
Open via the **RV Interior Manager** button in the Admin Panel (admin/moderator only).

**Availability summary table**
- One row per interior type (Normal, Bus, Small, Caravan, etc.)
- Shows room dimensions, total slots, occupied, and free counts for each type
- Click any column header to sort ascending/descending (`^` / `v` indicator)

**Assignments table**
- Lists every vehicle that currently has an interior room assigned
- Columns: Vehicle ID · Name · Vehicle Position · RV Type · Room Position · Linked At · Last Enter · Last Exit
- Click any column header to sort; click again to reverse
- Hover over any cell to see the full untruncated value in a floating tooltip

**Filter bar** (below the summary table)
- Search across: Car name, Vehicle ID, RV Type, Room location, Vehicle location, Linked At date, Last Enter, Last Exit
- Type any partial string to filter the assignments list in real time
- Type `-` to find records with empty fields (e.g. vehicles never entered)

**Action buttons**
- **Teleport to Vehicle** — teleports the admin to the vehicle's last known world position
- **Teleport to Room** — teleports the admin into the interior room
- **Dissociate** — frees the room assignment; the vehicle will need a new room before anyone can enter it again
- **Force Idle Check** — runs the idle room cleaner immediately instead of waiting for the next hourly cycle

### Manual Association (context menu)
Right-click any supported vehicle from outside → Associate Interior:
- **Random room** — assigns the next available slot automatically
- **Choose room…** — opens a room picker showing all free slots for that type with:
  - Region filter dropdown (Main / Update 1 / Update 2)
  - Coordinate search (type any partial X / Y / Z value)
  - Scrollable list with row selection; confirm to assign that specific room

### Sandbox Options

**Require Admin to Associate** (`Sandbox → RV Interior Manager → Require Admin to Associate Rooms`, default: **OFF**)

When enabled, only admins and moderators can associate a room to a vehicle. Regular players who try to enter an RV that has no room assigned are blocked before the teleport happens and receive an on-screen message. They stay in the world until an admin associates the vehicle.

**Idle Room Cleaner** (`Sandbox → RV Interior Manager → Idle Cleanup Days`, default: **0 = disabled**)

Automatically dissociates rooms that have not been entered for the configured number of real-world days.
- Uses `lastEnterDate` as the reference; falls back to `dateLinked` if the vehicle was never entered
- Runs once on world load and every ~60 minutes during the session
- Every dissociation is written to `~/Zomboid/Logs/RVM_IdleCleanup.log` with full details (rvId, vehicle name, type, room coords, vehicle position, dates, days idle)

---

## How the Sync Works

The base mod stores all assignments in a single shared `ModData` table (`modPROJECTRVInterior`). This manager mod builds its own denormalized table (`RVInteriorManager`) on top of it.

```
Base mod ModData                      Manager ModData
─────────────────────────────────     ──────────────────────────────────────
AssignedRooms[vehicleId] = {x,y,z}   relationships[vehicleId] = {
AssignedRoomsbus[vehicleId] = ...       typeKey, room, lastPos,
Vehicles[vehicleId]  = {x,y,z}         dateLinked, lastEnterDate,
Players[playerId]    = {...}            lastOutDate, vehicleName
                                      }
```

**Position tracking — dirty flag + periodic flush**
1. Every ~1 second the server compares `modData.Vehicles` (updated by the base mod's `UpdateVehPos` client tick) against an in-memory cache.
2. Vehicles that moved more than 0.5 tiles are flagged as dirty.
3. Every ~10 seconds only the dirty positions are written to `RVInteriorManager`. Vehicles that haven't moved generate zero writes.

**Date tracking**
When a player enters or exits a vehicle interior, the server records the timestamp in `relationships[vehicleId].lastEnterDate / lastOutDate`. Newly associated vehicles get a `dateLinked` timestamp.

**Vehicle name caching**
The vehicle script name is captured the moment the player enters (while the chunk is loaded) and cached in the relationship so it remains readable even after the chunk unloads.

---

## Multiplayer Flow

```
Player (client)                     Server
──────────────────                  ──────────────────────────────────────────
Radial menu "Enter RV"
  sendClientCommand ──────────────► RVMServer wraps GetInToRV:
                                      • RequireAdminToAssociate ON?
                                        • Room already assigned? → allow
                                        • Not admin/mod?        → deny (accessDenied)
                                      • Otherwise → GetInToRV (base mod):
                                          assigns room if needed
                                          sendServerCommand ──► teleportToRoom
◄────────────────────────────────── accessDenied / teleportToRoom

Admin right-clicks vehicle
  sendClientCommand "associate" ──► RVMServer.associate()
                                      normalise numeric/string key
                                      guard against duplicates
                                      write to base mod's AssignedRooms (string + numeric key)
                                      set projectRV_uniqueId on server vehicle object
                                      update relationships table
                                      sendServerCommand ──► associateResult
◄────────────────────────────────── associateResult (ok / error)
```

---

## Short FAQ

**Game version:** B42 Unstable (latest)  
**Multiplayer:** Yes  
**Added midgame:** Yes — pre-existing room assignments will show up in the panel immediately. Some fields (vehicle name, last position) will populate as vehicles are loaded into the world. The **Linked At** date is the only field that cannot be recovered retroactively; it will be set to the first enter/exit event recorded after this mod is installed.

---

## Technical Information

| | |
|---|---|
| Workshop ID | 3704055215 |
| Mod ID | rvinteriormanager |
| Version | 0.2 |
| Build | 42.16+ |

---

## Permissions for Modders

**Ask for permission.**

This mod may **not** be included in modpacks, collections distributed as a single download, or any form of redistribution without the express permission of the original creator. Extensions and patches are also subject to this restriction. Having received permission, credit must be given to the original creator both within the mod files and wherever the mod is published online.

---

## CI/CD — Steam Workshop Publishing

Pushes and merged PRs to `main` automatically publish the mod to the Workshop via GitHub Actions ([`.github/workflows/steam-publish.yml`](.github/workflows/steam-publish.yml)).

### Required GitHub Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret | Value |
|---|---|
| `STEAM_USERNAME` | Steam account username (dedicated deploy account recommended) |
| `STEAM_PASSWORD` | Steam account password |
| `STEAM_TOTP` | Steam Guard shared secret (base32) for TOTP generation |

> **Tip:** Use a dedicated Steam account that co-owns the Workshop item instead of your personal account. To get the `STEAM_TOTP` shared secret, use a tool like [SteamTimeIdler](https://github.com/nicklvsa/go-steam-totp) or export it from the Steam mobile authenticator.

### What gets uploaded

The `42/` folder is uploaded as the mod content. `poster.png` is used as the Workshop preview image. The changenote is auto-generated from the last 10 commit messages.

---

## Tested On

Dedicated server (Linux) · Build 42.16+

---

## Known Issues

- **Context menu shows "Associate" on an already-assigned vehicle (pre-existing worlds).** This can happen the first time you right-click a vehicle whose chunk has not been loaded since the mod was installed — the client's local cache hasn't synced yet. Simply right-clicking a second time will show the correct **Dissociate** option. No data is lost.
