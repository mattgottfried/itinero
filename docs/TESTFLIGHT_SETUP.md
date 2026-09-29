# Getting Itinero onto TestFlight

State: the app archived and exported with **App Store distribution signing** (team X796Z5UW4P, iCloud/CloudKit,
App Group, push, widget) under its previous name. After the rename to Itinero the new App IDs still have to be
registered: open Xcode → Settings → Accounts and make sure your Apple ID is signed in (re-enter the password if
asked), then run `tools/release.sh` — it registers `com.matt.itinero`, the iCloud container and the App Group, and
writes `build/release/export/Itinero.ipa`. Uploading needs your Apple login too.

## One-time: create the app record
1. https://appstoreconnect.apple.com → Apps → **+** → New App.
2. Platform iOS · Name **Itinero** (or similar if taken) · Primary language English · Bundle ID
   **com.matt.itinero** (registered automatically by the first signed build — if it isn't in the list, run `tools/release.sh` first) · SKU `itinero`.

## Upload a build (pick one)
- **Transporter** (Mac App Store): drag `build/release/export/Itinero.ipa` in → Deliver.
- **Xcode**: open `Itinero.xcodeproj` → Product → Archive → Distribute App → App Store Connect → Upload.
- **Command line** (needs an App Store Connect API key from Users and Access → Integrations → Keys):
  `ASC_KEY_PATH=… ASC_KEY_ID=… ASC_ISSUER_ID=… tools/release.sh --upload`
- Each new upload needs a higher `CURRENT_PROJECT_VERSION` in `project.yml` (currently 1).

## After it processes (~10–30 min)
1. App Store Connect → Itinero → TestFlight → the build appears; answer the export-compliance prompt if shown
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
