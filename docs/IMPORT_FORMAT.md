# Itinerary import format

TripTrac imports a trip from one JSON file (Trips screen → + → Import itinerary file…).

```json
{
  "trip": {"name": "…", "destination": "…", "kind": "land|cruise",
           "start": "2026-11-13", "end": "2026-11-27", "timeZone": "Asia/Tokyo"},
  "travelers": [{"name": "Ann", "team": "Team 1"}],
  "days": {"2026-11-13": "Day title"},
  "items": [{
    "date": "2026-11-15", "category": "flight|hotel|activity", "title": "…", "booked": false,
    "meta": ["…"], "notes": "Ann · Ben — [Meal] — needs booking/reservation"
  }]
}
```

`meta` and `notes` keep the page's own text layout; `SiteImporter` parses them:

- **activity** meta: `"HH:mm"`, place, time range (`"4:30–6:30pm"`, `"Morning"`, …) — a name-only entry lists attendees.
- **flight** meta: airline + number, `"MCO → MSP"`, `"Nov 14, 6:15 AM"` (departure airport's zone), `"Conf: ABC"`.
  A title/meta mentioning "Shinkansen" becomes a train.
- **hotel** meta: name, `"Fri, Nov 20 → Sat, Nov 21"`, address, `"Conf: …"`.
- **notes**: `Names · separated · by dots` or `All N`, `(optional)`, `[Tag]` (Meal, Day Trip, Disney, Rest / Free Time),
  and `needs booking/reservation`. Empty attendees means the whole group.

Anything ambiguous (backwards hotel dates, a start time that disagrees with the listed range, missing
place/destination) is imported as written and listed in the post-import report — never silently fixed.

Real exports contain confirmation numbers: keep them in `private/` (git-ignored), never in the repo.
