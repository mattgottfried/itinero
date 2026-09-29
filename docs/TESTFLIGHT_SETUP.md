# Getting TripTrac onto TestFlight

State: the app archives and exports with **App Store distribution signing** (team X796Z5UW4P, iCloud/CloudKit,
App Group, push, widget). `build/TripTrac-1.0.0-build1.ipa` is ready to upload. What's left needs your Apple login.

## One-time: create the app record
1. https://appstoreconnect.apple.com → Apps → **+** → New App.
2. Platform iOS · Name **TripTrac** (or similar if taken) · Primary language English · Bundle ID
   **com.matt.triptrac** (it's already registered) · SKU `triptrac`.

## Upload a build (pick one)
- **Transporter** (Mac App Store): drag `build/TripTrac-1.0.0-build1.ipa` in → Deliver.
- **Xcode**: open `TripTrac.xcodeproj` → Product → Archive → Distribute App → App Store Connect → Upload.
- **Command line** (needs an App Store Connect API key from Users and Access → Integrations → Keys):
  `ASC_KEY_PATH=… ASC_KEY_ID=… ASC_ISSUER_ID=… tools/release.sh --upload`
- Each new upload needs a higher `CURRENT_PROJECT_VERSION` in `project.yml` (currently 1).

## After it processes (~10–30 min)
1. App Store Connect → TripTrac → TestFlight → the build appears; answer the export-compliance prompt if shown
   (the app sets "no non-exempt encryption", so it normally isn't).
2. **Internal testing** (fastest, no review): Users and Access → invite each family member as a user (App Manager or
   Developer role isn't needed — "Marketing"/limited is fine), then TestFlight → Internal Testing → add them. They
   install via the TestFlight app on their iPhones.
3. External testers need a one-time Beta App Review (~1 day) — use internal if the group is on your team.
4. Paste `docs/TESTFLIGHT_NOTES.md` into "What to Test".

## Before Nov 13
- Two-phone check of family sharing: `docs/FAMILY_SHARING_TEST.md`.
- Turn on Settings → reminders and set "I'm traveling as" on each phone.
- Keep a JSON backup of the Japan trip (trip menu → Share or back up) somewhere outside the app.
