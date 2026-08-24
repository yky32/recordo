# Recordo · iOS Live Activity / Dynamic Island

泊車計時中：app 退到背景 / 鎖屏仍可睇 **Live Activity**；iPhone 14 Pro+ 會出 **Dynamic Island**。

Timer 用系統 `Text(timerInterval:countsDown:false)` **原生數秒**，唔使 Flutter 背景每秒 update。

## 已做好（code）

| | |
|--|--|
| Flutter | `live_activities` · `LiveActivityService` · session start/end 自動起/停 |
| Swift UI | `ios/RecordoLiveActivity/RecordoLiveActivity.swift` |
| App Group | `group.com.recordo.live` |
| Runner | `NSSupportsLiveActivities` · `Runner.entitlements` |
| iOS floor | **16.1+** |

## 你要喺 Xcode 做一次（必要）

Widget Extension **必須** embed 入 app，否則 Live Activity 唔會顯示。

1. 開 `ios/Runner.xcworkspace`
2. **File → New → Target… → Widget Extension**
   - Product Name: `RecordoLiveActivity`
   - Embed in Application: **Runner**
   - **唔使** Include Configuration App Intent（可 untick）
3. 用我哋嘅檔取代 Xcode 自動產生嘅 Swift：
   - 刪 extension 入面預設 `.swift`
   - 將 repo 內 `ios/RecordoLiveActivity/RecordoLiveActivity.swift` 加落 extension target
   - Info.plist 要有 `NSSupportsLiveActivities = YES`（repo 已有樣板）
4. **Signing & Capabilities**（**Runner** + **RecordoLiveActivity** 兩個 target）：
   - **+ App Groups** → `group.com.recordo.live`（兩個都要勾同一 group）
5. Extension target:
   - Deployment **iOS 16.1**
   - Bundle id 建議：`com.recordo.RecordoLiveActivity`
6. Runner target 確認有 App Group capability + entitlements 指向 `Runner/Runner.entitlements`
7. 選 **真機**（Simulator **唔支援** Live Activities）
8. Run

### 驗證

1. 揀場 → 右滑開始計時  
2. Home 鍵 / 上掃退 app  
3. 鎖屏 / Dynamic Island 應見 **計時中 + 場名 + 時間在走**  
4. 結束 session → Live Activity 消失  

## 故障排查

| 現象 | 檢查 |
|------|------|
| 完全冇 banner | Extension 未 embed / Attributes 名唔係 `LiveActivitiesAppAttributes` |
| 有 activity 但空白 | App Group id 兩邊唔一致 / 未勾 group |
| `areActivitiesEnabled` false | 系統設定 → 面容ID與密碼 / 專注模式；或 iOS < 16.1 |
| 只有鎖屏冇 Island | 需要 iPhone 14 Pro 或之後 |

## 開發備註

- `createActivity(session.id, { parkName, startMs, hourlyLabel })`
- `iOSEnableRemoteUpdates: false`（唔使 Push 更新）
- 唔好 rename `LiveActivitiesAppAttributes`
