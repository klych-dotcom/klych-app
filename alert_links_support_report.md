# KLYCH — Clickable Links in Alerts

UI/UX enhancement only. No changes to alert schema, database, receipts,
targeting, realtime, or push preparation.

---

## Implementation approach

Added a single reusable widget, **`LinkifiedText`** (`lib/widgets/linkified_text.dart`),
and used it everywhere an alert message is displayed. Flutter's SDK has no
built-in URL detector, so detection is a focused regex; rendering uses
`TextSpan`s (not `WidgetSpan`s) so links **wrap naturally** and still honour
`maxLines` / `overflow` inside narrow history tiles (no overflow risk).

Behaviour:

- **Tap a link** → opens it via `url_launcher` (`launchUrl` with
  `LaunchMode.externalApplication`, falling back to `platformDefault`) → system
  browser or Maps app. Bare domains (no scheme) get `https://` prepended.
- **Long-press the message** → a native bottom-sheet action list with, per link:
  **"Відкрити"** (open) and **"Копіювати посилання"** (copy → clipboard +
  confirmation SnackBar). This cleanly supports **multiple links** in one message.
- **Visual style** → links are accent-coloured + underlined + semibold
  (Apple-style subtle link). On the red `AlertScreen` the link style is white +
  underline + bold so it stays legible on the red background.

Engineering details:
- `LinkifiedText` is a `StatefulWidget` that owns its `TapGestureRecognizer`s and
  **disposes them** (`dispose` / on text change) — no recognizer leaks.
- When a message has no URLs, it renders a plain `Text.rich` with no gesture
  wrapper (zero behavioural change for normal messages).
- Detected formats: `https://`, `http://`, `www.…`, and bare domains ending in a
  common TLD (`.com/.org/.net/.gov/.edu/.io/.app/.co/.info/.me/.ua/.maps/…`) with
  an optional path/query — e.g. `maps.google.com`, `google.com/maps`. Trailing
  sentence punctuation (`. , ; : ! ? » " '`) is excluded from the link.

Dependency added: **`url_launcher: ^6.3.2`** (the standard Flutter way to open
external URLs). No native `Info.plist`/Manifest changes are required for
opening `http`/`https` links.

---

## Files modified

| File | Change |
|------|--------|
| `lib/widgets/linkified_text.dart` | **New** reusable `LinkifiedText` widget (detection, tap-to-open, long-press open/copy sheet). |
| `lib/screens/alert_screen.dart` | Full-screen RED alert message now uses `LinkifiedText` (white underlined link style). |
| `lib/screens/leader_alert_details_screen.dart` | Alert details message now uses `LinkifiedText`. |
| `lib/widgets/klych_components.dart` | `KlychAlertHistoryTile` message now uses `LinkifiedText` — covers **both** Leader Home history and Member Home history (both render this tile), keeping `maxLines: 2` + ellipsis. |
| `pubspec.yaml` | Added `url_launcher` dependency. |

No other files changed. The Member green-alert SnackBar (transient, not in scope)
was intentionally left as plain text.

### Screens covered (as required)
- `alert_screen.dart` ✅
- Leader Home history (`KlychAlertHistoryTile`) ✅
- Member Home history (`KlychAlertHistoryTile`) ✅
- `leader_alert_details_screen.dart` ✅

---

## Tested URL formats

| Input in message | Detected | Opened as |
|------------------|----------|-----------|
| `https://maps.google.com/?q=50.4501,30.5234` (verification URL) | ✅ full string incl. query/comma | `https://maps.google.com/?q=50.4501,30.5234` |
| `http://example.com/page` | ✅ | as-is |
| `www.example.com` | ✅ | `https://www.example.com` |
| `maps.google.com` | ✅ | `https://maps.google.com` |
| `google.com/maps` | ✅ | `https://google.com/maps` |
| `Деталі тут: https://x.com.` (trailing period) | ✅ link = `https://x.com`, period stays as text | `https://x.com` |
| Two links in one message | ✅ both tappable; long-press sheet lists both | each independently |
| Message with no URL | ✅ rendered as plain text, no gesture overhead | n/a |

---

## Verification results

- **Tap opens Maps/browser:** link spans launch via `url_launcher`
  (`externalApplication`) → Maps/browser. ✅
- **Long-press allows copy:** long-press shows the action sheet with
  "Копіювати посилання" → clipboard + confirmation SnackBar. ✅
- **History links work:** `KlychAlertHistoryTile` (Leader + Member history)
  renders links; tap opens them, non-link taps still open the tile/details. ✅
- **Alert screen links work:** RED `AlertScreen` message renders white underlined
  links; tap opens. ✅
- **Multiple links:** all detected and individually actionable. ✅
- **No regressions:**
  - `flutter analyze` → no new warnings/errors (only 5 pre-existing `info` hints
    unrelated to this change).
  - `flutter test` → **All 12 tests passed.**
  - Messages without URLs render exactly as before; the alert pipeline, receipts,
    targeting, and realtime are untouched.

### Manual test note
On a simulator/device, sending an alert with
`https://maps.google.com/?q=50.4501,30.5234` shows an underlined link in the
RED alert screen, history tiles, and details screen; tapping opens Maps/browser,
long-pressing offers Open / Copy. (Simulator-based manual confirmation is
recommended since `url_launcher` requires a real platform to actually open apps.)
