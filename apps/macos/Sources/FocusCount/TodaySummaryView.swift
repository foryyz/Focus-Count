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

#if os(macOS)
struct TodayFocusHero: View {
    @ObservedObject var store: StudyStore
    let fontSize: CGFloat
    @DirectoryPreference(FocusMilestone.themeKey) private var rewardsTheme = false

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
            if rewardsTheme {
                MilestoneHero(seconds: summary.seconds, fontSize: fontSize * 0.62, horizontal: true)
            } else {
                VStack(spacing: 12) {
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
                        .font(.system(size: fontSize > 165 ? 14 : 13))
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: 760)
            }
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

#endif

/// Shared theme controls and rewards rendering for both native clients.
struct ThemeSettingsContent: View {
    #if os(macOS)
    @DirectoryPreference(FocusMilestone.themeKey) private var rewards = false
    #else
    @AppStorage(FocusMilestone.themeKey) private var rewards = false
    #endif
    @State private var preview = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("主题", selection: $rewards) {
                Text("经典").tag(false)
                Text("珠光流彩").tag(true)
            }.pickerStyle(.segmented)
            Text(rewards ? "珠光流彩 · 每一小时，都更丰盛" : "经典 · 清爽、平静的专注主页")
                .font(.headline)
            Text("珍珠白主页与丝绸文字随每小时升级：1 小时银灰，2–5 小时蓝、紫与玫瑰红，6–8 小时玫红与珊瑚粉；5 小时输入框点亮灯带，8 小时 RGB 流动灯带，9 小时深粉紫玫瑰红时间与成就倒计时，9–10 小时精细椭圆光轨，10 小时持续庆祝。开始专注始终使用 RGB 粉色渐变。")
                .font(.caption).foregroundStyle(.secondary)
            Button { preview = true } label: { Label("效果预览", systemImage: "sparkles.rectangle.stack") }
            Text("选择在本机保存，立即生效。10 小时主页持续庆祝，动画遵循系统“减少动态效果”设置。预览不改变记录或主题选择。")
                .font(.caption).foregroundStyle(.secondary)
        }.sheet(isPresented: $preview) { ThemeEffectPreview() }
    }
}

struct ThemeEffectPreview: View {
    @Environment(\.dismiss) private var dismiss
    @State var hours = 0.0
    private var simulatedSeconds: Double { hours * 3600 + 42 * 60 }
    private var selectedStageHour: Int { Int(hours) }
    private var horizontal: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("效果预览").font(.headline)
                Spacer()
                Button("完成") { dismiss() }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0...10, id: \.self) { value in
                            Button { hours = Double(value) } label: {
                                Text("\(value)H").font(.callout.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(selectedStageHour == value ? Color.teal.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
                            }.buttonStyle(.plain).accessibilityLabel("预览 \(value) 小时").id(value)
                        }
                    }
                }
                .task(id: selectedStageHour) {
                    await Task.yield()
                    proxy.scrollTo(selectedStageHour, anchor: .center)
                }
            }
            HStack {
                Slider(value: $hours, in: 0...10, step: 1).accessibilityLabel("模拟专注小时")
                Text("\(Int(hours))H 42m").monospacedDigit().font(.caption).frame(width: 76)
            }
            ScrollView {
                VStack(spacing: 30) {
                    Spacer(minLength: 32)
                    MilestoneHero(seconds: simulatedSeconds, fontSize: horizontal ? 82 : 64,
                                  horizontal: horizontal)
                    TextField("这次想专注于什么？（可选）", text: .constant(""))
                        .textFieldStyle(.plain).padding(14).frame(maxWidth: 360)
                        .modifier(PearlInputSurface(seconds: simulatedSeconds, enabled: true, isInput: true))
                    Button {} label: { Label("开始专注", systemImage: "play.fill").font(.headline) }
                        .buttonStyle(PrismaticStartStyle())
                        .accessibilityHint("预览按钮，不会开始真实计时")
                    HStack(spacing: 16) {
                        Image(systemName: "square.grid.2x2")
                        Image(systemName: "gearshape")
                        Image(systemName: "arrow.up.arrow.down")
                    }.foregroundStyle(.secondary).padding(12)
                        .accessibilityHidden(true)
                    Spacer(minLength: 32)
                }.padding(.horizontal, 12).frame(maxWidth: .infinity)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(MilestoneHomeEffect(seconds: simulatedSeconds, enabled: true,
                                              backdrop: Color.secondary.opacity(0.035)))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            Text("仅模拟视觉效果，不写入专注记录。动画遵循系统“减少动态效果”设置。")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(20)
        #if os(macOS)
        .frame(width: 760, height: 460)
        #endif
    }
}

