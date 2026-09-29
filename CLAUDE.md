# Passagio

**Naming:** the app is called **Passagio** (home screen / App Store). Internal names stay `itinero` — bundle IDs
`com.matt.itinero`(+`.widget`), module/folders, iCloud container, repo — so the name can change again without
re-registering IDs. User-visible strings use `AppName.display` (`Shared/AppName.swift`); the store name is set in App
Store Connect. Earlier names TripTrac and Itinero were taken.

Native iOS app (SwiftUI + SwiftData, iOS 17+) for planning and tracking trips and their itineraries —
both cruises and land trips. First real use: a 7-person family trip to Japan, Nov 13–27 2026.

Read `DESIGN.md` (visual language) and `PREFERENCES.md` (how I like to work) before making changes.
Both are living documents: extend, don't replace.

## Project conventions (the `[ ]` fills from PREFERENCES.md)

- **Build system:** `project.yml` (XcodeGen) is the source of truth. `Itinero.xcodeproj` is generated and
  git-ignored — run `xcodegen generate` after adding/removing files. No manual pbxproj registration.
- **Xcode Cloud:** `ci_scripts/ci_post_clone.sh` installs XcodeGen and generates the project on the runner (the
  `.xcodeproj` is git-ignored). The git-ignored `private/japan-2026.json` is not in cloud builds, so a cloud/TestFlight
  build starts empty: import the itinerary from the JSON file (AirDrop → Trips → + → Import file).
- **Build / test:**
  `xcodebuild test -project Itinero.xcodeproj -scheme Itinero -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`
  Claude *can* build and run in the simulator in this project — verify there, not only by reading the diff.
- **Git:** feature branch `feature/<topic>` → PR → merge into `main`. Merge finished batches without being
  asked. New commits, never amend; never force-push shared history. Commit/PR text explains *why*, and
  contains no AI model name or attribution lines.
- **CI:** none yet. Once TestFlight builds exist, keep a cumulative "What's new / what to test" note in
  `docs/TESTFLIGHT_NOTES.md` since the last uploaded build.
- **Bundle ID:** `com.matt.itinero`. Signing: automatic, team X796Z5UW4P. Release: `tools/release.sh` (bump `CURRENT_PROJECT_VERSION` first).
- **Personal data:** real itinerary data (confirmation numbers, addresses) lives in `private/` (git-ignored)
  or in the app's own store — never in committed source, fixtures, or tests. Tests use fake data.

## Architecture

- `Itinero/DesignSystem/` — components from DESIGN.md. `StatusTone` + `statusTone(for:daysUntil:)` is the
  *only* place status→color is decided. Add new components here, with accessibility built in.
