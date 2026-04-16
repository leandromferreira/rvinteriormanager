# Changelog

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
