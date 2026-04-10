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
Open via the **RV Interior Manager** button in the radial menu (admin/moderator only).

**Availability summary table**
- One row per interior type (Normal, Bus, Small, Caravan, etc.)
- Shows total slots, occupied, and free counts for each type
- Click any column header to sort ascending/descending (`^` / `v` indicator)

**Assignments table**
- Lists every vehicle that currently has an interior room assigned
- Columns: Vehicle ID · Name · Vehicle Position · RV Type · Room Position · Linked At · Last Enter · Last Exit
- Click any column header to sort; click again to reverse
- Hover over any cell to see the full untruncated value in a floating tooltip

**Filter bar** (below the summary table)
- Search across: Car name, Vehicle ID, Room location, Vehicle location, Linked At date, Last Enter, Last Exit
- Type any partial string to filter the assignments list in real time

**Action buttons per row**
- **Teleport to Vehicle** — teleports the admin to the vehicle's last known world position
- **Teleport to Room** — teleports the admin into the interior room
- **Dissociate** — frees the room assignment; the vehicle will need a new room before anyone can enter it again

### Manual Association (context menu)
Right-click any supported vehicle from outside → Associate Interior:
- **Random room** — assigns the next available slot automatically
- **Choose room…** — opens a room picker showing all free slots with region filter (Main / Update 1 / Update 2) and coordinate search; confirm to assign that specific room

### Sandbox Option — Require Admin to Associate
`Sandbox → RV Interior Manager → Require Admin to Associate Rooms` (default: **ON**)

When enabled, only admins and moderators can associate a room to a vehicle. Regular players who try to enter an RV that has no room assigned are blocked before the teleport happens and receive an on-screen message. They stay in the world until an admin associates the vehicle.

---

## How the Sync Works

The base mod stores all assignments in a single shared `ModData` table (`modPROJECTRVInterior`). This manager mod builds its own denormalized table (`RVMPositionData`) on top of it.

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
3. Every ~10 seconds only the dirty positions are written to `RVMPositionData`. Vehicles that haven't moved generate zero writes.

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
                                      write to base mod's AssignedRooms
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
| Workshop ID |  3704055215 |
| Mod ID | rvinteriormanager |
| Build | 42.16+ |

---

## Permissions for Modders

**Ask for permission.**

This mod can only be added to and extended with the express permission from the original creator. Having received permission, credit must be given to the original creator, both within the files of the mod and wherever the mod roams online. If no permission is received you may not alter the mod.
