# 共享数据协议 v5

Mac 与 iPhone 使用同一套 `FocusCountCore.RecordExchange` 合并逻辑。Windows 后续实现也必须遵循本文。导入兼容 v1、v2、v3、v4、v5，导出统一为 v5；未知版本拒绝写入。两端都应更新后再交换文件，旧客户端不能读写 v5。

## 文件结构

UTF-8 JSON 顶层包含 `version`（5）、`sessions`（记录数组）、`draft`（计时草稿）、可省略的 `pendingEnd`（待保存的结束时间）。Mac 主文件为 `~/Library/Application Support/FocusCount/sessions.json`；iPhone 从内部沙盒状态导出此格式。

每条记录：

| 字段 | 类型 / 含义 |
| --- | --- |
| id | UUID，标识一次学习，编辑时保持不变 |
| startedAt / endedAt | 开始和结束时间 |
| activeSeconds | 有效秒数，有限非负值，不超过起止区间（容差 0.001 秒） |
| subject | 非空科目 |
| focus | S、A、B、C、D |
| updatedAt | 最后修改时间；旧数据缺失时用 endedAt |
| deletedAt | 可省略，存在表示已删除；恢复删除时移除 |
| history | 可省略，所有不同的历史版本快照，不计入学习统计 |

历史快照使用 `sessionID` 对应所属记录，其余字段为 startedAt、endedAt、activeSeconds、subject、focus、updatedAt、deletedAt，不递归包含 history。导入时校验快照字段与所属 ID；无效数据或重复记录 ID 拒绝整份导入。

所有 JSON 日期仍采用从 **2001-01-01T00:00:00Z 起的秒数**，允许小数。Unix 秒数 = JSON 秒数 + 978307200。CSV 使用 ISO 8601 UTC。

## 彻底删除
顶层可选字段 `purgedIDs` 是 UUID 数组（集合）。彻底删除只允许对最近删除中的记录执行，移除整条记录及全部 history，永久保留该 ID 作为防复活标记，不保存科目或时长。
合并时先取双方 purgedIDs 的并集，再排除这些 ID 的所有记录，优先于任何修改时间或恢复操作。导出携带标记；旧 v1/v2/v3 文件仍可导入，但无法使记录复活。两端必须更新后使用。
清空全部作用于所有最近删除记录，不受筛选条件影响；需要界面确认。已有独立备份和外部导出文件不会被追溯擦除。

## 自动合并规则

1. 按 ID 合并集合。不同 ID 都保留，不凭科目或日期猜测去重，避免误删两次真实学习。
2. 相同 ID 按 `max(updatedAt ?? endedAt, deletedAt ?? 负无穷)` 比较，较新的版本作为当前记录。
3. 时间完全相同时，使用快照的 SHA-256 标识字典序选取较大者，保证两个方向结果一致。标识由 Swift JSONEncoder 的 sortedKeys 输出计算；未来 Windows 实现须匹配该规范或采用明确的协议升级。
4. 所有其他当前版本、双方已有 history 合并成去重集合，移除与新当前版本完全相同的快照，按标识排序保存。
5. 历史版本不会作为新 session 加入，统计与 CSV 只计算当前且未删除的记录。同文件反复导入不会重复计时，也不会不断复制相同历史版本。
6. 两端正常编辑、删除、恢复都会归档上一个版本。“恢复此版本”是一次新修改，恢复全部字段及删除状态，并保留恢复前的版本。新的修改时间至少晚于当前版本 0.001 秒。

这是保留所有不同版本的自动选择策略，并不猜测不同设备修改哪个字段更符合用户意图。冲突版本可以在两端的数据管理 → 历史版本中查看、恢复。没有共同编辑祖先的旧文件也不会直接丢弃其中一个版本。

## 导入、导出与备份

两端均由用户选择 JSON 文件、查看预览并确认，然后自动合并；不是云服务或后台目录监听。

- 导入前先验证，再分别备份本地完整状态和导入文件。任何备份失败都不开始合并。
- Mac 备份在 `~/Library/Application Support/FocusCount/backups/<UUID>/before-import.json` 与 `incoming.json`，界面可打开目录。
- iPhone 在沙盒 Application Support/FocusCount 内保留 `before-import-<UUID>.json`（完整内部状态）和 `incoming-<UUID>.json`（导入 JSON），可通过 Xcode 下载容器取得。
- 主文件原子写入，保存失败保留原内存状态。Mac CSV 在 JSON 成功保存后重新生成。
- 默认只合并记录。明确选择同步计时后，用 `timerTransfer` 替换本机计时；先备份，保存失败回滚。缺少该字段的旧文件不能接续计时。
- 导出包含所有记录、删除标记、历史版本，以及兼容旧版的 `draft` 暂停快照和新版的 `timerTransfer` 完整状态；导出不暂停本机运行。
- 备份与历史版本不自动清理。请定期导出到独立位置防止设备损坏或文件被外部删除。