- `Itinero/Logic/` and `TripLogic.swift` — pure business logic, no SwiftUI/SwiftData, unit-tested in
  `ItineroTests/` in the same batch of work:
  - `ItineraryLogic`: per-day ordering (by each item's *own* time zone wall clock), traveler filtering,
    booking summary, next-up. Works on the `Schedulable` protocol so tests use plain structs.
  - `SiteImporter`: parses the JSON export of the family itinerary web page into `ParsedTrip` and reports
    anything odd as `ImportWarning`s instead of guessing. Format: `docs/IMPORT_FORMAT.md`.
  - `TripLogic`: phase, countdown, day count. Trip dates are midnight in the *trip's* zone; use
    `Trip.localStart/localEnd` (re-anchored to the device calendar) for "days until" and "underway".
- `Itinero/Models/` — SwiftData: Trip → Day → ItineraryItem, Trip → Traveler, item ⇄ attendees (many-to-many;
  **empty attendees = whole group**). Schema is CloudKit-compatible on purpose (defaults everywhere, optional
  relationships, stable `id`, no unique constraints) because Phase 4 shares trips via CloudKit.
  `ItemDraft` is the value copy used by the editor and by delete-with-undo. `ImportApplier` writes a
  `ParsedTrip` into the store (a trip with the same name + start date counts as already imported).
- Phase 2 logic (all pure + tested in `Phase2LogicTests`): `ScheduleIssues` (overlaps between travelers who share
  an item, booked stay without check-out), `BudgetLogic` (per-currency totals, cost split across attendees),
  `BookingGroups` (urgent/later/undated), `MapLinks` + `LinkNormalizer`, `SearchLogic`, `TimeDisplay` (item time vs
  "your time", friendly zone names), `PortLogic` (all-aboard alert tone), `ItineraryLogic.runState/progress`.
- `isDone` is a flag independent of `BookingStatus` (a booked item stays booked when it's done).
- Map pins: `DayMapView` finds coordinates with `MKLocalSearch` and caches them on the item; editing the place
  clears the cache. They are approximate by nature — the UI says so.
- Trip hub tiles open sections via `TripSection` + `navigationDestination(item:)`; lists use Buttons (not tap
  gestures) so rows are real buttons for VoiceOver.
- Phase 5: `TripSnapshot` is the portable value copy of a whole trip (JSON backup/restore, text + ICS export, and
  the shape Phase 4 maps to CloudKit records). Restoring never overwrites an existing trip id.
  `ReminderPlanner` (pure) plans local notifications (max 60 pending); `Services/AppSync` writes the widget feed
  (`Shared/NextUpSnapshot.swift`, read by the `ItineroWidget` extension via the `group.com.matt.itinero`
  App Group) and schedules reminders every 30 s / on foreground. "I'm traveling as" (Settings) filters both.
- Phase 4 (family sharing, opt-in per trip): SwiftData can't share across iCloud accounts, so trips are mirrored to
  CloudKit with `CKSyncEngine` (`Services/CloudSync`): one record zone per trip, records Trip/Traveler/Day/Item/Check
  (`Logic/CloudRecords` — pure mapping, fingerprints, diff plan, last-writer-wins; tested), trip record shared via
  `CKShare`. Local edits are detected by diffing content fingerprints (`reconcile()`, every 30 s) — SwiftData has no
  change hooks. Remote records apply through `Models/CloudApply` (upserts by id). Rules: remote changes never delete a
  whole trip; an ended share keeps the local copy; deleting a trip here tombstones it and never deletes the shared
  copy; only records previously synced can be deleted by sync. Coordinates (map-pin cache) never sync.
  **Not yet verified end-to-end** (needs two iCloud accounts on real devices) — see docs/FAMILY_SHARING_TEST.md.
- Signing: automatic, team X796Z5UW4P. Capabilities (iCloud/CloudKit container `iCloud.com.matt.itinero`, App
  Group, push) are in `Itinero.entitlements`; a new extension's bundle ID only registers after its parent App ID
  exists (build the app once with `-allowProvisioningUpdates` first).
- Views: `TripsView` (list, import), `TripDetailView` (day timeline, traveler filter chips),
  `Views/ItemEditorView`, `Views/TravelersView`, `Views/ImportReportView`.
- Personal itinerary: `private/japan-2026.json` (git-ignored) is bundled into local builds if present and
  offered from the empty state. `RealItineraryTests` skips itself when the file is absent.
- Never delete user data as a side effect of a fix — add a flag instead.
- Never fabricate real-world facts (hours, prices, flight numbers). Verify and cite, or leave blank.

## Roadmap

0. Foundation (repo, design system, tests) ✅
1. Core model + Japan itinerary import ✅ (import from the public italiatrois.netlify.app page)
2. Trip-day features ✅ (needs-booking tracker, item detail, bookings wallet, issues, maps, checklist, budget, cruise fields, trip notes/links, today card, done, search, your-time)
3. TestFlight #1 — archive/export with distribution signing works (icon, privacy manifest, v1.0.0 build 1); the upload itself needs Matt's App Store Connect login: see docs/TESTFLIGHT_SETUP.md, `tools/release.sh`
4. Family sharing ✅ built (CloudKit + CKSyncEngine); two-device verification pending
5. Notifications, widget, share card, export ✅
