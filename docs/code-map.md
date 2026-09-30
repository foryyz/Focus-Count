# FocusCount 功能与代码定位索引

核对日期：2026-09-30。对应当前工作区：Mac 1.19.7 / iPhone 1.5.6。本文描述当前实现，不是历史需求清单。开发流程见 [development-guide.md](development-guide.md)。

## 如何使用

先按功能找下面的章节，再在指定文件搜索类型或函数名。函数签名在表中可能省略参数；同名函数必须结合所属类型定位。SwiftUI 的布局大量写在 `body` 或计算属性里，它们不是独立函数。不要只搜索 `func`。

路径缩写仅用于正文：`Core` = `packages/FocusCountCore/Sources/FocusCountCore/`，`Mac` = `apps/macos/Sources/FocusCount/`，`Phone` = `apps/ios/FocusCount/`。表中的文件链接均可直接打开。

## 1. 架构与入口

| 范围 | 文件与入口 | 职责 |
|---|---|---|
| 公共模型 | [Core/Models.swift](../packages/FocusCountCore/Sources/FocusCountCore/Models.swift)：`StudySession`、`TimeEvent`、`Database`、`SessionSnapshot`、`TimerTransfer` | 专注记录、单次标记、交换容器、历史快照、跨设备计时 |
| Mac 启动和首页 | [Mac/FocusCountApp.swift](../apps/macos/Sources/FocusCount/FocusCountApp.swift)：`FocusCountApp`、`AppDelegate`、`ContentView.body` | 应用生命周期、主窗口、所有首页入口 |
| Mac 状态与写入 | [StudyStore.swift](../apps/macos/Sources/FocusCount/StudyStore.swift)：`StudyStore.init`、`persist()`、`commit(_:)` | 业务操作、计时推进、原子写入及错误反馈 |
| iPhone 启动和首页 | [Phone/FocusCountApp.swift](../apps/ios/FocusCount/FocusCountApp.swift)：`FocusCountPhoneApp`、`TimerScreen.body` | NavigationStack、sheet、沉浸界面和 scenePhase |
| iPhone 状态与写入 | [PhoneStore.swift](../apps/ios/FocusCount/PhoneStore.swift)：`PhoneState`、`PhoneStore.init`、`commit(_:)` | 手机本机状态、记录操作、模式及通知协调 |

**共享代码不只在 Core。** Xcode 工程直接编译部分 Mac 目录文件。准确列表看 [generate-ios-project.py](../scripts/generate-ios-project.py) 的共享文件循环，以及 [project.pbxproj](../apps/ios/FocusCount.xcodeproj/project.pbxproj) 的 Sources 引用；其中包括事件分析、标记图表、颜色、分类、今日统计和目标倒数。改这些文件必须考虑两端。

## 2. 首页、品牌、字号、动画和窗口

| 功能 | Mac 定位 | iPhone 定位 |
|---|---|---|
| 首页排版、导航图标 | `ContentView.body`，位于 Mac `FocusCountApp.swift` | `TimerScreen.body`、`brandItem`，位于 Phone `FocusCountApp.swift` |
| Today’s focus 与励志文字 | [TodaySummaryView.swift](../apps/macos/Sources/FocusCount/TodaySummaryView.swift)：`TodayFocusHero.body`；字号由 `ContentView` 传入 | `TimerScreen.welcome`；标题、时长、励志语和输入框在这里；`greetings` 保存文案 |
| 计时数字和暂停样式 | `ContentView.timerDigits(size:)`、`phase`、`pauseInk` | `TimerScreen.timer(width:)`、`running`、`pauseInk` |
| 开始按钮彩色效果、专注波纹 | [FocusPresentation.swift](../apps/macos/Sources/FocusCount/FocusPresentation.swift)：`PrismaticStartStyle.makeBody`、`FocusFlow.body` | Phone `FocusCountApp.swift` 内同名类型，**独立实现** |
| 全屏与主窗口外观 | `FocusWindow.attach(_:)`、`toggle()`、`FocusWindowReader`，位于 `FocusPresentation.swift` | `TimerScreen.immersive`，是隐藏导航等内容的沉浸状态，不是 Mac 全屏 API |
| 全屏时控件显隐 | `ContentView.visible`、`revealControls()`、`.task(id: interaction)` | `TimerScreen.body` 中 `immersive` 条件 |
| 左下角今日概览 | `ContentView` 的 bottomLeading overlay → `TodaySummaryView` | `TimerScreen` 的 bottom safeAreaInset → [PhoneDashboard.swift](../apps/ios/FocusCount/PhoneDashboard.swift) 的 `PhoneTodaySheet` |

