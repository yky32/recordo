# Recordo · iOS Live Activity / Dynamic Island

泊車計時中：app 退到背景 / 鎖屏仍可睇 **Live Activity**；iPhone 14 Pro+ 會出 **Dynamic Island**。

Timer 用系統 `Text(timerInterval:countsDown:false)` **原生數秒**，唔使 Flutter 背景每秒 update。

## 狀態

| | |
|--|--|
| Flutter | `live_activities` · `LiveActivityService` · session start/end |
| Swift UI | `ios/RecordoLiveActivity/RecordoLiveActivity.swift` |
| Xcode target | **RecordoLiveActivity** 已 embed 入 Runner |
| App Group | `group.com.recordo.live`（Runner + Extension entitlements） |
| iOS | **16.1+** |
| Simulator build | ✅ 可 compile（**Live Activity 只喺真機顯示**） |

## 你仲要做（Signing）

1. 開 `ios/Runner.xcworkspace`
2. **Runner** target → Signing & Capabilities  
   - Team 選你自己  
   - 確認 **App Groups** 有 `group.com.recordo.live`
3. **RecordoLiveActivity** target → 同樣 Team + App Groups 勾同一 group  
4. **真機** run（Simulator 唔會出 Island / Live Activity banner）

如果 App Groups 喺 Xcode UI 未出現 capability chip：  
+ Capability → App Groups → 加 `group.com.recordo.live`（兩個 target）。

## 驗證

1. 揀場 → 右滑開始計時  
2. Home / 上掃退 app  
3. 鎖屏或 Dynamic Island → **計時中 + 場名 + 時間在走**  
4. 結束 session → Live Activity 消失  

## 故障

| 現象 | 檢查 |
|------|------|
| 完全冇 banner | 真機？iOS≥16.1？App Group 兩邊一致？ |
| `areActivitiesEnabled` false | 設定 → 面容ID與密碼 / Live Activities |
| 只有鎖屏冇 Island | 需要 14 Pro 或之後 |
| Signing error | Extension bundle id `com.recordo.RecordoLiveActivity` 要同 Team |

## 開發

- `createActivity(session.id, { parkName, startMs, hourlyLabel })`
- Attributes 名必須 `LiveActivitiesAppAttributes`（plugin 約定）
- Embed phase 必須喺 **Thin Binary 之前**（避免 Runner build cycle）