不要用同步工具直接覆盖正在运行客户端的主文件。直接覆盖文件不等于调用合并功能，多进程同时写同一主文件也不在本协议支持范围内。

## 迁移

Mac 兼容主文件 v1/v2/v3/v4/v5。升级前保留 sessions.v<旧版本>.backup.json，随后写入 v5。
iPhone 内部 app-state.json 升级为 5，兼容旧内部版本 1/2/3/4，升级前保留 app-state.v<旧版本>.backup.json。旧客户端拒绝新版本，避免丢失彻底删除标记。

## 计时和统计

Mac 使用包含休眠时间的连续单调时钟，熄屏和休眠继续累计；iPhone 使用持久化日期基准，锁屏和重启应用后继续，手动修改系统时间可能影响正在运行的时长。

日期筛选按本地时区，包含首尾两天，跨午夜全部归入开始日。修改起止时间不自动改变有效时长。CSV 字段保持 `id,started_at,ended_at,active_seconds,subject,focus`，UTF-8 BOM、CRLF 换行、三位小数，文本转义和公式防护保持原规则。CSV 不包含历史版本，不能代替 JSON 备份。

## Mac 独立应用存储

默认数据目录与应用路径无关。旧项目数据仅在首次从项目启动时自动发现，验证并备份双方后合并到 Application Support。迁移标记为 project-storage-migration.json；原项目数据保留。先移动应用的用户可在数据管理中手动导入旧 sessions.json。

## 时间标记（v5）

顶层可选 events 数组，每项包含 id、kind、occurredAt、updatedAt、可选 deletedAt。SEX 的 kind 为 SEX；无起止区间、activeSeconds 或 focus。事件不进入 sessions，因此不计入专注统计或 CSV。

事件按 ID 合并，采用较新修改时间；同时间按 sortedKeys JSON 字节序确定结果。purgedIDs 同时作用于事件，彻底删除优先。普通删除和恢复仅改变删除状态，不改标记时间。v1–v4 数据按无事件导入，未知新版本拒绝，防止旧客户端丢弃 events。iPhone 内部状态升级到 5，旧文件先备份；标记可在手机无损往返交换。

## 可选计时接续扩展（Mac 1.11.0 / iPhone 1.2.0）

仍使用 v5，通过可选字段向后兼容；旧客户端忽略此扩展，重新导出会丢失接续信息。两端都需升级。

`timerTransfer` 包含 `timerID`（同一次专注的 UUID）、`capturedAt`（导出时间）、`startedAt`、`accumulated`（导出时有效秒数）、`isRunning`、`pendingEnd` 和 `activity`。日期编码沿用本协议。有限非负秒数、状态互斥、起止顺序和时长上限均在导入时验证，无效快照拒绝整份文件。

运行时：接收累计秒数 = accumulated + max(0, 接收时间 − capturedAt)，再从接收时刻继续计时。Mac 使用新的本机单调时钟锚点；iPhone 使用新的日期锚点。暂停和待保存不增加传递期间时长。未开始快照会清空本机计时。重复接收同一运行快照从原始导出时间重建，不会相加或重复累计。

Mac 本地额外保存可选 `activity` 和 `timerID`；iPhone 内部状态保存同名字段。新开始生成 ID，接续沿用；完成保存使用这个 ID 作为 session ID，取消或保存后清除本机计时 ID。计时 ID 已存在于任一侧记录或 purgedIDs 中时，不允许再次导入其运行快照，只能关闭同步计时后合并记录。

同步计时每次必须明确选择，不依据文件新旧自动覆盖，也不合并两个独立计时。源设备不会收到远程暂停或结束指令；取消、暂停和未完成草稿并非实时同步。接收旧暂停快照会恢复该快照，用户需核对导出时间。Mac 本地重启恢复暂停的原策略不变。

## 可选目标日期（Mac 1.16.0 / iPhone 1.3.0）

v5 顶层新增可选 `goal`，没有字段表示不参与目标合并。字段包含 `name`、`emoji`、`date`、`includesTime`、`deleted`、`updatedAt` 与 `revision`（UUID）；日期编码规则与其他字段一致。日期和修改时间必须有限，未删除目标名非空且最长 500 字符，emoji 最长 16 字符。

应用只维护一个当前目标。按 `updatedAt` 选择较新目标；相同时间比较该结构经 JSONEncoder sortedKeys 编码后的字符串，取字典序较大者，保证双方一致。删除是带时间戳的 `deleted: true` 快照，必须保留并导出，不能简单去掉字段。导入备份包含双方目标，可从备份恢复；不同目标不会自动生成多目标列表。

目标与记录在同一次原子提交中合并。旧客户端可读取 v5 记录，但会忽略目标扩展，因此需使用支持此扩展的两端版本交换目标。`hidden` 不允许写入共享目标，属于设备本地偏好；未知设备首次收到目标默认隐藏。仅改变本机可见性不产生共享目标修订。界面隐藏不会移除导出文件中的目标内容。
