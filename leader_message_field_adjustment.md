# KLYCH — Leader Message Field Adjustment

UI-only change. No business logic, alerts, targeting, recipients, realtime, or
acknowledgement behaviour was modified.

## Scope

- File: `lib/screens/leader_home_screen.dart`
- Change: visible height of the alert message composer on Leader Home.

## Previous height

- The composer used a line-based `TextField` (`minLines: 2`, `maxLines: 4`).
- Visible resting height ≈ **2 text lines ≈ 64 logical px ≈ ~10.6 mm** on modern
  iPhones. It only grew while typing and felt secondary to the history list.

## New height

- The composer is now a **fixed-height composition area** of **150 logical px**.
- Implemented with a bounded `SizedBox(height: 150)` wrapping a
  `TextField(expands: true)`, so the field fills the full box immediately
  (not just while typing).

### mm conversion

Modern iPhones (13 / 14 / 15 / 15 Pro) render at ~460 physical ppi with a device
pixel ratio of 3, giving ~153 logical ppi → **~6.04 logical px per mm**.

```
150 logical px ÷ 6.04 px/mm ≈ 24.8 mm  (target: ≈ 24 mm)
```

## Implementation notes

- Composer changed from a flexible region to a **deterministic fixed height**
  (`150 px`) so the visible field is the same physical size on every target
  device rather than depending on leftover layout space.
- `expands: true` (with `maxLines: null`, `minLines: null`,
  `textAlignVertical: TextAlignVertical.top`) makes the text fill the box from
  the top for a comfortable, document-style typing experience.
- Styling unchanged: same `KlychTheme` filled input decoration, same hint
  `Текст оповіщення...`, same font.
- The **alert history section** below was switched from a fixed flex share to a
  plain `Expanded`, so it now simply fills whatever space remains under the
  composer — the composer is the primary focus and history is secondary.
- No dead/black space at the bottom: the history `Expanded` absorbs all
  remaining height.
- Keyboard safety: with the composer fixed and history flexible, opening the
  keyboard shrinks only the history list, so there is **no RenderFlex overflow**
  and the send button stays visible.

## Device verification (layout math)

All three devices share the same logical density class (~6.04 px/mm), so the
fixed 150 px composer measures the same on each:

| Device         | Logical size | Composer height | Physical height |
|----------------|--------------|-----------------|-----------------|
| iPhone 13      | 390 × 844    | 150 px          | ≈ 24.8 mm       |
| iPhone 14      | 390 × 844    | 150 px          | ≈ 24.8 mm       |
| iPhone 15 Pro  | 393 × 852    | 150 px          | ≈ 24.8 mm       |

Fixed UI above the history (header + composer + level/recipients + send +
labels) totals ≈ 398 px. With the keyboard open (~336 px) the remaining space
stays positive on all three devices, so the composer and send button remain
fully visible and there are no overflow warnings.

## Verification

- `flutter analyze` → no new issues (only the 8 pre-existing `info` hints
  unrelated to this change).
