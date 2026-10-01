# FocusCount 开发与交接指南

核对日期：2026-10-02。对应当前工作区：Mac 1.20.0 / iPhone 1.5.6。具体功能、文件和函数见 [code-map.md](code-map.md)。本文说明修改方法和必须保持的行为。

## 1. 接手顺序

1. 阅读 [README.md](../README.md)，了解产品和运行方法；历史更新说明不一定代表当前实现。
2. 按 [功能索引](code-map.md) 找入口，沿 UI → Store → Core → 持久化追踪。修改前先读相应测试。
3. 执行 `git status --short`，区分已有改动与本次任务。特别保留个人签名、Info.plist 和 Xcode 用户配置。
4. 涉及数据时阅读 [data-format.md](data-format.md)，再核对 `Database`、`RecordExchange` 和两端 Store 的实际导入导出路径。
5. 修改、做针对性验证，更新受影响的文档。不要把旧辅助函数的存在当成功能已经启用。

本文按功能组织，两端差异在对应章节说明。只改一个平台的界面，也要检查该源文件是否被另一端编译。

## 2. 工程边界

| 路径 | 职责 | 开发注意事项 |
|---|---|---|
| `packages/FocusCountCore/` | 公共模型、计时、模式状态机、合并协议和设置同步 | 尽量保持独立于平台界面；公共规则优先放这里 |
| `apps/macos/` | Swift Package，SwiftUI / AppKit 应用及测试 | 除 Mac 专用代码外，也存放部分两端共用的图表和设置实现 |
| `apps/ios/` | Xcode 工程、手机界面、存储、通知、音频及测试 | iPhone 使用独立 Store，并直接引用部分 Mac 源文件 |
| `scripts/` | Mac 打包、iPhone 构建、工程生成、归档 | 生成脚本不等于日常构建命令 |
| `dist/` | 构建和分发产物 | 不应作为源代码或用户数据来源 |
| `apps/windows/` | 后续 Windows 开发说明 | 当前没有已实现的 Windows 客户端 |

**共享源文件有两种来源：Core 包，以及 Xcode 显式引用的 Mac 文件。** 后者的列表在 [generate-ios-project.py](../scripts/generate-ios-project.py) 和 [project.pbxproj](../apps/ios/FocusCount.xcodeproj/project.pbxproj)。不能根据文件目录推断平台边界。

两端首页、动画、模式菜单、声音库和 Store 有独立实现。同名类型不代表共用实现。新业务规则尽量共用；交互和布局分别适配。

## 3. 本机数据与交换文件

### 存储位置

- Mac：`~/Library/Application Support/FocusCount/`，主要包括 `sessions.json`、`settings.plist`、`sessions.csv`、`backups/` 和 `sounds/`。实际入口是 Mac `Models.swift` 的 `Storage.directory`。`legacyDirectory` 的命名不代表这个路径已经废弃。
- iPhone：应用沙盒中的 `app-state.json`，具体目录创建见 `PhoneStore.init`；音频由 `PhoneSounds` 管理。
- Mac 所有应用设置保存在目录内的 `settings.plist`；iPhone 设置继续使用 UserDefaults。交换时由 `SharedPreferences` 经统一 `PreferenceStorage` 接口捕获并应用。
- Mac 启动不再调用旧项目数据自动迁移；旧数据需手动导入，不能因目录清空而重新灌入旧记录。

不要把 iPhone 的 `PhoneState` 本机文件直接当作跨平台 `Database` 交换文件。数据备份应通过各端的导出入口生成。

### 写入约定

记录操作应通过 Store，不能让视图绕过 Store 直接写 JSON。两端均有原子写入路径，但不能概括为所有状态修改都具备完整事务回滚：例如 Mac 部分计时操作先修改内存再调用 `persist()`。修改写入流程时，应检查失败后的内存状态、用户错误提示与磁盘内容是否一致。

导入先解码和校验，再合并、提交。不要为了兼容损坏文件而静默删除其中无法识别的数据。测试使用临时目录，禁止用真实记录覆盖测试夹具。

## 4. 同步协议与不可破坏的规则

当前“同步”是手动导出 / 导入 JSON，没有服务器或自动云同步。交换容器当前为版本 5；旧版本兼容范围由 `RecordExchange.decode` 决定。

