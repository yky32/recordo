// Recordo Live Activity — Lock Screen + Dynamic Island parking timer
// MUST use ActivityAttributes name: LiveActivitiesAppAttributes (live_activities plugin)

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RecordoLiveWidgets: WidgetBundle {
  var body: some Widget {
    if #available(iOS 16.1, *) {
      RecordoParkingLiveActivity()
    }
  }
}

// Name is required by live_activities plugin — do not rename.
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState
  public struct ContentState: Codable, Hashable {}
  var id = UUID()
}

extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String {
    "\(id)_\(key)"
  }
}

// Must match Flutter LiveActivityService.appGroupId
let sharedDefault = UserDefaults(suiteName: "group.com.recordo.live")!

@available(iOSApplicationExtension 16.1, *)
struct RecordoParkingLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      lockScreenView(context: context)
    } dynamicIsland: { context in
      let parkName = str(context, "parkName") ?? "Recordo"
      let range = timerRange(context)

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 4) {
            Text("計時中")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(Color.green)
            Text(parkName)
              .font(.headline)
              .lineLimit(2)
              .minimumScaleFactor(0.7)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 4) {
            Text("泊咗")
              .font(.caption2)
              .foregroundStyle(.secondary)
            Text(timerInterval: range, countsDown: false)
              .monospacedDigit()
              .font(.title2.weight(.bold))
              .multilineTextAlignment(.trailing)
              .frame(width: 100)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Image(systemName: "car.fill")
            Text(feeLine(context))
              .font(.footnote)
              .foregroundStyle(.secondary)
            Spacer()
            Text("Recordo")
              .font(.caption2.weight(.bold))
          }
          .padding(.top, 4)
        }
      } compactLeading: {
        Image(systemName: "car.fill")
          .foregroundStyle(Color.green)
      } compactTrailing: {
        Text(timerInterval: range, countsDown: false)
          .monospacedDigit()
          .frame(width: 52)
          .font(.caption.weight(.semibold))
      } minimal: {
        Image(systemName: "car.fill")
          .foregroundStyle(Color.green)
      }
    }
  }

  @ViewBuilder
  private func lockScreenView(context: ActivityViewContext<LiveActivitiesAppAttributes>) -> some View {
    let parkName = str(context, "parkName") ?? "停車場"
    let range = timerRange(context)

    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
          Text("計時中")
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.green)
        }
        Text(parkName)
          .font(.headline)
          .lineLimit(2)
        Text(feeLine(context))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
        Text("泊咗")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Text(timerInterval: range, countsDown: false)
          .monospacedDigit()
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .multilineTextAlignment(.trailing)
          .frame(minWidth: 110)
      }
    }
    .padding(16)
    .activityBackgroundTint(Color.black.opacity(0.85))
    .activitySystemActionForegroundColor(.white)
  }

  private func str(
    _ context: ActivityViewContext<LiveActivitiesAppAttributes>,
    _ key: String
  ) -> String? {
    sharedDefault.string(forKey: context.attributes.prefixedKey(key))
  }

  private func timerRange(
    _ context: ActivityViewContext<LiveActivitiesAppAttributes>
  ) -> ClosedRange<Date> {
    let startMs = sharedDefault.double(forKey: context.attributes.prefixedKey("startMs"))
    let start: Date
    if startMs > 0 {
      start = Date(timeIntervalSince1970: startMs / 1000.0)
    } else {
      start = Date()
    }
    // Live Activity timerInterval needs an end bound; count-up until +12h
    let end = start.addingTimeInterval(12 * 60 * 60)
    return start...end
  }

  private func feeLine(
    _ context: ActivityViewContext<LiveActivitiesAppAttributes>
  ) -> String {
    let hourly = sharedDefault.string(forKey: context.attributes.prefixedKey("hourlyLabel"))
    if let hourly, !hourly.isEmpty {
      return "約 \(hourly)/時 · 以閘口為準"
    }
    return "Recordo · 免費泊車記帳"
  }
}