iPhone 品牌使用 `brandItem`；iOS 26+ 调用 `sharedBackgroundVisibility(.hidden)`，文字 `fixedSize`，避免被工具栏圆形背景压缩。不要重新把它当作普通圆形图标按钮。

## 3. 普通计时：开始、暂停、结束、取消

- [Core/Models.swift](../packages/FocusCountCore/Sources/FocusCountCore/Models.swift)：`StudyClock.now`；`TimerState.seconds(now:)`、`toggle(date:now:)`、`pause(now:)`、`checkpoint(now:)`。Mac 普通计时的基础。
- [Core/MobileClock.swift](../packages/FocusCountCore/Sources/FocusCountCore/MobileClock.swift)：`MobileClock.seconds(at:)`、`toggle(at:)`、`pause(at:)`、`finish(at:)`、`isValid`。手机使用可持久化的日期基准。
- Mac UI：`ContentView.submitActivity()`、`toggleTimer()` → `StudyStore.toggle()`、`pause()`、`finish()`、`save(subject:focus:)`、`cancelTimer()`；`resumeEditingTimer()` 返回待保存计时。
- iPhone UI：`TimerScreen.startOrMark()`、`actionButtons` → `PhoneStore.start(activity:)`、`toggle()`、`finish()`、`save(_:completesTimer:)`、`cancelTimer()`；`returnToTimer()` 返回计时。
- Mac 休眠：`StudyStore.prepareForSleep()`、`refreshAfterWake()`；通知注册在 `init`。
- 手机后台：`FocusCountPhoneApp` 的 scenePhase → `checkpoint()` / `becameActive()`。

**结束和保存是两步。** `finish()` 进入 `pendingEnd`，保存编辑页确认后才生成记录。取消清空当前未保存计时，不删除旧记录。

## 4. 专注模式与微休息

| 层次 | 文件、类型及成员 | 修改场景 |
|---|---|---|
| 模式定义、默认参数 | [Core/FocusRoutine.swift](../packages/FocusCountCore/Sources/FocusCountCore/FocusRoutine.swift)：`FocusMode`、`FocusRoutineSettings`、`isValid` | 增加模式、修改默认时间或参数范围 |
| 阶段状态机 | 同文件：`FocusRoutine.Phase`、`advance(_:random:)`、`nextRound(random:)`、`skipRest(random:)` | 专注→微休息→长休息→等待下一轮；`advance` 返回有效专注秒数 |
| Mac 调度 | `StudyStore.setMode(_:)`、`advanceRoutine(now:)`、`skipModeRest()`、`isRunning`、`isResting` | 连接状态机、计时器、声音和持久化 |
| Mac 选择与参数 UI | [FocusModeViews.swift](../apps/macos/Sources/FocusCount/FocusModeViews.swift)：`FocusMode.symbol/title`、`FocusModeMenuView`、`FocusModeSettingsView.soundPicker`、`ModeRestView` | 模式图标、单击切换、横向参数菜单、休息倒计时 |
| 手机整轮时间表 | [PhoneRoutine.swift](../apps/ios/FocusCount/PhoneRoutine.swift)：`PhoneRoutine.init(settings:at:)`、`init(routine:at:)`、`advance(at:)`、`reminders(at:)`、`skipRest(at:)` | 固定这一轮的随机序列，后台恢复不能重新抽签 |
| 手机阶段与接续 | 同文件：`phase`、`remaining`、`roundRemaining`、`portable`、`isValid`、`supports(_:)` | 阶段判定、导出公共状态、检查手机提醒数量 |
| 手机调度 | `PhoneStore.setMode(_:)`、`settled(_:at:)`、`tick(at:)`、`skipRest()`、`refreshNotifications()` | 累积有效时间并刷新提醒 |
| 手机选择与参数 UI | [PhoneModeViews.swift](../apps/ios/FocusCount/PhoneModeViews.swift)：`PhoneModeMenu`、`PhoneModeSettings.soundPicker`、`PhoneRestView` | 手机设置、声音选择、试听、跳过休息 |