struct MilestoneHero: View {
    let seconds: Double
    let fontSize: CGFloat
    var horizontal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    private var stage: FocusMilestone { FocusMilestone(seconds: seconds) }
    private var minutes: Int { Int(max(0, seconds.isFinite ? seconds : 0)) / 60 }
    private var palette: [Color] { MilestoneColors.palette(stage) }
    private var remainingMinutes: Int? { FocusMilestone.remainingAchievementMinutes(seconds: seconds) }
    private var countdownDescription: String {
        remainingMinutes.map { "仅剩 \($0) 分钟达成成就。" } ?? ""
    }
    var body: some View {
        VStack(spacing: 16) {
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || scenePhase != .active || stage.rawValue < 1)) { context in
                let angle = reduceMotion ? 0.0 : context.date.timeIntervalSinceReferenceDate * 0.18
                VStack(spacing: stage == .finalPush ? 2 : 10) {
                    if stage == .achieved {
                        HStack(spacing: 0) {
                            Text("🎉").font(.system(size: fontSize * (horizontal ? 0.65 : 0.48)))
                            MilestoneLettering(word: "YOU MADE IT.", size: fontSize * (horizontal ? 0.88 : 0.68),
                                               stage: stage, colors: palette, angle: angle)
                                .tracking(1.5)
                        }.lineLimit(1).minimumScaleFactor(0.5).padding(.vertical, 24)
                            .background { AchievementOrbit(stage: stage, angle: angle) }
                            .overlay(alignment: .topTrailing) { MilestoneStars(stage: stage, angle: angle).frame(width: 90, height: 24).offset(y: -6) }
                    } else if horizontal {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            if stage != .finalPush { title(angle: angle) }
                            time(angle: angle)
                        }.lineLimit(1).minimumScaleFactor(0.45)
                    } else {
                        VStack(spacing: 6) {
                            if stage != .finalPush { title(angle: angle) }
                            time(angle: angle)
                        }
                    }
                    if let remainingMinutes {
                        HStack(spacing: 0) {
                            Text("仅剩").foregroundStyle(.secondary)
                            Text("\(remainingMinutes)Mins").fontWeight(.semibold)
                                .foregroundStyle(AngularGradient(colors: MilestoneColors.lightStripColors, center: .center,
                                    angle: .radians(angle.truncatingRemainder(dividingBy: 2 * .pi))))
                            Text("达成成就").foregroundStyle(.secondary)
                        }.font(.system(size: horizontal ? 13 : 11, design: .rounded))
                            .monospacedDigit().lineLimit(1)
                    }
                    if !stage.encouragement.isEmpty {
                        Text(stage.encouragement).font(.system(size: horizontal ? (fontSize > 102 ? 14 : 13) : 10)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }.padding(.vertical, stage == .finalPush ? 12 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: stage)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(stage == .achieved ? "YOU MADE IT. " : "")今日已保存专注时长，\(minutes / 60) 小时 \(minutes % 60) 分钟。\(countdownDescription)\(stage.encouragement)")
        }.frame(maxWidth: 760)
    }
    private func title(angle: Double) -> some View {
        HStack(spacing: 0) {
            Text("Today’s ").foregroundStyle(.secondary)
            if stage == .radiant {
                MilestoneLettering(word: "focus", size: fontSize * (horizontal ? 0.45 : 0.51),
                                   stage: stage, colors: palette, angle: angle)
            } else {
                Text("focus").fontWeight(.semibold)
                    .foregroundStyle(stage == .gold ? palette[0] : Color.primary)
            }
        }.font(.system(size: fontSize * (horizontal ? 0.45 : 0.51), design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.6)
    }
    private func time(angle: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if stage == .beginning { Text("☹️").font(.system(size: fontSize * 0.85)) }
                MilestoneLettering(word: stage == .beginning ? "H" : "\(minutes / 60)H", size: fontSize,
                                   stage: stage, colors: stage == .finalPush ? MilestoneColors.roseSpectrum : palette, angle: angle)
            }
            if stage == .finalPush {
                MilestoneLettering(word: "\(minutes % 60)m", size: fontSize * 0.56,
                                   stage: stage, colors: palette, angle: angle)
            } else {
                Text("\(minutes % 60)m").font(.system(size: fontSize * 0.47, design: .rounded))
                    .foregroundStyle(stage == .radiant ? MilestoneColors.rgb(scheme == .dark ? 0xC8B6F0 : 0x9583CA) : Color.secondary)
            }
        }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            .background { if stage == .finalPush { AchievementOrbit(stage: stage, angle: angle) } }
            .overlay(alignment: .topTrailing) {
                if MilestoneColors.materialStage(stage).rawValue >= 5 {
                    MilestoneStars(stage: stage, angle: angle).frame(width: 58, height: 18).offset(x: 4, y: -8)
                }
            }
    }
}