| 数据 | 当前策略 |
|---|---|
| 专注记录、时间标记 | 按稳定 ID 合并，以修改时间判断新版本，处理同时间冲突；保留历史快照 |
| 最近删除 | 删除状态参与合并 |
| 永久删除 | 保留删除 ID，防止旧文件重新导入后复活 |
| 目标日期 | 通过 `GoalSnapshot` 同步，删除也有时间戳 |
| 标记颜色、emoji、活动颜色、分类及归属 | `SharedSettings` 按键合并 |
| 目标隐藏状态、倒数显示格式 | 作为共享偏好同步 |
| 模式参数 | 设置中的独立开关，默认关闭并持久保存；只同步五个数值：随机提醒最小/最大分钟、微休息秒数、每轮专注分钟、长休息分钟 |
| 提示音 | 设置中的独立开关，默认关闭并持久保存；按 ID 合并自定义音频与名称，并采用文件中的声音选择和音量 |
| 默认模式选择 | 不随共享参数同步 |
| 当前计时 | 用户主动勾选后接入；普通记录导入默认不替换当前计时 |

### 合并与设置

- 保留原记录 ID。导入时重新生成 ID 会造成重复，导入替换数据库会丢失本机数据。
- 永久删除必须保留防复活信息；不能只从数组移除，也不能随意清理删除 ID。
- `SharedSettings` 每个键有独立修改时间，空值可以表达删除。新增偏好需要更新捕获、校验和应用三个环节。
- `SharedPreferences.capture` 使用规范化内容，避免仅因 JSON 键顺序改变而生成新版本。不要替换为每次导出都写当前时间。
- 旧文件缺少某项可选设置时，保留本地值，不能当作用户清空。
- `ModeParameters` 把旧模式载荷归一化为五个数值，再应用到接收端本地设置。声音 ID 和音量通过独立 `soundPreferences` 传递，只有声音同步开关开启时才应用。
- 声音导入使用 `stageSounds` 和 `SoundFileTransaction`，验证音频后批量写入，记录提交失败时回滚。声音引用必须对应内置音或可用附件；无效引用应提示用户关闭声音同步或重新导出。声音设置采用所选文件值，数值参数仍按键的修改时间合并。
- 修改可选字段也要验证旧客户端行为。当前参数格式虽然仍使用版本 5，但较旧应用可能无法接受，用户应更新两端。

### 当前计时接续

`TimerTransfer` 保存计时状态及捕获时间，接收端计算传输期间的时间。微休息模式还通过公共状态转换接续阶段，只累加有效专注时间。导入声音选项关闭时保留本机声音，开启时采用文件声音设置。关闭数值参数同步不会改动本机下轮参数；主动接续计时时，本轮仍使用传入阶段的节奏。

计时接续不是分布式控制：导入不会远程停止另一台设备。不要承诺两端自动互斥。已经保存或永久删除的计时 ID 不能重新作为活动计时接入。

目标隐藏是界面隐私控制，不是文件加密；导出的目标内容仍存在。新增导出选项时，要明确显示状态和数据包含范围的区别。

## 5. 计时、休眠与后台差异

| 场景 | Mac | iPhone |
|---|---|---|
| 普通计时 | `TimerState` / `StudyClock` 计算经过时间，不能依赖回调次数 | `MobileClock` 使用可持久化的日期基准 |
| 微休息 | `FocusRoutine.advance` 推进状态，返回有效专注秒数 | `PhoneRoutine` 预先生成整轮计划，恢复时沿原计划计算 |
| 实际休眠 / 后台 | Mac 实际休眠时暂停微休息模式；普通计时继续累计 | 切后台或锁屏后继续按计划计时，并用本地通知提醒 |
| 应用恢复 | Mac 重启后草稿/模式暂停，避免盲目继续 | iPhone 通过 `checkpoint`、`becameActive`、`settled` 接续 |
| 长休息结束 | 等待手动开始下一轮 | 同样等待手动开始 |

UI 的定时刷新负责刷新显示，不是时间真值。不要用“每次 tick 加一秒”替代经过时间计算。修改阶段转换必须覆盖暂停、跨阶段恢复、跳过休息、结束、取消和计时导入。

手机随机计划不能每次刷新或恢复重新生成。跨设备传输的是公共当前阶段状态，不保证传输后每一次未来随机提醒都与原设备完全相同。

