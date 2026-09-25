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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let summary = TodaySummary(database: store.database, now: context.date)
            VStack(spacing: 10) {
                Text("今日专注").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                Text(duration(summary.seconds))
                    .font(.system(size: fontSize, weight: .light, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityLabel("今日已保存专注时长，\(duration(summary.seconds))")
                HStack(spacing: 12) {
                    Text("\(summary.sessions.count) 次专注")
                    Circle().frame(width: 3, height: 3).accessibilityHidden(true)
                    Text("\(summary.events.count) 次标记")
                }.font(.system(size: 13)).foregroundStyle(.secondary)
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
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("专注时长").font(.caption).foregroundStyle(.secondary)
                        Text(duration(summary.seconds)).font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                    Spacer()
                    Text("\(summary.sessions.count) 次专注").font(.caption).foregroundStyle(.secondary)
                }
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
                HStack {
                    Text("时间标记").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(summary.events.count) 次").font(.caption).foregroundStyle(.secondary)
                }
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