/// A thin elliptical reflection, with an open highlight arc and a transparent center.
private struct AchievementOrbit: View {
    let stage: FocusMilestone
    let angle: Double
    var body: some View {
        GeometryReader { geometry in
            let colors = stage == .achieved
                ? [MilestoneColors.rgb(0xD2AC69), MilestoneColors.rgb(0xBD77A6), MilestoneColors.rgb(0x8B7DC0)]
                : MilestoneColors.roseSpectrum
            let reflection = LinearGradient(colors: [colors[0].opacity(0.04), colors[0].opacity(0.5),
                colors[1].opacity(0.08), colors[2].opacity(0.35), colors[2].opacity(0.03)],
                startPoint: UnitPoint(x: 0.1 + sin(angle * 0.35) * 0.15, y: 0),
                endPoint: UnitPoint(x: 0.9 + sin(angle * 0.35) * 0.1, y: 1))
            ZStack {
                Ellipse().stroke(LinearGradient(colors: [colors[0].opacity(0.13), .clear, colors[2].opacity(0.16)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
                Ellipse().trim(from: 0.06, to: 0.86).stroke(reflection, style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
                Ellipse().trim(from: 0.06, to: 0.86).stroke(reflection, lineWidth: 2.5).blur(radius: 2).opacity(0.4)
            }.frame(width: geometry.size.width * (stage == .achieved ? 0.98 : 1.08), height: geometry.size.height * (stage == .achieved ? 0.83 : 0.96))
                .rotationEffect(.degrees(stage == .achieved ? -8 : -12))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private enum MilestoneColors {
    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }
    static func materialStage(_ stage: FocusMilestone) -> FocusMilestone {
        (2...7).contains(stage.rawValue) ? FocusMilestone(rawValue: stage.rawValue + 1)! : stage
    }
    static let roseSpectrum: [Color] = [rgb(0xC73888), rgb(0x582187), rgb(0xA81550), rgb(0xC73888)]
    static let lightStripColors: [Color] = [rgb(0xDB3268), rgb(0x397ECC), rgb(0x7853BE), rgb(0xE96997), rgb(0xDB3268)]
    static func palette(_ stage: FocusMilestone, dark: Bool = false) -> [Color] {
        let values: [UInt32]
        switch materialStage(stage).rawValue {
        case 0: values = dark ? [0xB4B6C2, 0xE5E6EC, 0xA0A4B0] : [0x777D8B, 0xB5B8C3, 0x666D7A]
        case 1: values = dark ? [0xBFC5D0, 0xFFFFFF, 0xA7ADBD] : [0x717B90, 0xB9C1D0, 0x8A93A5]
        case 2: values = dark ? [0x9EAAC4, 0xF2F4FF, 0xC6CCDB] : [0x4B5670, 0xAEB7CC, 0x727D98]
        case 3: values = [0x5287BC, 0xA3CAE7, 0x346CA7]
        case 4: values = [0x245BB7, 0x927CCB, 0x443F9C, 0x5D91D0]
        case 5: values = [0x60339D, 0xCD5489, 0x3C60AB, 0xA15DB7]
        case 6: values = [0x54237D, 0xB42E69, 0xDA7DA7, 0x74439B]
        case 7: values = [0xB92F70, 0xF1A0A1, 0xD85B78, 0xA73168]
        case 8: values = [0x942359, 0xF29BA5, 0xD85F83, 0xBB3469, 0xF3B8BE]
        case 9: values = [0xC73888, 0x582187, 0xA81550]
        default: values = [0x7B1858, 0xD94A82, 0xEEA29A, 0xD2A55F, 0x7765BA, 0xF6CAD8, 0xAD326A]
        }
        return values.map(rgb)
    }
    static func atmosphere(_ stage: FocusMilestone) -> [Color] { palette(stage) }
}

/// The same moving color field fills text and glass; highlights remain inside the glyphs.
private struct PearlSilkField: View {
    let colors: [Color]
    let angle: Double
    let richness: Int
    var body: some View {
        ZStack {
            if #available(macOS 15, iOS 18, *) {
                MeshGradient(width: 3, height: 3, points: [
                    SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, 0.5), SIMD2<Float>(Float(0.5 + sin(angle * 0.55) * 0.17), Float(0.5 + cos(angle * 0.4) * 0.2)), SIMD2<Float>(1, 0.5),
                    SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1)
                ], colors: (0..<9).map { colors[$0 % colors.count] })
            } else {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Canvas { context, size in
                // Curved folds add directional reflection rather than a flat rainbow sweep.
                let count = richness >= 9 ? 4 : richness >= 4 ? 3 : 2
                context.addFilter(.blur(radius: max(0.6, size.height * 0.018)))
                for index in 0..<count {
                    let center = Double(index + 1) / Double(count + 1) + sin(angle * 0.4 + Double(index)) * 0.075
                    let width = richness >= 9 ? 0.065 : 0.09
                    var fold = Path()
                    fold.move(to: CGPoint(x: -size.width * 0.1, y: size.height * (center - width)))
                    fold.addCurve(to: CGPoint(x: size.width * 1.1, y: size.height * (center + 0.22 - width)),
                        control1: CGPoint(x: size.width * 0.25, y: size.height * (center - 0.35)),
                        control2: CGPoint(x: size.width * 0.65, y: size.height * (center + 0.48)))
                    fold.addLine(to: CGPoint(x: size.width * 1.1, y: size.height * (center + 0.22 + width)))
                    fold.addCurve(to: CGPoint(x: -size.width * 0.1, y: size.height * (center + width)),
                        control1: CGPoint(x: size.width * 0.65, y: size.height * (center + 0.48 + width)),
                        control2: CGPoint(x: size.width * 0.25, y: size.height * (center - 0.35 + width)))
                    fold.closeSubpath()
                    context.fill(fold, with: .linearGradient(Gradient(colors: [.white.opacity(0.04), .white.opacity(richness >= 9 ? 0.55 : 0.32), .white.opacity(0.03)]),
                        startPoint: CGPoint(x: 0, y: size.height * (center - width)),
                        endPoint: CGPoint(x: 0, y: size.height * (center + width * 1.5))))
                }
            }
            if richness == 10 {
                LinearGradient(colors: [.clear, MilestoneColors.rgb(0xEDC887).opacity(0.3), .clear],
                    startPoint: UnitPoint(x: 0.1 + sin(angle * 0.45) * 0.15, y: 0),
                    endPoint: UnitPoint(x: 0.65 + sin(angle * 0.45) * 0.15, y: 1))
                    .blendMode(.screen)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct MilestoneLettering: View {
    let word: String
    let size: CGFloat
    let stage: FocusMilestone
    let colors: [Color]
    let angle: Double
    @Environment(\.colorScheme) private var scheme
    private var lettering: Text {
        Text(word).font(.system(size: size, weight: MilestoneColors.materialStage(stage).rawValue >= 9 ? .heavy : MilestoneColors.materialStage(stage).rawValue >= 5 ? .bold : MilestoneColors.materialStage(stage).rawValue >= 3 ? .semibold : .medium, design: .rounded))
    }
    var body: some View {
        let materialColors = scheme == .dark && stage.rawValue < 3 ? MilestoneColors.palette(stage, dark: true) : colors
        lettering.foregroundStyle(materialColors[0])
            .overlay {
                Group {
                    if stage == .finalPush && word.hasSuffix("H") {
                        RoseFlowField(angle: angle)
                    } else {
                        PearlSilkField(colors: materialColors, angle: angle, richness: MilestoneColors.materialStage(stage).rawValue)
                    }
                }.mask(lettering)
            }
            .background {
                lettering.foregroundStyle(.white.opacity(0.7)).offset(y: -0.6)
                lettering.foregroundStyle(materialColors[0].opacity(0.28)).offset(y: 0.7)
            }
            .overlay {
                if stage.rawValue >= 9 {
                    LetteringSparkles(angle: angle, triumphant: stage == .achieved).mask(lettering)
                }
            }
            .brightness((scheme == .dark && MilestoneColors.materialStage(stage).rawValue >= 3 ? 0.14 : 0) + (stage.rawValue == 5 ? 0.08 : 0) + (stage == .finalPush ? 0.05 : 0))
            .shadow(color: materialColors[0].opacity(stage.rawValue >= 9 ? 0.16 : 0.08), radius: 2, y: 2)
            .lineLimit(1).minimumScaleFactor(0.5)
    }
}

private struct LetteringSparkles: View {
    let angle: Double
    let triumphant: Bool
    var body: some View {
        Canvas { context, size in
            for index in 0..<(triumphant ? 9 : 4) {
                let x = size.width * Double((index * 37 + 11) % 97) / 97
                let y = size.height * (0.18 + Double((index * 13) % 29) / 29 * 0.65)
                let pulse = pow(max(0, sin(angle + Double(index) * 1.7)), 8)
                context.opacity = pulse * 0.75
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct RoseFlowField: View {
    let angle: Double
    var body: some View {
        AngularGradient(colors: MilestoneColors.roseSpectrum, center: .center, angle: .radians(angle.truncatingRemainder(dividingBy: 2 * .pi)))
            .overlay(LinearGradient(colors: [.white.opacity(0.18), .clear, .white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct PearlInputSurface: ViewModifier {
    let seconds: Double
    let enabled: Bool
    var isInput = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        if enabled {
            let stage = FocusMilestone(seconds: seconds)
            let color = MilestoneColors.palette(stage, dark: scheme == .dark)[0]
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || scenePhase != .active || !isInput || stage.rawValue < 8)) { context in
                        let angle = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 0.45
                        let shape = RoundedRectangle(cornerRadius: 12)
                        if isInput && stage.rawValue >= 8 {
                            shape.strokeBorder(AngularGradient(colors: MilestoneColors.lightStripColors, center: .center, angle: .radians(angle.truncatingRemainder(dividingBy: 2 * .pi))), lineWidth: 2)
                            shape.strokeBorder(AngularGradient(colors: MilestoneColors.lightStripColors, center: .center, angle: .radians(angle.truncatingRemainder(dividingBy: 2 * .pi))), lineWidth: 3)
                                .blur(radius: 5).opacity(0.55)
                        } else if isInput && stage.rawValue >= 5 {
                            let gradient = LinearGradient(colors: [color.opacity(0.9), MilestoneColors.palette(stage).last!.opacity(0.9), color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            shape.strokeBorder(gradient, lineWidth: 1.8)
                            shape.strokeBorder(gradient, lineWidth: 3).blur(radius: 4).opacity(0.5)
                        } else {
                            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.85), color.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        }
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
        } else { content }
    }
}

/// Apply to the whole control so native Menu and Button receive the same hover surface.
struct ToolbarHoverSurface: ViewModifier {
    let seconds: Double
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    func body(content: Content) -> some View {
        let color = MilestoneColors.palette(FocusMilestone(seconds: seconds), dark: scheme == .dark)[0]
        content.background {
            RoundedRectangle(cornerRadius: 9)
                .fill(color.opacity(hovering && enabled ? 0.08 : 0))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(hovering && enabled ? 0.6 : 0)))
                .shadow(color: color.opacity(hovering && enabled ? 0.18 : 0), radius: 5, y: 2)
                .allowsHitTesting(false)
        }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
    }
}

private struct MilestoneStars: View {
    let stage: FocusMilestone
    let angle: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<(MilestoneColors.materialStage(stage).rawValue < 7 ? 1 : 3), id: \.self) { index in
                Text("✦").font(.system(size: index == 1 ? 9 : 5))
                    .foregroundStyle(MilestoneColors.palette(stage)[0])
                    .opacity(reduceMotion ? 0.65 : 0.5 + 0.2 * sin(angle + Double(index)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Continuous celebration is visual only; it never reads or writes daily celebration claims.
struct MilestoneHomeEffect: ViewModifier {
    let seconds: Double
    let enabled: Bool
    let backdrop: Color
    var dailySeconds: ((Date) -> Double)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { minute in
            let current = dailySeconds?(minute.date) ?? seconds
            let stage = FocusMilestone(seconds: current)
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || scenePhase != .active || !enabled || stage.rawValue < 1)) { context in
                let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                let celebrating = enabled && stage == .achieved
                let impulse = celebrating && !reduceMotion ? sin(time * 0.7) : 0
                ZStack {
                    (enabled ? (scheme == .dark ? Color(red: 0.085, green: 0.075, blue: 0.10) : Color(red: 0.985, green: 0.98, blue: 0.975)) : backdrop).ignoresSafeArea()
                    if enabled {
                        MilestoneAtmosphere(stage: stage, time: time,
                                            celebration: celebrating && !reduceMotion ? (time.truncatingRemainder(dividingBy: 8) / 2) : 0)
                    }
                    content.scaleEffect(1 + impulse * 0.003).offset(y: -impulse * 1.5)
                    if celebrating {
                        PaperCelebration(elapsed: time, still: reduceMotion)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct MilestoneAtmosphere: View {
    let stage: FocusMilestone
    let time: Double
    let celebration: Double
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            let colors = MilestoneColors.atmosphere(stage)
            let intensity = (scheme == .dark ? 0.10 : 0.025) + Double(stage.rawValue) * (stage.lightsHome ? 0.007 : 0.003)
            let drift = sin(time / 22) * 0.045
            let burst = celebration > 0 ? sin(min(1, celebration / 4) * .pi) : 0
            for index in 0..<min(4, colors.count) {
                let y = size.height * (0.15 + Double(index) * 0.25 + drift)
                var ribbon = Path()
                ribbon.move(to: CGPoint(x: -size.width * 0.15, y: y))
                ribbon.addCurve(to: CGPoint(x: size.width * 1.15, y: y + size.height * 0.18),
                    control1: CGPoint(x: size.width * 0.2, y: y - size.height * (0.3 + burst * 0.12)),
                    control2: CGPoint(x: size.width * 0.7, y: y + size.height * 0.38))
                var silk = context
                silk.addFilter(.blur(radius: 32))
                silk.stroke(ribbon, with: .linearGradient(Gradient(colors: [.clear, colors[index].opacity(intensity + burst * 0.05), .white.opacity(intensity), .clear]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: size.height * (stage.lightsHome ? 0.22 : 0.12))
            }
            for index in 0..<(stage == .achieved ? 26 : stage == .finalPush ? 18 : stage == .radiant ? 12 : max(0, stage.rawValue - 5)) {
                let horizontalSeed = Double((index * 37) % 97) / 97
                let x = size.width * (stage.rawValue >= 8 ? (index % 2 == 0 ? 0.04 + horizontalSeed * 0.16 : 0.8 + horizontalSeed * 0.16) : (index % 2 == 0 ? 0.055 : 0.945))
                let y = size.height * (stage.rawValue >= 8 ? 0.05 + Double((index * 23 + 9) % 89) / 89 * 0.9 : 0.16 + Double(index / 2) * 0.22)
                let glint = 0.4 + 0.15 * sin(time / 4 + Double(index))
                context.opacity = glint
                context.fill(star(at: CGPoint(x: x, y: y), radius: index % 3 == 0 ? 3 : 2), with: .color(colors[index % colors.count]))
            }
            if celebration > 0 {
                let progress = min(1, celebration / 4)
                let center = CGPoint(x: size.width * (-0.2 + progress * 1.4), y: size.height * 0.4)
                context.opacity = sin(progress * .pi) * 0.12
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.96, green: 0.82, blue: 0.56), .clear]),
                    center: center, startRadius: 0, endRadius: max(size.width, size.height) * 0.6))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
    private func star(at point: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: point.x, y: point.y - radius))
            path.addLine(to: CGPoint(x: point.x + radius * 0.3, y: point.y - radius * 0.3))
            path.addLine(to: CGPoint(x: point.x + radius, y: point.y))
            path.addLine(to: CGPoint(x: point.x + radius * 0.3, y: point.y + radius * 0.3))
            path.addLine(to: CGPoint(x: point.x, y: point.y + radius))
            path.addLine(to: CGPoint(x: point.x - radius * 0.3, y: point.y + radius * 0.3))
            path.addLine(to: CGPoint(x: point.x - radius, y: point.y))
            path.addLine(to: CGPoint(x: point.x - radius * 0.3, y: point.y - radius * 0.3))
            path.closeSubpath()
        }
    }
}

private struct PaperCelebration: View {
    let elapsed: Double
    let still: Bool
    var body: some View {
        Canvas { context, size in
            let colors = [MilestoneColors.rgb(0xDAB97E), MilestoneColors.rgb(0xE7AFBF), MilestoneColors.rgb(0xB8ACD6), MilestoneColors.rgb(0xEECCD1)]
            for index in 0..<(still ? 24 : 72) {
                let seed = Double((index * 37) % 97) / 97
                let age = (elapsed + seed * 8).truncatingRemainder(dividingBy: 8)
                let progress = age / 8
                let horizontalSeed = Double((index * 53 + 17) % 101) / 101
                let x = size.width * (0.02 + horizontalSeed * 0.96 + sin(age * 1.2 + Double(index)) * 0.025)
                let y = size.height * (-0.08 + progress * 1.2)
                var paper = context
                paper.opacity = sin(progress * .pi) * 0.65
                paper.translateBy(x: x, y: y)
                paper.rotate(by: .radians(age * (index % 2 == 0 ? 3 : -3) + seed * 6))
                let width = CGFloat(3 + index % 3)
                let height = CGFloat(2 + index % 4)
                paper.fill(Path(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), cornerRadius: 0.6), with: .color(colors[index % colors.count]))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