## 6. 手机通知和声音

`PhoneNotifications` 负责权限、排程、取消和前后台协调。应用只删除自己的 `focus-mode` 通知，不能清空所有本地通知。

手机模式参数受通知排程数量约束，相关判断在 `PhoneRoutine.supports`。导入更密集计划时，代码限制本次提交的提醒数量并提示用户；不要假设任意长计划都已完整投递。后台通知受系统权限、静音和系统专注模式影响，编译通过不能证明通知声音可听见。

- 前台由计时逻辑播放提示音；通知代理避免再播一遍。
- `generation` 防止旧异步排程覆盖新状态，后台任务保护排程提交；修改时保留对应竞争控制。
- 自定义声音存入本机声音库，可选随 JSON 交换；通知声音转换到 `Library/Sounds`，长度限制逻辑在 `notificationSound`。
- iPhone 设置页的声音 Picker 和试听 Button 必须是独立 Form 行，试听用独立按钮样式。之前把两者放在同一个可点击选择行，会导致试听变成切换声音。
- 新增预置音要检查两端命名和资源构建，同步选项关闭时不得导入附件或修改本地声音选择。

## 7. 常见扩展任务

### 增加模式

1. 扩展 Core 的 `FocusMode`、参数与状态机，明确暂停、结束和休息计入时长的规则。
2. 更新两端模式 `symbol/title`、选择菜单和横向参数菜单。
3. 接入 Mac `StudyStore` 与 iPhone `PhoneRoutine` / `PhoneStore`，明确后台计划如何表达。
4. 检查 `isValid`、Codable、旧文件默认值、共享参数范围与计时传输。
5. 添加纯状态机测试、两端 Store 测试，再做真实后台和声音检查。

不要只加一个菜单选项，随后复用不符合新模式的微休息状态。

### 新增可同步设置或模型字段

先决定它属于业务数据、可同步偏好还是本机设置。业务数据增加字段时定义旧文件缺省行为；偏好增加键时更新 `current`、`validate`、`apply` 和删除语义。为双向合并、重复导入、缺失字段和同时间冲突添加测试。

如果设置引用本地文件，先解决跨设备引用含义；不能直接同步一个只在源设备有效的文件路径或声音 UUID。

### 修改图表和首页

按 `code-map.md` 找图表的数据计算与渲染层。聚合、日期归属与平均频率属于数据层；缩放、碰撞避让、配色与点击弹层属于展示层。

- 标记是单次事件，专注记录是带时长的活动，两类统计不能混用。
- 图表时区、日界线和“本周”起点应继续使用已有 Calendar 规则；覆盖夏令时和跨午夜。
- 今日统计当前按记录开始日期归属，仅统计已保存记录。若要按跨日实际时长拆分，必须同时修改统计和测试，不能仅改标题。
- Mac 图表窗口拖动和图表选区手势有冲突风险。`MarkerWindowController` 关闭背景拖窗，调整窗口外观时不要破坏选区左右手柄。
- iPhone 优先验证小屏宽度、横竖屏和滚动；不能直接缩放 Mac 界面代替适配。

### 新增源文件

Mac / Core 的 Swift Package 一般自动发现目标目录中的文件。iPhone Xcode 工程使用显式文件引用，新增 Phone 文件或共用 Mac 文件后，要加入对应 Sources，并同步工程生成脚本中的共享清单。

**不要盲目运行 `generate-ios-project.py`。** 它会重写工程和 scheme，可能覆盖个人签名设置。优先精确修改引用；确需重新生成时，先保留工作区改动并逐项审查差异。不能提交他人的 Team、证书或用户工作区配置。

## 8. 验证命令与边界

以下命令从仓库根目录执行，需要完整 Xcode。可在当前 shell 设置：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

公共逻辑和 Mac 测试：

```sh
swift test --package-path packages/FocusCountCore
swift test --package-path apps/macos
```

iPhone 模拟器构建：

```sh
bash scripts/build-ios.sh
xcrun simctl list devices available
```

选取当前实际可用的模拟器 UUID，再运行测试；不要直接照抄占位符：

```sh
xcodebuild \
  -project apps/ios/FocusCount.xcodeproj \
  -scheme FocusCount \
  -destination 'platform=iOS Simulator,id=<实际模拟器UUID>' \
  -derivedDataPath dist/ios/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
```