`FocusMode` 的 `symbol/title` 扩展在两端各有一份。默认模式互斥；参数修改下轮生效。微休息自动结束，长休息结束停在 `ready`，需手动开始下一轮。

## 5. 提示音、导入音频与后台通知

| 功能 | 代码位置 |
|---|---|
| Mac 声音库 | [SoundLibrary.swift](../apps/macos/Sources/FocusCount/SoundLibrary.swift)：`FocusSound`、`SoundLibrary.builtins`、`sound(_:)`、`importSound()`、`add(_:)`、`rename(_:to:)`、`save(_:)` |
| Mac 声音设置页 | 同文件：`SoundSettingsView`、`SoundNameRow`；入口在 `ContentView` 齿轮按钮 |
| Mac 实际播放 | `StudyStore.previewModeSound(id:volume:)`、`playModeSound(_:volume:)`、`advanceRoutine(now:)` 的阶段切换分支 |
| 手机声音库 | [PhoneSounds.swift](../apps/ios/FocusCount/PhoneSounds.swift)：`PhoneSounds.presets`、`url(_:)`、`play(_:volume:)`、`add(_:)`、`rename(_:name:)` |
| 手机声音设置页 | 同文件：`PhoneSoundSettings`、`preview(_:)`；`.fileImporter` 导入文件、alert 改名 |
| 手机通知音频转换 | `PhoneSounds.notificationSound(_:)`：生成 `Library/Sounds/*.caf`，截取最多 29 秒 |
| 后台通知安排 | `PhoneNotifications.replace(_:report:)`、`userNotificationCenter(_:willPresent:withCompletionHandler:)`，位于 `PhoneRoutine.swift` |
| 手机内置音频 | [Sounds/](../apps/ios/FocusCount/Sounds/)：六个 WAV，Xcode 以文件夹资源复制 |

手机试听与 Picker 必须是不同 Form 行：`PhoneModeSettings.soundPicker` 返回 `Group`，试听用 `.buttonStyle(.borderless)`。放回同一个 VStack 行会再次出现“点试听却打开选择器”。

**声音同步在设置中选择，默认关闭并持久保存。** Store 的 `export()` 携带 `sounds` 文件及独立 `soundPreferences`；`importRecords(_:syncTimer:syncSounds:syncParameters:)` 分别控制计时、声音和数值参数。`stageSounds(_:)` 验证音频后使用 Core `SoundFileTransaction` 批量写入；记录写入失败时回滚音频。`SharedPreferences.mode` 仍只包含五个时间数值，默认模式不参与同步。

## 6. 专注记录、编辑、最近删除和历史版本

- Mac：[HistoryView.swift](../apps/macos/Sources/FocusCount/HistoryView.swift) 的 `HistoryFilter.apply`、`HistoryView.body`、`SessionEditor`；紧凑条形图在 [HistoryMiniCharts.swift](../apps/macos/Sources/FocusCount/HistoryMiniCharts.swift) 的 `DailyBars`、`SubjectBars`、`HistoryMiniCharts`。
- Mac 写入：`StudyStore.upsert(_:)`、`setDeleted(_:deleted:)`、`permanentlyDelete(_:)`、`restoreVersion(_:)`。
- iPhone：[PhoneHistory.swift](../apps/ios/FocusCount/PhoneHistory.swift) 的 `PhoneHistory`、`row(_:)`；[RecordEditor.swift](../apps/ios/FocusCount/RecordEditor.swift) 的 `RecordEditor.body`；[ExchangeScreen.swift](../apps/ios/FocusCount/ExchangeScreen.swift) 的 `PhoneVersionHistory`。
- 手机写入：`PhoneStore.save(_:completesTimer:)`、`delete(_:restore:)`、`permanentlyDelete(_:)`、`restoreVersion(_:)`。
- Core 校验：`StudySession.validationError`；历史合并：`RecordExchange.replacing`、`retainingVersions`、`archivedCount`。这些函数在 **MobileClock.swift**，不要因文件名只想到计时。

