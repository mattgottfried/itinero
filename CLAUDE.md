# TripTrac

Native iOS app (SwiftUI + SwiftData, iOS 17+) for planning and tracking trips and their itineraries —
both cruises and land trips. First real use: a 7-person family trip to Japan, Nov 13–27 2026.

Read `DESIGN.md` (visual language) and `PREFERENCES.md` (how I like to work) before making changes.
Both are living documents: extend, don't replace.

## Project conventions (the `[ ]` fills from PREFERENCES.md)

- **Build system:** `project.yml` (XcodeGen) is the source of truth. `TripTrac.xcodeproj` is generated and
  git-ignored — run `xcodegen generate` after adding/removing files. No manual pbxproj registration.
- **Build / test:**
  `xcodebuild test -project TripTrac.xcodeproj -scheme TripTrac -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`
  Claude *can* build and run in the simulator in this project — verify there, not only by reading the diff.
- **Git:** feature branch `feature/<topic>` → PR → merge into `main`. Merge finished batches without being
  asked. New commits, never amend; never force-push shared history. Commit/PR text explains *why*, and
  contains no AI model name or attribution lines.
- **CI:** none yet. Once TestFlight builds exist, keep a cumulative "What's new / what to test" note in
  `docs/TESTFLIGHT_NOTES.md` since the last uploaded build.
- **Bundle ID:** `com.matt.triptrac`. Signing team is set at archive time (Phase 3).
- **Personal data:** real itinerary data (confirmation numbers, addresses) lives in `private/` (git-ignored)
  or in the app's own store — never in committed source, fixtures, or tests. Tests use fake data.

## Architecture

- `TripTrac/DesignSystem/` — components from DESIGN.md. `StatusTone` + `statusTone(for:daysUntil:)` is the
  *only* place status→color is decided. Add new components here, with accessibility built in.
- `TripTrac/TripLogic.swift` and other pure enums/functions — business logic, no SwiftUI/SwiftData imports,
  unit-tested in `TripTracTests/` in the same batch of work.
- Views: `TripsView` (list), `TripDetailView` (day timeline), `TripEditorView`.
- Models (`Trip.swift`, SwiftData): Trip → ItineraryItem today; growing to Trip → Day → Item + Traveler
  (per-item attendance) in Phase 1. Never delete user data as a side effect of a fix — add a flag instead.
- Never fabricate real-world facts (hours, prices, flight numbers). Verify and cite, or leave blank.

## Roadmap

0. Foundation (repo, design system, tests) ✅
1. Core model + Japan itinerary import (from italiatrois.netlify.app public page)
2. Trip-day features: who's-where filter, needs-booking tracker, maps, checklist, budget, cruise support
3. TestFlight #1 (check Xcode beta vs. release before upload)
4. Family sharing (approach TBD: CloudKit sharing / hosted backend / read-only)
5. Notifications, widget, share card, export
