# Changelog

## [0.6] — 2026-05-09

### Added
- **Vehicle Type Editor** — new tab in the admin panel ("Room Types") lets admins add or remove vehicles from each interior type without restarting the server:
  - Select a type to see its compatible vehicle list with status badges
  - **Mod active** (green) — script is present in loaded mods
  - **Mod not found** (orange) — script is in the type list but the mod is not installed on the server
  - Add entries by script name (`Base.ScriptName`), remove with the × button
  - **Restore Default** button resets all type overrides back to the original mod values
  - Changes are persisted to `vehicles_type_changes.lua` and survive world wipes
- **Cross-search panel** — type part of a vehicle script name to instantly see which types it belongs to across all mods
- **Size column** in the type list (room dimensions, e.g. `8x4`)
- **Tooltips** on every action button and the script name input field

### Fixed
- **"Mod active" badge showing for uninstalled mods** — the server was accumulating all ever-seen vehicle scripts in ModData and never clearing stale entries. The list is now built fresh from `ScriptManager` on every request; uninstalled mods are no longer falsely reported as active.
- **Re-added vehicle losing its RV option** — after removing a vehicle from a type and re-adding it, the context menu "Associate" option and the radial menu "Enter RV" did not reappear. Root cause: override application was incremental and could leave inconsistent state. Fixed with `applyAllOverridesClean`, which always rebuilds scripts from the saved standard baseline so the result is deterministic regardless of how many add/remove cycles were performed.
- **Context menu not reflecting script changes** — `getRVTypeKeys` was calling `require("RVVehicleTypes")` which can return a stale cached reference. The context menu now uses `clientScriptsState`, a module-level table populated directly from the server's `adminSync` event, bypassing the require cache entirely.
- **Radial menu not reflecting script changes** — `adminSync` was patching `RV.VehicleTypes` via `require`, which could resolve to a different reference than the one the base mod uses. Fixed: the handler now patches the global `RV` directly, ensuring the base mod's own radial menu check also sees the updated scripts list.
- **Admin panel resetting type selection on every script add/remove** — adding or removing a vehicle from a type triggered a full server `requestData`, causing `receiveData` to reset the selected type, scroll position, and page. Script changes no longer trigger a refresh (the `adminSync` event already updates the panel in place); dissociate and associate refreshes now preserve the current type selection.
- **Removed `showRadialMenu` wrapper** — our wrapper around the base mod's radial menu was causing a crash when the *Protect Vehicle* mod was active (`__add not defined`). The wrapper is removed; vehicles that still have a room assigned but whose script was removed from all type lists will show **Dissociate** in our context menu as before.

### Changed
- `applyScriptOverrides` (shared module) removed — all override application now goes through `applyAllOverridesClean` on the server side.

---

## [0.3] — 2026-04-26

### Fixed
- **Room Picker — free room count wrong**: the picker and context menu were showing all rooms as free because the client-side ModData was never populated on first load. Replaced the local-cache approach with a server-side `getFreeRooms` command that returns authoritative data.
- **Room Picker — count stale after associate/dissociate**: `freeRoomCache` is now invalidated on `associateResult` and `dissociateResult` so the next right-click always fetches a fresh count.
- **Room Picker — scroll direction inverted**: `onMouseWheel` was using `- del`; corrected to `+ del` to match the admin panel convention.

### Changed
- **Context menu pre-fetch**: `getFreeRooms` is now sent to the server at right-click time (when an unassigned RV is detected), so by the time the admin clicks "Choose Room" the data is already cached and the picker opens instantly without a loading state.
- **Room Picker — cache structure**: `freeRoomCache[typeKey]` now stores `{ count, rooms }` together, removing the need for a separate count cache and rooms cache.

---

## [0.2] — 2026-04-15

### Added
- **Idle Room Cleaner** — new sandbox option `IdleCleanupDays` (integer, 0–365, default 0 = disabled):
  - Automatically dissociates rooms with no interaction for the configured number of real-world days.
  - Uses `lastEnterDate` as the reference; falls back to `dateLinked` if the vehicle was never entered.
  - Runs once on world load and every ~60 minutes during the session.
  - Logs every dissociation to `~/Zomboid/Logs/RVM_IdleCleanup.log` with full details (rvId, name, type, room coords, vehicle position, dates, days idle).
- **Force Idle Check** button in the admin panel — triggers the idle cleaner immediately without waiting for the hourly cycle.
- **Room Picker** — "Choose room…" context menu option opens a picker panel with region filter (Main / Update 1 / Update 2), coordinate search, and a scrollable numbered list; confirm to assign a specific room.
- **Column sorting** — click any header in the summary or assignments table to sort ascending/descending; active column shows `^` / `v` indicator.
- **Floating tooltip** — hover over any assignments table cell to see the full untruncated value.
- **RV Type filter** — new field option in the admin panel filter bar, filtering by `typeKey`.
- **Bootstrap date stamping** — pre-existing assignments with no `dateLinked` are stamped with the server start time on first load, giving the idle cleaner a baseline for all vehicles.

### Fixed
- **MP: room not found on enter** — the base mod's `ensureVehiclePersistentId()` could generate a new random ID before the client's value synced to the server, breaking the room lookup on enter. The server now force-sets `projectRV_uniqueId` directly on the vehicle object at association time by scanning loaded vehicles by world position.
- **MP: dual-key storage** — room assignments are now written under both string and numeric keys in ModData so the base mod finds them regardless of which key format it uses internally.
- **Dissociate** now clears all key variants (string, numeric, original) from `AssignedRooms`, preventing ghost entries.
- **Context menu crash** (`RVMContextMenu.lua`): `context:setOptionEnabled()` does not exist in B42. Replaced with `opt.notAvailable = true`.
- **Sandbox option translation**: raw key was displayed in the sandbox panel. Fixed: removed stale `.txt` translation files (B42.15+ only reads `.json`), fixed double-prefix bug (`Sandbox_Sandbox_RVM_...` → `Sandbox_RVM_...`), corrected option name to `RVM.RequireAdminToAssociate`.
- **Scroll direction inverted** in admin panel: `onMouseWheel` was subtracting the delta instead of adding it. Fixed for both the summary table and the assignments table.
- **Filter field labels** renamed to match assignments table column names: "Car" → "Name", "Room Loc" → "RV Pos", "Vehicle Loc" → "Veh. Pos", "Linked At" → "Linked".

### Changed
- Translation files migrated: sandbox keys moved exclusively to `Sandbox.json` (B42.15+ format). Stale `.txt` files removed.

### Project
- Added `.gitignore` to exclude `.claude/` and `CALUDE.md` / `CLAUDE_rvupdate.md` from version control.

---

## [0.1] — 2026-04-10

Initial release.

- Admin panel with availability summary and assignments table
- Teleport to vehicle / Teleport to room / Dissociate actions
- Context menu association (random room) and dissociation
- Sandbox option: Require Admin to Associate
- Real-time vehicle position tracking (dirty-flag + periodic flush)
- Date tracking: Linked At, Last Enter, Last Exit
- Vehicle name caching across chunk loads
- Support for PROJECT RV Interior + Update 1 + Update 2