## 7. 时间标记：命令、时间轴、emoji 和颜色

- Mac 命令：[StudyStore.swift](../apps/macos/Sources/FocusCount/StudyStore.swift) 的 `FocusCommand.init(_:)`；首页 `submitActivity()` / `submit()` 调用 `markEvent(kind:at:)`。
- 手机命令：`TimerScreen.startOrMark()` / `submitMarker()` → `PhoneStore.markCommand(_:at:)` → `markEvent(kind:at:)`。
- 两端修改/删除：Store 的 `updateEvent(_:kind:at:)`、`setEventDeleted(_:deleted:)`、`purgeEvents(_:)`。
- Mac 页面：[EventHistoryView.swift](../apps/macos/Sources/FocusCount/EventHistoryView.swift) 的 `EventHistoryView`；独立窗口 [MarkerWindowController.swift](../apps/macos/Sources/FocusCount/MarkerWindowController.swift) 的 `show(store:)`、`windowWillClose(_:)`；编辑器在 [MarkerVisualizationPanel.swift](../apps/macos/Sources/FocusCount/MarkerVisualizationPanel.swift) 的 `MarkerEventEditor`。
- 手机页面：[PhoneMarkerScreen.swift](../apps/ios/FocusCount/PhoneMarkerScreen.swift) 的 `PhoneEventHistory`、`charts(compact:)`、`recordRow(_:)`、`PhoneMarkerEditor`。
- 共享外观：[MarkerColors.swift](../apps/macos/Sources/FocusCount/MarkerColors.swift) 的 `setEmoji(_:for:)`、`ensure(_:)`、`nextColor(used:)`、`set(_:for:)`、`color(_:)`；emoji 截取一个 Swift Character（允许组合 emoji）。

当前所有 `!文字` 都是标记，`!stop` 不结束计时。大小写规范化应同时检查命令入口和 `EventAnalytics.label(_:)`。

## 8. 时间标记可视化

| 想改什么 | 文件 / 类型 / 关键成员 |
|---|---|
| 周期过滤、频率、平均每周次数 | [EventAnalytics.swift](../apps/macos/Sources/FocusCount/EventAnalytics.swift)：`records`、`periodStart`、`frequencies`、`weeklyRate`、`weeklyText`、`hours`、`dailyCounts` |
| 长周期聚合粒度及点面积 | [MarkerOverviewData.swift](../apps/macos/Sources/FocusCount/MarkerOverviewData.swift)：`MarkerGranularity.resolved(days:)`、`MarkerOverviewData.init`、`diameter(count:unit:limit:)` |
| 长周期趋势、频率气泡 | [MarkerFrequencyOverview.swift](../apps/macos/Sources/FocusCount/MarkerFrequencyOverview.swift)：`chart`、`scale`、`bubble`、`inspector`、`zoom` |
| 时间分布缩放、可见日期范围 | [MarkerTimelineChart.swift](../apps/macos/Sources/FocusCount/MarkerTimelineChart.swift)：`updateZoom`、`resetWindow`、`body` |
| 24 小时内点/emoji 排布、拥挤聚合 | [MarkerPointLayout.swift](../apps/macos/Sources/FocusCount/MarkerPointLayout.swift)：`items(events:start:offset:visibleDays:width:hourHeight:calendar:)` |
| emoji 与聚合点实际绘制 | [MarkerPointTimeline.swift](../apps/macos/Sources/FocusCount/MarkerPointTimeline.swift)：`MarkerPointTimeline.body` |
| 范围选框拖拽 | [MarkerRangeNavigator.swift](../apps/macos/Sources/FocusCount/MarkerRangeNavigator.swift)：`body` 的手势；Mac 同时检查 `MarkerWindowController.show` 的窗口拖动属性 |
| Mac 可视化容器 | `MarkerVisualizationPanel`、`EventHistoryView` |
| iPhone 页面、横竖屏适配 | `PhoneMarkerCharts`、`PhoneTimeDistribution`，位于 `PhoneMarkerScreen.swift`；组合以上共享图表 |

