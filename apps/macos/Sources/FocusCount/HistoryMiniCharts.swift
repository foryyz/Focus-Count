import SwiftUI
import FocusCountCore

struct DailyBars: View {
    let records: [StudySession]
    let select: (Date) -> Void
    private var totals: [Date: Double] {
        Dictionary(grouping: records, by: { Calendar.current.startOfDay(for: $0.startedAt) })
            .mapValues { $0.reduce(0) { $0 + $1.activeSeconds } }
    }
    var body: some View {
        let values = totals
        let peak = max(values.values.max() ?? 0, 1)
        ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(values.keys.sorted(), id: \.self) { day in
                    let seconds = values[day] ?? 0
                    Button { select(day) } label: {
                        VStack(spacing: 5) {
                            Text(String(format: "%.1fh", seconds / 3600)).font(.system(size: 10)).foregroundStyle(.secondary)
                            RoundedRectangle(cornerRadius: 4).fill(Color.teal.opacity(0.75))
                                .frame(width: 28, height: max(2, 75 * seconds / peak))
                            Text(day.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(width: 43, height: 110, alignment: .bottom)
                    }.buttonStyle(.plain)
                        .help("\(day.formatted(date: .complete, time: .omitted)) · \(duration(seconds))")
                        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted))，\(duration(seconds))，筛选当天")
                }
            }
        }.frame(height: 126)
    }
}

struct SubjectBars: View {
    let records: [StudySession]
    let select: (String) -> Void
    var body: some View {
        let totals = Dictionary(grouping: records, by: \.subject).mapValues { $0.reduce(0) { $0 + $1.activeSeconds } }
        let peak = max(totals.values.max() ?? 0, 1)
        ScrollView {
            VStack(spacing: 8) {
                ForEach(totals.keys.sorted { totals[$0]! == totals[$1]! ? $0 < $1 : totals[$0]! > totals[$1]! }, id: \.self) { subject in
                    Button { select(subject) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(subject).lineLimit(1)
                                Spacer()
                                Text(duration(totals[subject] ?? 0)).monospacedDigit()
                            }.font(.caption)
                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 3).fill(Color.teal.opacity(0.65))
                                    .frame(width: max(2, geometry.size.width * (totals[subject] ?? 0) / peak))
                            }.frame(height: 7)
                        }
                    }.buttonStyle(.plain).help("筛选活动：\(subject)")
                }
            }
        }.frame(height: 126)
    }
}

struct HistoryMiniCharts: View {
    let records: [StudySession]
    let activities: [String]
    let selectDay: (Date) -> Void
    let selectActivity: (String) -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("每日时长").font(.subheadline.bold())
                Text("有记录的开始日期 · 点击筛选").font(.caption2).foregroundStyle(.secondary)
                DailyBars(records: records, select: selectDay)
            }.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text("活动分布").font(.subheadline.bold())
                Text("有效专注时长 · 点击活动筛选").font(.caption2).foregroundStyle(.secondary)
                SubjectBars(records: records, select: selectActivity)
            }.frame(maxWidth: .infinity)
        }.padding(14).background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}
