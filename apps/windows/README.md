# Windows 11 客户端（待开发）

此目录预留给 Windows 客户端源码，目前无可运行实现。

实现时遵守 `../../docs/data-format.md`：从可执行文件所在位置向上查找 `.focuscount-root`，使用根目录 `data/`，构建产物放入 `dist/windows/`。找不到根目录应提示错误，不静默改用当前工作目录或用户目录。

计时使用 Windows/.NET 的单调时钟；保存已累计的有效秒数，恢复为暂停状态。JSON 时间戳须按现有 v5 协议转换，不能直接按 Unix 毫秒读取。先确保与 macOS 的数据读写互操作，再扩展界面功能。