## 9. 专注分析、分类和颜色

| 层次 | 文件及成员 |
|---|---|
| 聚合算法 | [FocusAnalysisData.swift](../apps/macos/Sources/FocusCount/FocusAnalysisData.swift)：`interval`、`filtered`、`dayCount`、`grain`、`buckets`、`trailingWeekAverage`、`breakdown` |
| 分类模型 | 同文件：`FocusCategory`、`FocusAppearance`、`FocusBucket`、`FocusBreakdown` |
| 分类/颜色写入 | [FocusAppearanceStore.swift](../apps/macos/Sources/FocusCount/FocusAppearanceStore.swift)：`change`、`addCategory`、`rename`、`remove`、`assign`、`ensureColors`、`setColor`、`categoryID` |
| Mac 页面与独立窗口 | [FocusAnalysisView.swift](../apps/macos/Sources/FocusCount/FocusAnalysisView.swift)：`body`、`details`、`itemColor`、`clearSelection`；[FocusAnalysisWindow.swift](../apps/macos/Sources/FocusCount/FocusAnalysisWindow.swift)：`show(store:)` |
| Mac 分类编辑 | [FocusCategoryEditor.swift](../apps/macos/Sources/FocusCount/FocusCategoryEditor.swift)：`body`、`add()` |
| 趋势折线与选择 | [FocusTrendChart.swift](../apps/macos/Sources/FocusCount/FocusTrendChart.swift)：`body`、`point(at:proxy:geometry:)`、`axisLabel` |
| 环形/扇形占比、大号日柱图 | [FocusShareChart.swift](../apps/macos/Sources/FocusCount/FocusShareChart.swift)：`FocusShareSlice.make`、`FocusShareChart.body`、`FocusLargeDailyBars` |
| 手机页面/分类编辑 | [PhoneFocusAnalysis.swift](../apps/ios/FocusCount/PhoneFocusAnalysis.swift)：`PhoneFocusAnalysis`、`color(_:)`、`PhoneFocusAppearance` |

## 10. 今日概览和目标倒数

- 共享今日统计：`TodaySummary.init(database:now:calendar:)`、`seconds`，位于 `TodaySummaryView.swift`。仅统计当天开始的未删除已保存记录，不包括当前草稿。
- 手机统计入口：`PhoneStore.today(at:)`（扩展在 `PhoneDashboard.swift`）。
- 目标数据：[Core/GoalSnapshot.swift](../packages/FocusCountCore/Sources/FocusCountCore/GoalSnapshot.swift) 的 `GoalSnapshot.isValid`、`merge(_:_:)`。
- 共享目标逻辑：[TargetCountdown.swift](../apps/macos/Sources/FocusCount/TargetCountdown.swift) 的 `TargetDate.deadline`、`remaining`；`TargetCountdownStore.receive`、`save`、`setHidden`、`hide`、`setTotalHours`、`remove`。主数据写回通过初始化传入的 `writer` 调用两端 `updateGoal(_:)`。
- Mac UI：`TargetCountdownRow`、`TargetCountdownSettings`；手机 UI：`PhoneCountdownFooter`、`PhoneTargetSettings`（`PhoneDashboard.swift`）。

## 11. 数据同步与持久化

