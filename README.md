# Recordo

**Free HK parking app.** Find car parks, community prices, slide-to-log fees.

- **No paywall. No IAP. No subscriptions.**
- Prices: operator-verified where we have official tariffs; otherwise driver UGC — **not** an official rate API.
- Vacancy: Transport Department participating parks only.
- On-street meters: TD open data. Payment is in HKeMeter, not Recordo.

## Run

```bash
cd ~/Documents/git/personal/recordo
flutter pub get
flutter run
```

## Bundle

`com.recordo` (App + Live Activity `com.recordo.RecordoLiveActivity`)

App Store review notes: `docs/ASC_REVIEW_NOTES.md`
