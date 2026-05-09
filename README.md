# [B42] RV Interior Manager

A companion admin panel for **PROJECT RV Interior** (and its expansion mods). Gives server admins full visibility and control over every vehicle-to-room assignment in the save, with real-time position tracking, sorting, filtering, and manual assignment tools.

---

## Requirements

| Mod | Workshop ID |
|---|---|
| PROJECT RV Interior | [3543229299](https://steamcommunity.com/sharedfiles/filedetails/?id=3543229299) |

Optional but recognised:
- [RV Interior Expansion \[B42\]](https://steamcommunity.com/sharedfiles/filedetails/?id=3618427553)
- [RV Interior Expansion Part 2 \[B42\]](https://steamcommunity.com/sharedfiles/filedetails/?id=3622163276)
- [RV Military Addon \[B42\]](https://steamcommunity.com/sharedfiles/filedetails/?id=3614959302)

---

## Features

### Admin Panel
Open via the **RV Interior Manager** button in the Admin Panel (admin/moderator only).

#### Room Types tab

**Type list** (left panel)
- One row per interior type with room dimensions (e.g. `8x4`) and slot counts (total / available / occupied)
- Select a type to edit its compatible vehicle list on the right
- Search field to filter types by name
- **Restore Default** button resets all type overrides to the original mod values; changes persist across world wipes

**Compatible vehicles** (right panel — shown when a type is selected)
- Lists every vehicle script assigned to the selected type
- Each entry shows a status badge:
  - **Mod active** (green) — the mod that provides this vehicle is installed on the server
  - **Mod not found** (orange) — the script is in the list but the mod is not installed; players cannot use it
- Add a vehicle by typing its script name (`Base.ScriptName`) and clicking **Add**
- Remove any vehicle with the **×** button
- Changes take effect immediately — no server restart needed

**Cross-search** (bottom-right)
- Type part of any vehicle script name to see every interior type it belongs to across all installed mods

> **Important:** if a vehicle is removed from all type lists while it still has a room assigned, players can no longer enter that RV. The room stays reserved until an admin **Dissociates** it from the context menu. The vehicle must be re-added to a type and re-associated before it becomes usable again.

#### Linked Vehicles tab

**Assignments table**
- Lists every vehicle that currently has an interior room assigned
- Columns: Vehicle ID · Name · Vehicle Position · RV Type · Room Position · Linked At · Last Enter · Last Exit
- Click any column header to sort ascending/descending; click again to reverse
- Hover over any cell to see the full untruncated value in a floating tooltip

**Filter bar**
- Search across: Name, Vehicle ID, RV Type, Room position, Vehicle position, Linked At, Last Enter, Last Exit
- Type any partial string to filter in real time
- Type `-` to find records with empty fields (e.g. vehicles never entered)

**Action buttons** (all with tooltips)
- **Teleport to Vehicle** — teleports the admin to the vehicle's last known world position
- **Teleport to Room** — teleports the admin into the interior room
- **Dissociate** — frees the room assignment
- **Force Idle Check** — runs the idle room cleaner immediately instead of waiting for the next hourly cycle

### Context Menu (right-click a vehicle)
Available to admins and moderators when right-clicking a supported vehicle from outside:

- **Associate RV Interior** — appears when the vehicle's script is in at least one type list and has no room assigned:
  - **Random room** — assigns the next available slot automatically
  - **Choose room…** — opens a picker with region filter (Main / Update 1 / Update 2), coordinate search, and a scrollable numbered list; confirm to assign a specific room
- **Dissociate RV Interior** — appears when the vehicle has an assigned room; frees the slot regardless of whether the vehicle is still in any type list

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
| Version | 0.6 |
| Build | 42.17+ |

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