| 入口/规则 | 位置 |
|---|---|
| JSON 校验/编码、记录与事件合并 | [Core/MobileClock.swift](../packages/FocusCountCore/Sources/FocusCountCore/MobileClock.swift)：`RecordExchange.decode`、`encode`、`merge`、`mergeEvents`、`modified` |
| 通用计时接续 | `TimerTransfer.seconds(at:)`、`timerState(at:now:)`、`mobileClock(at:)`、`isValid`，在 Core `Models.swift` |
| 偏好按键合并、删除标记 | [SharedPreferences.swift](../packages/FocusCountCore/Sources/FocusCountCore/SharedPreferences.swift)：`SharedSettings.merge`、`SharedPreferences.current`、`capture`、`validate`、`apply`、`numbersOnly` |
| 仅同步模式数值 | 同文件：`ModeParameters.init(_:)`、`applying(to:)`；保留接收端的模式偏好和声音配置 |
| Mac 导入导出 | `StudyStore.importRecords(_:syncTimer:syncSounds:syncParameters:)`、`export()`；[DataExchangeView.swift](../apps/macos/Sources/FocusCount/DataExchangeView.swift) 的预览、文件选择和确认按钮 |
| 手机导入导出 | `PhoneStore.importRecords(_:syncTimer:syncSounds:syncParameters:)`、`export()`；[ExchangeScreen.swift](../apps/ios/FocusCount/ExchangeScreen.swift) 的文件读写 UI；`PhoneImportFile.read(_:)` 在 `PhoneStore.swift`，负责安全作用域与文件协调 |
| Mac 路径、旧数据迁移、CSV | [Mac/Models.swift](../apps/macos/Sources/FocusCount/Models.swift)：`Storage.directory`、`legacyDirectory`、`projectDirectory`、`migrateProjectData`、`migrateLegacyData`、`csv` |

调用链：文件选择 → `RecordExchange.decode` → 用户确认 → Store 的 `importRecords` → 备份 → 合并/写入 → `SharedPreferences.apply` → 外观 Store 监听 `SharedPreferences.changed` 刷新。

导出必须经过平台 Store 的 `export()`，不能仅把原始状态 JSON 当成同步文件；这里负责计时快照、收集偏好、声音附件、声音设置与导出来源。

新增同步辅助代码：[Core/ExchangePreview.swift](../packages/FocusCountCore/Sources/FocusCountCore/ExchangePreview.swift)。`ExchangeSource` 记录导出时间与设备；`SoundPreferences` 传递声音选择与音量；`ExchangePreview.changes` 计算变化；`ImportArchive.list/read` 发现与读取导入历史（兼容旧 iPhone 本机备份）；`SoundFileTransaction` 管理声音批量提交与回滚。

两端 Store 的 `importArchives()` 提供历史列表，`importPreview` 提供实际变化摘要。历史页面同时显示“导入历史”和“记录修改版本”：前者重新进入合并预览，不代表整库回退，也不会撤销永久删除；后者保留单条记录恢复能力。

## 12. 测试和脚本快速定位

- [Core tests](../packages/FocusCountCore/Tests/FocusCountCoreTests/)：`CoreTests`、`TimerTransferTests`、`GoalSnapshotTests`、`FocusRoutineTests`、`SharedPreferencesTests`。
- [Mac tests](../apps/macos/Tests/FocusCountTests/)：存储/历史、模式、声音、今日统计、目标、分析与标记布局各有测试文件。
- [PhoneStoreTests.swift](../apps/ios/Tests/PhoneStoreTests.swift)：包含 `PhoneStoreTests`、`PhoneLayoutTests` 及标记分析/布局测试类。`testModeScreens()` 和 `testCompactAndLandscapeScreens()` 使用合成数据生成截图；`render(_:name:size:)` 是截图辅助方法。
- [build-app.sh](../scripts/build-app.sh)：Mac Release、应用包、版本号、临时签名；调用 [package-macos.py](../scripts/package-macos.py) 校验 ZIP 并归档旧版。
- [build-ios.sh](../scripts/build-ios.sh)：无签名模拟器构建。
- [generate-ios-project.py](../scripts/generate-ios-project.py)：生成 Xcode 工程及 scheme；会覆盖本机项目配置，使用前看开发指南。
- 图标：`apps/macos/Resources/FocusCount.icns`、`apps/ios/FocusCount/Assets.xcassets/AppIcon.appiconset/`；脚本 `generate-icons.sh`、`generate-ios-icon.swift`。