验证真机 SDK 编译，可使用：

```sh
xcodebuild \
  -project apps/ios/FocusCount.xcodeproj \
  -scheme FocusCount \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -derivedDataPath dist/ios/DeviceDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

未签名真机构建不能直接安装到手机。个人安装需在 Xcode 中配置自己的 Team、连接设备并完成签名。不要同时向同一个 DerivedData 路径运行多个 xcodebuild，以免构建数据库锁冲突。

测试入口与定位见 [code-map.md 的测试章节](code-map.md)。按改动选择验证：公共模型与同步改动应跑 Core 和两端相关测试；纯文档调整检查链接和代码名称即可。

`PhoneLayoutTests` 使用合成数据渲染并附加截图，适合检查布局，不等于自动验证真实触摸或后台通知。以下场景仍需手工检查：

- 试听按钮能播放，且不改变选择；导入音频和重命名正常。
- 锁屏/后台提醒、拒绝通知权限、静音/系统专注模式、回到前台不重复播放。
- 小屏文字不截断、参数页可以滚动、横屏图表可读。
- Mac 窗口拖动、全屏、图表选择区手柄、睡眠后计时。
- 双向导入、重复导入、永久删除不复活、emoji/分类/颜色同步、声音/数值参数开关关闭时本机对应设置不被覆盖。

## 9. 打包、版本与提交

Mac 分发构建：

```sh
bash scripts/build-app.sh
```

脚本生成 `.app` 和压缩包；归档规则在 [package-macos.py](../scripts/package-macos.py)，旧包进入 `dist/macos/history/`。当前构建采用本机构建架构和临时签名，不应称为通用架构或已公证发行版。

版本号位置：Mac 在 `scripts/build-app.sh`；iPhone 在 Xcode 工程，并与 `scripts/generate-ios-project.py` 的生成默认值保持一致。发布时更新相应 README，核对实际产物版本，而不是只改文档。

### Git 管理规则

远程仓库为 `git@github.com:foryyz/Focus-Count.git`，名称 `origin`。`main` 是稳定分支；新功能从已更新的稳定版本创建 `codex/<功能名>` 分支。按功能拆分提交，说明实际行为，关联验证结果；不要把源码管理与应用内“历史版本”混为一谈，Git 不保存用户专注数据。

1. 开始前执行 `git status --short`、`git diff`、`git fetch origin`，核对本地和远程；已有用户改动保持原样，禁止为清空工作区而覆盖它们。
2. 完成功能后同步更新 README 当前说明、`docs/changelog.md`；新入口更新 `code-map.md`，协议或开发流程变化更新本文及 `data-format.md`。
3. 按变更范围运行测试；公共同步逻辑需验证 Core 和两端。纯文档修改核对链接和命令。不能把模拟器测试写成真机验证。
4. 使用明确路径或 `git add -p` 暂存，检查 `git diff --cached` 和 `git diff --cached --check`。不使用无差别暂存；不提交个人数据、导出文件、自定义声音、签名材料、`xcuserdata`、缓存和 `dist/`。
5. 共享 `.pbxproj` 必须跟踪，包括版本号、源码引用及构建设置；本机 Apple Team、个人签名及无关 Xcode 改写不混入功能提交。工程文件存在本机改动时，仅暂存所需部分，不能重生成工程覆盖签名配置。
6. 提交后查看 `git log --oneline` 和 `git status --short`。若保留了本机改动，在交接中逐项说明，不能宣称工作区完全干净。

### 发布与版本标签

Mac 和 iPhone 独立递增版本与构建号。此次整理以 `macos/v1.19.7` 和 `ios/v1.5.6` 标记当前源码基线；此前未及时提交的小版本只补写变更记录，不伪造历史提交或标签。

发布前完成测试与构建，核对实际 Info.plist；Mac 用上面的构建脚本归档旧 ZIP，新版本保留在 `dist/macos/` 根目录。版本标签须为附注标签，指向包含实现、版本配置及说明文档的稳定提交；已发布标签不得删除重建或强制移动。仅有文档更新时不必递增应用版本或另造应用版本标签。

下列命令中的标签仅为当前版本示例，未来替换为待发布版本；已存在的标签不重复创建：

```sh
git diff --check
git log -5 --oneline
git tag -a macos/v1.19.7 -m "FocusCount macOS 1.19.7 (53)"
git tag -a ios/v1.5.6 -m "FocusCount iPhone 1.5.6 (13)"
# 已获用户推送授权后，先核对远程，再推送稳定分支与本次标签。
git fetch origin
git log --oneline HEAD..origin/main
git push origin main
git push origin macos/v1.19.7 ios/v1.5.6
```

远程有新提交时，先审查并整合，不强制推送；推送失败不等于提交丢失，交接中说明本地提交与远程状态。不要使用 `git push --tags` 意外发布无关标签。本项目 `dist/` 不进仓库，推送源码与标签不会上传安装包，也不等于创建了 GitHub Release。

### 查看与回退

```sh
git log --oneline --decorate -15
git show macos/v1.19.7 --stat
git diff macos/v1.19.7..HEAD -- apps/macos packages/FocusCountCore
```

查看旧代码可在独立检出目录打开对应标签，保留当前未提交工作。已共享提交需要撤销时使用 `git revert <提交号>` 产生新提交，不以 `reset --hard` 或强制推送改写公共历史。应用回退前另行备份数据并检查数据格式兼容性；源码标签或旧 ZIP 不包含用户数据，也不能让旧应用自动兼容新协议。

### 目标倒计时清空修复（Mac 1.19.8）

正式应用向 `TargetCountdownStore` 注入数据库 writer，初始化只接收数据库 `goal`（包括空值和删除标记），并移除 `focus-target-date-v1` 旧镜像。保存、隐藏目标时不再写回镜像；不得在数据库目标为空时自动恢复旧副本，因为用户可能主动清空了主数据。未注入 writer 的独立测试模式仍支持偏好存储，不用于正式应用。共享源码已修复，iPhone 下次构建也会使用此逻辑，本次仅发布 Mac。

Mac 正式包的偏好文件为 `~/Library/Preferences/local.focuscount.app.plist`；`focus-target-date-v1` 是其中的键，不是单独文件。目标隐藏和显示格式仍由 UserDefaults 管理。系统会缓存偏好，不宜直接编辑整个 plist；删除整个文件还会影响其他设置。旧版已恢复并写回主数据库的目标不会在升级时被自动删除，应在目标设置中删除。

回归测试为 `TargetCountdownTests.testMissingDatabaseGoalDoesNotRestoreLegacyDefaults` 和 `testDatabaseGoalNeverCreatesMirrorOrReturnsAfterDataRemoval`，覆盖旧镜像、空目标、保存/隐藏不再生成副本及删除标记。

## 10. 维护这两份文档

新增功能时，在 `code-map.md` 增加入口文件、核心类型/函数、调用关系及平台差异；修改持久化、同步、后台或开发流程时，更新本文对应章节。

以类型和函数名作为定位锚点，避免维护易失效的固定行号。重大重构后核对文档链接与函数存在性；共享文件移动后，同时检查 Xcode 引用和生成脚本。交接应说明验证范围与遗留问题，而不是仅列改动文件。


### 历史删除与导出时间（1.19.3 / 1.5.3）

两端 Store 的 `deleteArchive(_:)` 通过 `ImportArchive.delete(directory:phone:)` 删除指定本机备份。iPhone 完整备份的旧本机状态副本同时移除，避免列表回退显示隐藏副本；不删除当前数据库或相邻备份。

`deleteVersion(_:)` 调用 `RecordExchange.deletingVersion(_:from:)`，只删除指定旧快照。`StudySession.purgedHistoryIDs` 保存已删除快照的 SHA-256 ID，`retainingVersions` 合并删除标记并过滤旧版本；`decode` 也校验和过滤。不要为清理历史更新时间戳或删除当前记录，也不要在后续编辑/恢复时丢掉这些删除标记。双端更新后可防止旧导入文件复活已删除历史。

`ExchangeSource.exportedAt` 在导出时写入，沿用数字日期编码保持兼容；新增 `exportedAtISO8601` 提供人可读时间。后者是展示副本，读取以 `exportedAt` 为准。预览不使用文件修改时间或旧计时快照时间冒充导出时间，旧文件缺少字段时显示未知。文件名和其他内容修改不会改变内嵌时间；这不是数字签名，时间字段本身仍可被手工修改。


### 删除全部历史版本（Mac 1.19.4 / iPhone 1.5.4）

两端历史页面新增“删除全部历史版本”，确认时列出导入备份和记录旧版本数量。两端 Store 的 `deleteAllHistory()` 先原子保存所有记录的旧版本删除标记（Core `RecordExchange.deletingAllVersions(from:)`），再删除本机导入备份；保留当前记录、最近删除记录、时间标记及计时。数据库保存失败时不删除备份；文件清理失败会显示错误并刷新剩余备份，允许重试。不会为本次清理再生成一份历史备份。记录旧版本的删除标记参与后续同步，其他设备的本机备份需在对应设备清理。


### 本机同步偏好（Mac 1.19.5 / iPhone 1.5.5）

“同步自定义提示音与声音设置”和“同步模式数值参数”移至设置中的“同步设置”，默认关闭，按设备持久记忆。导入预览不再显示这两个开关，每次直接使用本机选择；计时状态仍在预览中临时选择，默认关闭。

共享常量 `SyncPreferences.soundsKey/parametersKey` 位于 Core `SharedPreferences.swift`；Mac 设置页和交换页通过 `@DirectoryPreference`、iPhone 通过 `@AppStorage` 使用同一组本机键。导入时仍向 Store 显式传入两个选择，预览变化也按相同选择计算。这两个偏好不进入 `SharedPreferences` 交换内容，导入其他设备的数据不会重置它们。导出内容不受本机导入偏好影响。此规则替代上一版“每次导入默认开启”的交互。


### 聚合标记数量（Mac 1.19.6 / iPhone 1.5.6）

两端频率总览的聚合次数达到 4 次即显示下方小数字，不再仅在尺寸封顶时显示。Mac 时间分布也采用相同的 `MarkerCountBadge`（`MarkerFrequencyOverview.swift`，9pt 数字、浅色胶囊背景），布局为数字预留避让空间。无 emoji 的彩色点同样标注。Mac 时间分布的 2 次聚合直径由 44 降至 34，3 次仍约 48，其余放大规则保留。频率总览的窄日期列按数字宽度保留最小间距，必要时横向滚动。

### Mac 占比图标签（1.19.7）

内部标签按实际尺寸判断，不按固定占比阈值。名称最多两行，字号下限 10pt；放不下才使用外侧引线。数字测量须使用等宽数字字体，避免百分比被截断。扇形和圆环使用同一套检测，圆环额外排除中心区域。外侧文字与引线同色，保持活动色相并按背景调整到至少 4.5:1 的对比度。改动后运行 Mac `ShareLabelTests`，检查 400/560pt 图表及浅深色预览；共享文件中的 Mac 实现以条件编译隔离，同时验证 iOS 编译。

### 目录内设置（Mac 1.20.0）

`PreferenceStorage` 定义读写接口，`UserDefaults` 实现用于 iPhone 与隔离测试；Mac 默认由 `ApplicationPreferences.current` 指向 `FilePreferences.shared`。文件是 `settings.plist`，外层 `version = 1`、`values` 保存键值。Data（例如模式配置及同步修订账本）由 plist 原生编码，写入使用原子替换。缺失返回空设置，坏文件拒绝覆盖并提示；写入失败不更新缓存。

Mac 的模式、标记颜色/emoji、活动分类/颜色、目标显示、同步开关与分析窗口尺寸都使用此接口。新增 Mac 偏好必须接入该文件，不再用 `UserDefaults.standard` 或 `@AppStorage`。SwiftUI Bool 开关使用 `DirectoryPreference`。两个分析窗口不再调用 NSWindow 的偏好自动保存，而是把 frameDescriptor 写入设置文件。操作系统自身的偏好和窗口恢复元数据不属于业务数据。

App 初始化调用 `FilePreferences.discardLegacyDefaults` 清理明确列出的旧应用键，不迁移旧值、不删除整个系统偏好域。已有主数据、目标和声音文件保留；首次没有设置文件时模式参数等恢复默认。关闭应用后删除目录才能彻底重置；运行中删除不保证清除内存内容。不能在设置缺失时从计时快照反向补写模式偏好。

测试入口：Core `PreferenceStorageTests`（持久化/同步/坏文件/失败写入/旧键清理）；Mac `DirectorySettingsTests`（重启保留、删目录恢复默认、坏设置阻止数据写入）。
