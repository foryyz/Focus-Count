# FocusCount

学习计时器。目前提供 macOS 原生 SwiftUI 客户端；目录已为后续 Windows 11 客户端与共享数据预留边界，Windows 客户端尚未实现。

## 项目结构

```text
FocusCount/
├── .focuscount-root          项目根目录标记，移动/同步项目时必须保留
├── apps/
│   ├── macos/                Swift Package、Sources、Tests
│   └── windows/              后续 Windows 开发说明
├── data/                     跨平台共享数据，个人记录不进入 Git
├── docs/data-format.md       两个平台共同遵守的数据协议
├── scripts/build-app.sh      macOS 构建与本地签名
└── dist/macos/FocusCount.app  构建产物，不进入 Git
```

后续 Windows 客户端放入 `apps/windows/`，构建产物放入 `dist/windows/`，读写相同的 `data/sessions.json`。

## macOS 构建与运行

要求 macOS 13+、Swift 5.9+。从项目根目录运行：

```sh
bash scripts/build-app.sh
open dist/macos/FocusCount.app
```

脚本生成本机架构的应用并进行 ad-hoc 签名，未进行 Apple 公证。也可开发运行：`swift run --package-path apps/macos`。

**应用须保留在项目目录内**，推荐使用 `dist/macos/FocusCount.app`。可给应用创建访达替身以便启动。单独将 `.app` 复制到“应用程序”目录后将无法定位项目数据；请移动整个项目文件夹。定位失败时应用会显示错误并停止写入，不会改用其他数据目录。

测试（需要完整 Xcode）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path apps/macos
```

修改源码后，先退出旧应用，再重新构建、启动。

本次目录调整保留了原应用于 `dist/legacy/FocusCount.app`（仅作备份，仍使用旧数据路径）；原 `dist/FocusCount.app` 入口已改为指向新版应用的符号链接。日常请使用 `dist/macos/FocusCount.app`。

## 使用

- 点击大号时间，或在空命令输入框中回车：开始、暂停、继续。
- 输入 `stop!` 回车，或点击“结束”：填写科目与专注度 S–D 后保存。
- “返回计时”保留进度并恢复为暂停状态。
- 暂停不累计时间，系统睡眠自动暂停，关闭窗口退出。
- 运行中约每 5 秒保存草稿，操作时立即保存，重启后恢复为暂停状态。
- 主界面默认隐藏历史列表与统计，点击“学习记录”打开独立管理页。
- 记录页支持日期、科目、专注度筛选；编辑、补记、删除和恢复。
- 每日时长与科目分布图可点击筛选，统计与列表实时更新。
- 编辑保留原记录 ID；起止时间与有效时长分别填写，暂停不计时。
- “最近删除”不计入统计，可随时恢复，不自动清空。
- 完成学习与编辑时可选择已有科目；支持深色模式。

## 数据迁移与同步

所有数据现在位于项目根目录 `data/`。首次启动时，若 `data/sessions.json` 不存在且旧目录 `~/Library/Application Support/FocusCount/` 有记录，会验证并复制旧 JSON；旧文件保留作为备份。已有新数据时不会覆盖或自动合并。

`sessions.json` 是主数据，`sessions.csv` 在启动和保存记录时自动重建，手工修改 CSV 不会导入应用。右上角文件夹按钮可打开数据目录。

将 `data/` 用同步工具同步至另一台电脑对应项目的 `data/`，即可为未来跨平台共享做准备。**切换设备前退出应用并等待同步完成，避免两端同时写入。** 当前没有云同步服务、跨设备锁或冲突合并。请保留备份。

数据协议见 [docs/data-format.md](docs/data-format.md)。当前写入版本为 v2，新增修改和删除时间；首次读取 v1 数据会保留 `sessions.v1.backup.json` 备份，旧应用不能继续读写新版数据。为兼容原记录，JSON 日期仍使用自 2001 年起的秒数；CSV 日期为 ISO 8601 UTC。

## 版本控制

Git 跟踪源码、脚本、文档和根目录标记；忽略个人学习数据、编译缓存和 `dist/` 产物。新克隆的项目需要重新构建应用，并单独同步或恢复 `data/` 下的数据。
