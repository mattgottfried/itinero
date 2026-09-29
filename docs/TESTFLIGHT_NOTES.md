# What's new / what to test (since last TestFlight build)

No build uploaded yet. Cumulative so far:

- Phase 1: Trip → Day → Item model; import a trip from JSON; per-traveler "who's where" filter;
  add/edit/delete items with undo; booked / needs-booking status; travelers list.
- Test on device: load the Japan 2026 itinerary from the empty state, tap each traveler chip, edit an item,
  delete + undo, check the "things to check" import report against the real bookings.
- Phase 2: hub tiles on each trip (To book, Bookings, Checklist, Budget, Day map, Issues); item detail with
  Open in Maps / transit directions / copy address / copy confirmation; swipe right = Done; search bar;
  "your time" line for items in another time zone; cost + links on items; checklist; cruise ship/cabin + all-aboard.
- Test on device: open Day map on a day with places (pins need network — check they look right, vague places
  like "restaurant near Airbnb" will be approximate); tap Issues and compare with your real plan; add a cost
  in yen to two items and check Budget split; on trip days the Today card should show Now/Next.
- Phase 5: Settings (Trips → + → Settings): "I'm traveling as" + reminders (allow notifications when asked);
  widget "Next up" (long-press home screen → add widget); trip menu → Share or back up (image card, text, .ics,
  JSON backup — restore via Trips → + → Import file).
- Test on device: turn reminders on, add an item 2 hours from now and see the notification; add the widget and
  confirm it matches the next item; export .ics and open in Calendar; back up then delete + restore a test trip.
- Phase 4: trip menu → Family sharing… (owner: Turn on & invite family; invitee: open the link). NEW and not yet
  verified across two accounts — follow docs/FAMILY_SHARING_TEST.md with a test trip before using it for Japan.
