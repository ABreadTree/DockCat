# Claude Code CLI Review: Agent Bridge Settings Design

Source spec: `docs/superpowers/specs/2026-07-04-agent-bridge-settings-design.md`

Reviewer: Claude Code CLI

## Summary

已阅读 `docs/superpowers/specs/2026-07-04-agent-bridge-settings-design.md`（Agent Bridge Settings Design）。该设计在 macOS Swift 应用（DockCat）中新增一个"Agents"设置面板，通过直接修改 Codex、Claude Code、Hermes、OpenClaw 的本地配置文件（TOML/JSON/YAML）来接入一个仅监听 `127.0.0.1` 的 HTTP 事件端点。整体思路（备份 + 打标记 + 可回滚）是合理的，但涉及"macOS Swift 应用直接改写第三方 CLI 工具的 dotfile 配置"这一高风险操作面，存在若干需要在实现前明确的关键风险点。

## Findings

### 严重 (Critical)

1. **未提及 App Sandbox / 文件系统权限模型**（§ Architecture / Security And Resource Constraints）
   规范假定 DockCat 可以直接读写 `~/.codex/config.toml`、`~/.claude/settings.json`、`~/.hermes/config.yaml`。如果 DockCat 走 Mac App Store 分发或启用了 App Sandbox，写入 `$HOME` 下任意路径需要额外的 entitlement（如 `com.apple.security.files.user-selected.read-write` 或安全作用域书签），普通沙盒应用无法直接遍历/写入这些路径。规范中完全未讨论这一点，是最容易在实现阶段"卡死"的问题。

2. **写入过程无原子性保证，存在配置损坏风险**（§ Config Ownership / Testing）
   规范描述了备份策略，但没有提到"临时文件写入 + rename 替换"的原子写模式。若写入过程中应用崩溃、被强制退出或磁盘满，可能导致用户的 `settings.json` / `config.toml` / `config.yaml` 被截断或损坏，且没有自动检测+回滚机制兜底（备份是"事前"的，不能替代"事中崩溃"保护）。

3. **未处理与目标 Agent 进程并发写入的竞态**（§ Agent Integration Manager / Security And Resource Constraints）
   Codex/Claude Code/Hermes 在运行时也可能读写自己的配置文件。规范只字未提"目标工具是否正在运行"的检测，也没有文件锁机制。如果用户在 Claude Code 会话运行中点击 Enable，DockCat 写入 `settings.json` 与工具自身的读取/写入可能产生竞态，导致配置丢失部分内容或行为不一致（这也是"Needs restart"状态存在的原因，但规范未说明如何在写入时避免竞态本身）。

### 高 (High)

4. **Codex `notify` 命令包裹存在 shell 转义/注入风险**（§ Codex → Enable behavior）
   "Replace `notify` with a DockCat wrapper command that invokes the previous notify command" —— 如果原 `notify` 命令包含特殊字符（引号、`$()`、管道符等），naive 字符串拼接包裹可能导致命令注入或调用失败。规范没有说明包裹时如何做安全的参数化调用（例如通过数组式 exec 而非 shell 字符串拼接）。

5. **备份文件可能包含密钥，且规范只承诺"日志不含密钥"**（§ Config Ownership → Backups）
   Claude Code 的 `settings.json` 常见包含 `env` 块，其中可能存放 API Key 等敏感信息。规范写明"Never include secrets in DockCat logs"，但备份是对原文件的完整拷贝，天然包含这些密钥，且备份目录/权限没有做加固（如 `chmod 600`）说明。这是与第 8 条"日志不含密钥"要求的一个逻辑缺口。

6. **JSON/YAML hook 合并策略描述不够精确，存在覆盖其他工具 hook 的风险**（§ Claude Code / § Hermes → Enable behavior）
   "Add DockCat-managed command hooks directly to the user settings JSON" 和 "Ensure a `hooks:` block exists" —— Claude Code 的 hooks 字段通常是数组（同一事件可挂多个 hook）。规范没有明确"合并进数组"还是"替换该事件的 hook 列表"，如果实现时简单赋值覆盖，会破坏用户已有的其他 hook 配置（例如用户自己配置的其他工具 hook）。

7. **Disable/Restore 逻辑存在"尽力而为"的模糊地带**（§ Codex → Disable behavior）
   "If the file changed since enable, remove only the DockCat wrapper and leave unrelated settings intact **where possible**" —— "where possible" 缺乏具体算法定义（是做 diff、还是基于标记字符串匹配移除、还是需要重新解析整个 TOML 树）。这部分逻辑复杂度和出错概率都很高，是实现中最容易产生"半吊子"回滚、遗留孤立 wrapper 的地方。

### 中 (Medium)

8. **GUI 进程 PATH 探测的经典 macOS 陷阱**（§ Codex / § Claude Code / § Hermes → 检测逻辑）
   规范多处依赖"locating `xxx` on `PATH`"做检测。macOS 上通过 Finder/Dock 启动的 GUI 应用其环境变量 `PATH` 通常不包含用户 shell rc 文件（`.zshrc` 等）里追加的路径（如 nvm、asdf、brew 自定义路径管理的工具）。若不特殊处理（如通过 `$SHELL -lic 'command -v xxx'` 探测登录 shell 的 PATH），会出现"用户明明装了但 DockCat 显示 not installed"的误判。

