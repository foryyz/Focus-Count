import SwiftUI
import FocusCountCore

struct TodaySummary {
    let sessions: [StudySession]
    let events: [TimeEvent]
    var seconds: Double { sessions.reduce(0) { $0 + $1.activeSeconds } }
    var activities: [FocusBreakdown] { FocusAnalysisData.breakdown(sessions) { $0.subject } }
    init(database: Database, now: Date = Date(), calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        sessions = database.sessions.filter { $0.deletedAt == nil && $0.startedAt >= start && $0.startedAt < end }
        events = (database.events ?? []).filter { $0.deletedAt == nil && $0.occurredAt >= start && $0.occurredAt < end }
            .sorted { $0.occurredAt == $1.occurredAt ? $0.id.uuidString < $1.id.uuidString : $0.occurredAt > $1.occurredAt }
    }
}

struct TodayFocusHero: View {
    @ObservedObject var store: StudyStore
    let fontSize: CGFloat

    @State private var encouragement = [
        "You don’t have to finish it all. Just begin.",
        "One thing at a time. You’ve got this.",
        "Take a breath. Give this moment your attention.",
        "A little focus can take you a long way.",
        "Press Return to start. You don’t have to be perfect."
    ].randomElement()!

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let summary = TodaySummary(database: store.database, now: context.date)
            let minutes = Int(max(0, summary.seconds)) / 60
            VStack(spacing: 18) {
                (
                    Text("Today’s ")
                        .font(.system(size: fontSize * 0.28, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                    + Text("focus   ")
                        .font(.system(size: fontSize * 0.28, weight: .semibold, design: .rounded))
                    + Text("\(minutes / 60)H")
                        .font(.system(size: fontSize * 0.62, weight: .medium, design: .rounded))
                    + Text("  \(minutes % 60)m")
                        .font(.system(size: fontSize * 0.28, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                )
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityLabel("今日已保存专注时长，\(minutes / 60) 小时 \(minutes % 60) 分钟")
                Text(encouragement)
                    .font(.system(size: fontSize > 90 ? 19 : 16))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: 760)
        }
    }
}

struct TodaySummaryView: View {
    @ObservedObject var store: StudyStore
    @StateObject private var colors = MarkerColors()
    @StateObject private var appearance = FocusAppearanceStore()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let summary = TodaySummary(database: store.database, now: context.date)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("今日概览", systemImage: "sun.max").font(.headline)
                    Spacer()
                    Text(context.date.formatted(.dateTime.month().day())).font(.caption).foregroundStyle(.secondary)
                }
                Text("专注活动").font(.subheadline.weight(.medium))
                if summary.activities.isEmpty {
                    Text("今天的第一段专注，从这里开始。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(summary.activities) { activity in
                                let color = appearance.color("activity:" + activity.name)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 12) {
                                        Text(activity.name).lineLimit(1).help(activity.name)
                                        Spacer(minLength: 8)
                                        Text(duration(activity.seconds)).monospacedDigit()
                                    }.font(.system(size: 12, weight: .medium))
                                    GeometryReader { geometry in
                                        Capsule().fill(color.opacity(0.12))
                                        Capsule().fill(color)
                                            .frame(width: geometry.size.width * CGFloat(activity.seconds / max(1, summary.activities.first?.seconds ?? 1)))
                                    }.frame(height: 6)
                                }.accessibilityElement(children: .combine)
                            }
                        }.padding(.vertical, 3)
                    }.frame(height: min(164, CGFloat(summary.activities.count) * 42))
                }
                Divider()
                Text("时间标记").font(.subheadline.weight(.medium))
                if summary.events.isEmpty {
                    Text("今天还没有标记\n输入 !文字，记下值得留意的一刻。")
                        .font(.callout).foregroundStyle(.secondary).lineSpacing(5).padding(.vertical, 6)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(summary.events) { event in
                                let name = EventAnalytics.label(event.kind)
                                HStack(spacing: 10) {
                                    if let emoji = colors.emojis[name], !emoji.isEmpty {
                                        Text(emoji).frame(width: 22)
                                    } else {
                                        Circle().fill(colors.color(name)).frame(width: 7, height: 7).frame(width: 22)
                                    }
                                    Text(event.kind).font(.callout).lineLimit(2).help(event.kind)
                                    Spacer(minLength: 8)
                                    Text(event.occurredAt.formatted(date: .omitted, time: .standard))
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }.padding(.vertical, 3)
                    }.frame(height: min(150, CGFloat(summary.events.count) * 34))
                }
                Divider()
                HStack(spacing: 10) {
                    Text("\(summary.sessions.count) 次专注")
                    Text("·").accessibilityHidden(true)
                    Text("\(summary.events.count) 次标记")
                }.font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Text("仅统计已保存记录；跨午夜专注按开始日期归属。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(20).frame(width: 350)
        }
        .onAppear {
            colors.ensure((store.database.events ?? []).map { EventAnalytics.label($0.kind) })
            appearance.ensureColors(store.database.sessions.map(\.subject))
        }
    }
}
