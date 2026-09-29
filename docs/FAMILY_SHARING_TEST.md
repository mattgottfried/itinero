# Verifying family sharing (needs two real iPhones on two Apple IDs)

The record mapping, diffing and conflict rules are unit-tested; the CloudKit round trip is not, because it needs
two iCloud accounts. Do this once before relying on it for the Japan trip.

1. Both phones: same TestFlight build, signed in to iCloud, iCloud Drive on.
2. Phone A (owner): open a **test copy** of a trip (not Japan yet) → ⋯ → Family sharing → Turn on & invite family →
   send the link to Phone B (Messages/AirDrop).
3. Phone B: tap the link → TripTrac opens and the trip appears in Trips ("Shared with you"). Within ~a minute all
   days, items, travelers and the checklist should match Phone A.
4. Edit an item on B (mark done, change a time) → appears on A. Edit a different item on A → appears on B.
5. Edit the same item on both while one is in airplane mode; reconnect. The most recent edit wins on both.
6. Delete an item on A → gone on B. Delete a trip on B → A's copy is untouched.
7. On A choose Stop syncing → both keep their local copy; edits no longer travel.

If something looks wrong, ⋯ → Family sharing → Sync now, and note what you did; local data is never deleted by sync.
Rollback: Family sharing → Stop syncing this trip; Share or back up → JSON backup restores a trip on any device.