新增、迁移或重命名功能时，同步更新本索引对应条目。优先维护入口与关键函数，不必列出每个内部绘图辅助函数。


### 历史删除与导出时间（1.19.3 / 1.5.3）

两端 Store 的 `deleteArchive(_:)` 通过 `ImportArchive.delete(directory:phone:)` 删除指定本机备份。iPhone 完整备份的旧本机状态副本同时移除，避免列表回退显示隐藏副本；不删除当前数据库或相邻备份。

`deleteVersion(_:)` 调用 `RecordExchange.deletingVersion(_:from:)`，只删除指定旧快照。`StudySession.purgedHistoryIDs` 保存已删除快照的 SHA-256 ID，`retainingVersions` 合并删除标记并过滤旧版本；`decode` 也校验和过滤。不要为清理历史更新时间戳或删除当前记录，也不要在后续编辑/恢复时丢掉这些删除标记。双端更新后可防止旧导入文件复活已删除历史。

`ExchangeSource.exportedAt` 在导出时写入，沿用数字日期编码保持兼容；新增 `exportedAtISO8601` 提供人可读时间。后者是展示副本，读取以 `exportedAt` 为准。预览不使用文件修改时间或旧计时快照时间冒充导出时间，旧文件缺少字段时显示未知。文件名和其他内容修改不会改变内嵌时间；这不是数字签名，时间字段本身仍可被手工修改。


### 删除全部历史版本（Mac 1.19.4 / iPhone 1.5.4）

两端历史页面新增“删除全部历史版本”，确认时列出导入备份和记录旧版本数量。两端 Store 的 `deleteAllHistory()` 先原子保存所有记录的旧版本删除标记（Core `RecordExchange.deletingAllVersions(from:)`），再删除本机导入备份；保留当前记录、最近删除记录、时间标记及计时。数据库保存失败时不删除备份；文件清理失败会显示错误并刷新剩余备份，允许重试。不会为本次清理再生成一份历史备份。记录旧版本的删除标记参与后续同步，其他设备的本机备份需在对应设备清理。


### 本机同步偏好（Mac 1.19.5 / iPhone 1.5.5）

“同步自定义提示音与声音设置”和“同步模式数值参数”移至设置中的“同步设置”，默认关闭，按设备持久记忆。导入预览不再显示这两个开关，每次直接使用本机选择；计时状态仍在预览中临时选择，默认关闭。

共享常量 `SyncPreferences.soundsKey/parametersKey` 位于 Core `SharedPreferences.swift`；两端设置页和交换页通过 `@AppStorage` 使用同一组本机键。导入时仍向 Store 显式传入两个选择，预览变化也按相同选择计算。这两个偏好不进入 `SharedPreferences` 交换内容，导入其他设备的数据不会重置它们。导出内容不受本机导入偏好影响。此规则替代上一版“每次导入默认开启”的交互。


### 聚合标记数量（Mac 1.19.6 / iPhone 1.5.6）

两端频率总览的聚合次数达到 4 次即显示下方小数字，不再仅在尺寸封顶时显示。Mac 时间分布也采用相同的 `MarkerCountBadge`（`MarkerFrequencyOverview.swift`，9pt 数字、浅色胶囊背景），布局为数字预留避让空间。无 emoji 的彩色点同样标注。Mac 时间分布的 2 次聚合直径由 44 降至 34，3 次仍约 48，其余放大规则保留。频率总览的窄日期列按数字宽度保留最小间距，必要时横向滚动。

### Mac 占比图标签（1.19.7）

`FocusShareChart.swift` 中 Mac 使用 `MacFocusShareDiagram`：`placements` 测量名称和占比、搜索字号/换行宽度/位置；`layout` 按需预留外侧标签空间；`ink` 调整内外文字对比度。`ShareLabelGeometry.fits` 检查标签是否完整位于扇区内并避开圆环中心。iPhone 保留原有布局。几何边界与浅深色渲染回归见 `ShareLabelTests.swift`。
