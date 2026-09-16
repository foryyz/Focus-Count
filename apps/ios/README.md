# FocusCount for iPhone

原生 SwiftUI 应用，面向 iOS 17 及以上。使用系统 Swift Charts，无第三方依赖，无账号、广告或联网服务。手机端与 macOS 共用 `packages/FocusCountCore` 的模型、校验与 JSON 协议。

## 已实现

- 简约计时：轻点开始、暂停、继续，结束后填写科目与 S–D 专注度。
- 锁屏、切后台后继续计时，回到前台重算；关闭进程后重新打开也保留运行状态。
- 历史记录筛选（日期、科目、专注度）、编辑、补记、左滑删除、最近删除恢复。
- 每日时长图和科目分布，可点击筛选；按开始日期归属，跨午夜整段归入开始日。
- JSON 导入预览、按 ID 合并、导出到“文件”及兼容分享位置。
- 本地原子保存，写入失败不更改内存状态；读取失败保护原数据并停止写入。
- 原生深色模式与可滚动小屏/横屏布局。

## 在 Xcode 中运行

1. 打开 `apps/ios/FocusCount.xcodeproj`，选择共享 Scheme `FocusCount`。
2. 确保 Xcode 已安装 iOS 平台组件（Settings → Components）。选择一个 iPhone 模拟器。
3. 按 Command-R 构建运行。无需配置签名即可在模拟器运行。

从项目根目录构建模拟器版本：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-ios.sh
```

产物为 `dist/ios/DerivedData/Build/Products/Debug-iphonesimulator/FocusCount.app`。这是模拟器应用，不能直接安装到真机。

真机运行：连接 iPhone，在 Xcode 的 Signing & Capabilities 中选择自己的 Team，并根据提示使用唯一 Bundle Identifier，然后选择连接的 iPhone 运行。设备可能需要开启 Developer Mode。项目不包含开发者证书或预设 Team；本次没有进行 App Store / TestFlight 发布。

## 测试

共享核心测试（无需 iPhone 模拟器）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/FocusCountCore
```

手机端存储测试：在 Xcode 选择 iPhone 模拟器后按 Command-U，或：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apps/ios/FocusCount.xcodeproj -scheme FocusCount \
  -destination 'platform=iOS Simulator,id=<设备 UUID>' \
  -derivedDataPath dist/ios/DerivedData CODE_SIGNING_ALLOWED=NO test
```

## 存储与计时行为

手机端本地文件位于应用沙盒 `Library/Application Support/FocusCount/app-state.json`。这是手机的内部状态文件，包含记录以及运行中的手机计时状态，不能直接放到电脑 `data/sessions.json`。应用的导出功能会生成兼容的共享 v5 JSON。

手机计时把运行时间基准持久化，不依赖持续后台执行。锁屏或退出进程不会自动暂停，休息时请主动点暂停。手动更改系统时间可能影响运行时长；暂停后的累计时间不会随时钟变化。此版本没有锁屏实时活动、后台音频或结束提醒。

## 与电脑交换记录

Mac 与 iPhone 都打开首页右上角“数据管理”，选择“导出 JSON”或“导入 JSON / 导入并合并”。iPhone 可导出至“我的 iPhone → FocusCount → Exports”，不需要 iCloud。选择文件后先看预览，再确认自动合并。

相同 ID 自动去重，以修改时间较新者作为当前记录；同时间按固定规则选定，两端结果一致。不同内容全部保存在 history 中，随 JSON 往返导出，在两端的“历史版本”中可查看与恢复，不重复计入学习时长。删除标记也参与合并，不会因旧文件导入而直接复活。

导入前会备份双方数据，当前运行草稿不会被外部草稿替换。iPhone 备份在沙盒 Application Support/FocusCount 的 `before-import-<UUID>.json` 和 `incoming-<UUID>.json`，可以通过 Xcode 下载应用容器取得。备份不自动清理。

两端都需要更新到支持共享 v5 的版本。iPhone 内部状态版本升级为 5，升级前保留 app-state.v<旧版本>.backup.json。当前没有自动云同步，不要用文件直接覆盖代替应用内合并；详见 `docs/data-format.md`。

## 项目维护

新增/移除 Swift 源文件后，可从项目根目录运行 `python3 scripts/generate-ios-project.py` 重新生成 Xcode 项目。生成器包含应用和存储测试 target；自定义签名设置前请注意重新生成会覆盖项目设置。

应用图标使用 `assets/app-icon.jpg` 中保存的原始图片，仅做尺寸与格式转换。重新生成 iPhone PNG 和 Mac ICNS：

```sh
bash scripts/generate-icons.sh
```

### 导入反馈

选中文件后显示读取进度，读取完成后自动回到页面顶部的“请确认导入 · 尚未写入”。点击“确认合并到 iPhone”才保存；完成后弹窗列出新增、更新、彻底删除和当前记录数量。文件读取通过 NSFileCoordinator 协调文档提供方访问，失败信息显示在顶部。

共享 v5 的时间标记在手机端保留并随 JSON 合并、导出，目前仅 Mac 提供标记创建与管理。
