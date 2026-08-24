# CTO Ticket — recordo map mid-band still offset (走位)

**ID:** RECORDO-MAP-003  
**Status:** Open · regression after mid-band fix (TF ~1.0.0+23)  
**Desk:** 🇻🇳 **CTO · VN**  
**Product:** recordo (HK parking)  
**Repo:** `~/Documents/git/personal/recordo` · `yky32/recordo`  
**Severity:** High UX (core home map)  
**Created:** 2026-08-24  
**From:** CEO video `video_ae3f562f5f13.mp4` —「仍然是走位了」

---

## Context
Prior fixes:
- #18 sheet drag no camera jump
- #19 center on true mid of visible band (search↔sheet)
- build bumps to TF

CEO still reports **走位** on device (TestFlight).

## Evidence (video frames)
- App: TestFlight · home map · Wan Chai · bottom sheet「附近停車場」
- Blue user dot ~**31%** from top of screen (frame measure)
- Sheet content visually ~**55–62%** from top
- Approximate mid-band (search bottom ↔ sheet top) ~**35%+**
- **Blue sits ~5–8% of screen height too high** vs optical mid of visible map band
- While panning, pin cluster + chrome overlap feels “off” (secondary)

Video path:
`/Users/wayneyu/.hermes/cache/videos/video_ae3f562f5f13.mp4`

## Code suspect
`lib/features/home/park_map.dart` → `_centerOn`:

```dart
final topChrome = mq.padding.top + 72; // magic
final sheet = widget.sheetExtent.clamp(0.15, 0.9);
final sheetTop = h * (1.0 - sheet);
final band = (sheetTop - topChrome).clamp(80.0, h);
final targetY = topChrome + band * 0.5;
final offset = Offset(0, h / 2 - targetY);
_map.move(ll, z, offset: offset);
```

`home_map_screen.dart` passes `_sheetExtent` (init 0.42) from `DraggableScrollableNotification`.

### Why still wrong
1. **Magic `+ 72`** ≠ real search bar bottom (SafeArea + 8 + field height).
2. **`sheetExtent * screenH`** may not equal true sheet top (safe area, list chrome, extent vs pixels).
3. First `locate(forceCamera: true)` in `addPostFrameCallback` may run **before** sheet layout settles → wrong extent.
4. flutter_map `offset` is correct API-wise (`Offset(+y)` places latlng above geometric center) — formula inputs are the weak link.

## Fix direction
- [ ] Measure real **searchBottomY** and **sheetTopY** with `GlobalKey` / `context.findRenderObject()` (or LayoutBuilder callbacks from parent)
- [ ] Pass pixel insets into `ParkMap` instead of only `sheetExtent` fraction
- [ ] Re-run `_centerOn` after first sheet layout (listen extent once extent stable)
- [ ] Locate button + select park + initial GPS all use same measured mid-band
- [ ] Device QA: blue / selected pin on CEO mid-line mark with sheet at min / init / max

## Done when
- Locate: blue sits on mid-line of **visible** map (search bottom ↔ sheet top) at init sheet
- Select park: park pin on same mid-line
- Drag sheet: no jump (keep #18); optional: don’t re-center on drag
- CEO video retest OK on TF
