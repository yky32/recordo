# Recordo TestFlight

Same team as ClipVal/Replicaz: `3G34999H3A` · ITC `128328295`.

Bundle: **com.recordo**  
Secrets: mirror from `yky32/replicaz-app` or `clipvault-app`.

ASC: if API cannot CREATE apps, create **Recordo** once in App Store Connect with bundle `com.recordo`.

## First ASC app (required once)

API key **cannot CREATE apps**. IPA already builds on CI.

1. [App Store Connect](https://appstoreconnect.apple.com) → My Apps → **+** → New App  
2. Platforms: **iOS**  
3. Name: **Recordo**  
4. Primary language: English (US) or Chinese (Hong Kong)  
5. Bundle ID: **com.recordo** (must exist on Developer Portal — CI already created App ID + profile)  
6. SKU: `recordo`  
7. User Access: Full  

Then: Actions → **Deploy** → Run workflow.
