# 共享数据协议 v1

macOS 与未来 Windows 客户端应读写项目根目录 `data/sessions.json`，UTF-8 JSON。根目录以 `.focuscount-root` 文件标识；部署时须保留此文件。数据不应放入平台源码或应用包中。

## 字段

顶层对象：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| version | 整数 | 当前为 1，未知版本应拒绝写入 |
| sessions | 数组 | 已完成记录，按保存顺序排列 |
| draft | 对象 | 未完成计时状态 |
| pendingEnd | 数字，可省略 | 已结束但尚未填写保存的时间 |

每条 session：`id` 为 UUID 字符串；`startedAt`、`endedAt` 为时间戳；`activeSeconds` 为非负秒数，可含小数；`subject` 为去除首尾空白的非空科目；`focus` 为 S、A、B、C、D 之一。

`draft` 包含可省略的 `startedAt` 和必需的 `accumulated`（有效秒数）。运行中的单调时钟值不保存；保存快照时累计已用时间，恢复时始终暂停。`pendingEnd` 存在表示需要继续完成记录表单。

为兼容已有数据，所有 JSON 时间戳采用 Swift Date 默认编码：**从 2001-01-01T00:00:00Z 起的秒数**，允许小数。转换为 Unix 秒数：`unixSeconds = jsonSeconds + 978307200`。Windows 不应把这些值当作 Unix 毫秒。

示例（无记录、无草稿）：

```json
{"version":1,"sessions":[],"draft":{"accumulated":0}}
```

## 写入与迁移

先完整解码并检查版本，再写入；损坏或未知版本的文件应提示错误并停止写入。主文件采用同目录临时文件加原子替换，失败时保留旧记录。CSV 写入失败不应撤销已成功保存的 JSON。

macOS 首次发现共享主文件不存在时，会验证并复制旧目录 `~/Library/Application Support/FocusCount/sessions.json`，不删除原文件。已有共享主文件时不合并、不覆盖。旧文件损坏时停止迁移并提示错误。

## CSV

字段为 `id,started_at,ended_at,active_seconds,subject,focus`；UTF-8 BOM、CRLF 换行、ISO 8601 UTC 日期、三位小数秒数。字段用双引号包围，内部双引号重复转义。以 `= + - @` 或制表符、回车、换行开头的文本加单引号，防止表格公式执行。JSON 保留原文。

## 同步约束

此协议目前是单写入者文件协议，不提供同步服务、锁或冲突合并。两端退出应用后同步，再切换设备使用。JSON 是主数据，CSV 可重建。未来 Windows 实现必须遵守这些约定；如需并发写入，应另行设计协议升级与迁移。
