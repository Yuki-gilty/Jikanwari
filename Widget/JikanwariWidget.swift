import ActivityKit
import SwiftUI
import WidgetKit

@main
struct JikanwariWidgets: WidgetBundle {
    var body: some Widget {
        BreakLiveActivity()
        NextClassWidget()
        AfterThisWidget()
        TodayWidget()
        WeekWidget()
        UpcomingWidget()
    }
}

struct BreakLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BreakAttributes.self) { ctx in
            LockView(s: ctx.state, stale: ctx.isStale)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                // 背景はiOS標準のガラス（Liquid Glass）に任せる
                .activityBackgroundTint(nil)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                // カメラの横は狭いので、左右は大きな時限とカウントダウンだけ。入りきらなければカメラの下へ下ろす
                DynamicIslandExpandedRegion(.leading) {
                    PeriodBadge(periods: s.periods, size: 46)
                        .padding(.leading, 6)
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Countdown(s: s)
                            .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        Text(ctx.isStale ? "授業中" : "開始まで")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 6)
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(s.name)
                                .font(.title3.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 8)
                            if !s.room.isEmpty {
                                Label(s.room, systemImage: "mappin.and.ellipse")
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                        }
                        BreakBar(s: s)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Text("\(s.periods)限")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .padding(.leading, 2)
            } compactTrailing: {
                Countdown(s: s)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .frame(width: 46)
            } minimal: {
                Text(s.periods)
                    .font(.system(.body, design: .rounded).weight(.bold))
            }
            .keylineTint(.primary)
        }
    }
}

/// 時限の数字。いちばん大きく、いちばん先に目に入るように
struct PeriodBadge: View {
    let periods: String  // "6" や "6・7"
    let size: CGFloat

    var body: some View {
        VStack(spacing: -2) {
            Text(periods)
                .font(.system(size: size * (periods.count > 1 ? 0.4 : 0.62), weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
            Text("限")
                .font(.system(size: size * 0.22, weight: .bold))
        }
        .frame(width: size * (periods.count > 1 ? 1.25 : 1), height: size * 1.12)
        .glassEffect(.regular, in: .rect(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct Countdown: View {
    let s: BreakAttributes.ContentState
    var body: some View {
        Text(timerInterval: min(s.from, s.start)...s.start, countsDown: true, showsHours: false)
            .multilineTextAlignment(.trailing)
    }
}

/// 休み時間がどれだけ過ぎたか（自動で進む）
struct BreakBar: View {
    let s: BreakAttributes.ContentState
    var body: some View {
        ProgressView(timerInterval: min(s.from, s.start)...s.start, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(.primary)
        .labelsHidden()
    }
}

struct LockView: View {
    let s: BreakAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                PeriodBadge(periods: s.periods, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(stale ? "授業中" : "次の授業")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(s.name)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !s.room.isEmpty {
                        Label(s.room, systemImage: "mappin.and.ellipse")
                            .font(.headline)
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if !stale {
                    VStack(alignment: .trailing, spacing: 0) {
                        Countdown(s: s)
                            .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                        Text("開始まで")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 84, alignment: .trailing)
                }
            }
            if !stale { BreakBar(s: s) }
        }
    }
}