9. **TOML/YAML 往返解析可能丢失注释与格式**（§ Codex → Enable/Disable behavior, § Testing）
   `~/.codex/config.toml` 常被用户手工编辑并带注释。若使用通用 TOML 库做 parse→修改→serialize 往返，很可能丢失注释、字段顺序、空行等格式信息，即便语义正确也会让用户觉得"文件被弄乱了"。规范未讨论是否需要保格式的编辑方式（如基于行的定点 patch）。

10. **默认端口 8765 被占用时缺少自动降级策略**（§ App Settings / § Error Handling）
    规范只说明"Port unavailable: server failed to bind"作为错误状态展示，未说明是否自动尝试下一个可用端口或提示用户修改。对于"default on"的服务器，首次启动就撞到端口冲突会直接导致核心功能不可用。

11. **OpenClaw 检测逻辑基于单台开发机器的观察结果**（§ OpenClaw）
    "On this Mac, OpenClaw appears migrated into Hermes" —— 这是针对当前开发环境的个例描述，而非通用检测算法。需要明确"migrated"判定的通用规则（例如检测特定迁移标记文件/版本号），否则在其他用户机器上可能误判。

### 低 (Low)

12. **Hermes allowlist 项范围控制不够具体**（§ Hermes → Enable behavior）
    "Add or update allowlist entries only for the exact DockCat hook commands" —— 需要明确是"精确绝对路径匹配"而非允许通配符/相对路径，否则可能无意中放宽超出预期的命令执行许可。

13. **"Send Test Event" 未覆盖端到端 hook 验证**（§ Testing → Manual verification）
    测试事件只验证 DockCat 端点本身可达，不验证实际安装到 Codex/Claude Code/Hermes 里的 hook 触发链路是否生效。规范里没有自动化的"端到端验证已安装 hook"手段，完全依赖手工验证清单。

## Recommendations

1. 在编码前先做一个最小 spike：确认 DockCat 当前的分发/签名方式（沙盒 or 非沙盒 notarized），验证是否能直接读写 `~/.codex`、`~/.claude`、`~/.hermes` 而不需要额外用户授权流程；这会直接影响架构可行性。
2. 所有配置文件写入统一走"写临时文件 → fsync → rename 替换"原子模式，并在写入前先对目标文件做一次可解析性校验（dry-run parse），解析失败则拒绝写入并保留原文件（这与 § Error Handling 的"Config parse failed: do not write"要求一致，只是需要落到写入流程细节里）。
3. 在 Enable/Disable 操作前检测目标 agent 进程是否在运行，若在运行则提示用户"建议关闭后再操作"或明确告知需要重启生效（复用规范已有的"Needs restart"状态位）。
4. Codex notify 包裹使用参数化 exec（数组形式）而非字符串拼接，避免 shell 注入；将原始 `notify` 命令存入 manifest 时同样避免字符串拼接执行。
5. 备份文件权限设置为仅当前用户可读（如 `chmod 600`），并在文档中明确"备份可能包含用户密钥"，避免与"日志不含密钥"要求混淆。
6. Claude Code / Hermes 的 hook 写入采用"读取现有数组 → 追加/更新 DockCat 专属条目（按稳定标记去重）→ 写回"，禁止整段替换 hooks 配置。
7. Agent 检测统一通过登录 shell 解析 PATH（如 `$SHELL -lic 'command -v codex'`），而不是直接读取 GUI 进程继承的环境变量。
8. 明确端口占用时的处理策略（是否自动尝试 8766/8767 等），并在 UI 上提供手动修改端口的路径，减少"开箱即用失败"的概率。
9. 针对 TOML 编辑，评估是否需要引入保格式的编辑策略（定点替换 `notify = "..."` 这一行，而非整树 parse/serialize 往返），以保留用户注释与格式。

## Questions

1. DockCat 目前是否启用 App Sandbox？如果是，是否已有获取 `~/.codex`、`~/.claude`、`~/.hermes` 读写权限的方案（entitlement / 安全作用域书签 / 用户手动授权）？
2. 备份文件是否需要加密或限制权限，以应对配置文件中可能包含的密钥（如 Claude Code `settings.json` 的 `env` 字段）？
3. 当目标 agent（如 Claude Code）正在运行时，是否需要检测并阻止/警告用户再进行 Enable/Disable 操作，以避免文件竞态？
4. 默认端口 `8765` 被占用时，期望的行为是自动尝试其他端口，还是仅报错并要求用户手动修改？
5. 对于 Codex `config.toml` 等用户可能手工编辑并带注释的文件，是否要求保留原有格式/注释，还是可以接受标准 parse→serialize 往返导致的格式变化？
6. "Needs restart" 状态目前是纯静态提示，还是需要检测 agent 进程重启后自动刷新为"Enabled"？
