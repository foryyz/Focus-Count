# 共享数据协议 v4

Mac 与 iPhone 使用同一套 `FocusCountCore.RecordExchange` 合并逻辑。Windows 后续实现也必须遵循本文。导入兼容 v1、v2、v3、v4，导出统一为 v4；未知版本拒绝写入。两端都应更新后再交换文件，旧客户端不能读写 v4。

## 文件结构

UTF-8 JSON 顶层包含 `version`（4）、`sessions`（记录数组）、`draft`（计时草稿）、可省略的 `pendingEnd`（待保存的结束时间）。Mac 主文件为 `~/Library/Application Support/FocusCount/sessions.json`；iPhone 从内部沙盒状态导出此格式。

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
- 导入不会替换本机当前计时草稿。外部草稿随 incoming.json 备份保留，不能同时接管两个设备的运行计时。
- 导出包含所有当前记录、删除标记、历史版本，以及本机草稿的暂停快照；导出不暂停本机运行。
- 备份与历史版本不自动清理。请定期导出到独立位置防止设备损坏或文件被外部删除。

不要用同步工具直接覆盖正在运行客户端的主文件。直接覆盖文件不等于调用合并功能，多进程同时写同一主文件也不在本协议支持范围内。

## 迁移

Mac 兼容主文件 v1/v2/v3/v4。升级前保留 sessions.v<旧版本>.backup.json，随后写入 v4。
iPhone 内部 app-state.json 升级为 3，兼容旧内部版本 1/2，升级前保留 app-state.v<旧版本>.backup.json。旧客户端拒绝新版本，避免丢失彻底删除标记。

## 计时和统计

Mac 使用包含休眠时间的连续单调时钟，熄屏和休眠继续累计；iPhone 使用持久化日期基准，锁屏和重启应用后继续，手动修改系统时间可能影响正在运行的时长。

日期筛选按本地时区，包含首尾两天，跨午夜全部归入开始日。修改起止时间不自动改变有效时长。CSV 字段保持 `id,started_at,ended_at,active_seconds,subject,focus`，UTF-8 BOM、CRLF 换行、三位小数，文本转义和公式防护保持原规则。CSV 不包含历史版本，不能代替 JSON 备份。

## Mac 独立应用存储

默认数据目录与应用路径无关。旧项目数据仅在首次从项目启动时自动发现，验证并备份双方后合并到 Application Support。迁移标记为 project-storage-migration.json；原项目数据保留。先移动应用的用户可在数据管理中手动导入旧 sessions.json。
