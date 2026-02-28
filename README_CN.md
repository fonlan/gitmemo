# GitMemo Skill

这是一个为编码代理提供长期记忆能力的全自动 Skill，基于**本地** `.mem` Git 仓库存储任务历史，且仅依赖 Git；用户无需手动执行记忆相关命令。

## 项目特点

- 使用极其简单：安装后即可用，日常任务无需手动执行记忆命令
- 全自动：代理会在任务流程中自动执行 `init`、`search`、`read`、`write`、`delete`
- 纯本地、离线可用：记忆保存在本地 `.mem` Git 仓库，不依赖云端服务
- 除 Git 外无依赖：运行只要求 Git 环境
- 省 Token：通过检索并复用历史结论，减少重复上下文注入
- 不会导致上下文爆炸：先搜索再读取，且相关记忆读取上限为 5 条
- 可审计：所有记忆操作都有 Git 历史可查
- 可追溯：每条记忆都可按提交记录回放来源与变更
- 易管理：支持按分支对齐、删除重写、文本化 review

## 功能概览

- 将已完成任务沉淀为 `.mem/entries/` 下的 Markdown 记忆条目
- 在代理任务过程中自动执行：`init`、`search`、`read`、`write`、`delete`
- `search` 支持 `and`、`or`、默认 `auto` 三种匹配模式（先 AND，不足再回退 OR）
- 在 `write` 时自动将 `.mem` 分支与当前项目分支对齐
- 可通过各类代理指令文件统一约束记忆流程

## Git Memory 与向量数据库 Memory 对比

| 方案 | 优点 | 缺点 | 更适合 |
| --- | --- | --- | --- |
| 基于 Git 的 Memory（GitMemo） | 可审计、可追溯（有完整 Git 历史）；仅依赖 Git，部署简单；与代码分支天然对齐，便于代码评审 | 语义检索能力较弱（主要靠关键词/结构化文本）；数据量很大时检索效率不如向量索引；跨仓库聚合能力较弱 | 单仓库或中小规模团队；重视可解释性、审计和低运维成本 |
| 基于向量数据库的 Memory | 语义检索强，能处理同义改写和模糊问题；适合海量文本与跨项目知识库；可结合重排模型提升召回/排序效果 | 需要额外基础设施（向量库、Embedding 服务）；成本和运维复杂度更高；结果可解释性通常弱于 Git 历史 | 大规模知识库、跨项目检索、需要更高语义召回率的场景 |

## 目录说明

- `SKILL.md`：技能定义与流程规则
- `agents-template.md`：可复制到代理项目级指令文件的模板片段
- `scripts/mem.ps1`：供代理调用的 Windows 运行时接口
- `scripts/mem.sh`：供代理调用的 Linux/macOS 运行时接口

## 安装

### 1. 手动安装（用户执行）

在当前项目根目录执行：

```bash
git clone https://github.com/fonlan/gitmemo.git .agents/skills/gitmemo
```

或使用子模块：

```bash
git submodule add https://github.com/fonlan/gitmemo.git .agents/skills/gitmemo
```

然后把 `./.agents/skills/gitmemo/agents-template.md` 内容复制到对应工具的项目级指令文件：
请原样复制（包含 `# >>> gitmemo:agents-template:start` 和 `# <<< gitmemo:agents-template:end` 标记行），这样就算后续用 project 模式自动安装才能安全同步管理块也能避免重复。

### 2. 全自动安装（代理执行）

让 coding agent 严格按 `INSTALL.md` 流程执行安装：

- [INSTALL.md](./INSTALL.md)

支持两种自动化模式：

- 全局安装（具体路径与各工具 global 规则以 `INSTALL.md` 为准）
- 当前项目安装到 `<project_root>/.agents/skills/gitmemo`

可直接给代理的一句话示例：
- 安装到全局（自动识别，best-effort）
```text
根据 https://github.com/fonlan/gitmemo/blob/main/INSTALL.md 的流程，以 global 模式安装 gitmemo；自动识别当前 coding agent（codex/claude code/gemini cli/copilot/cursor），并按 INSTALL.md 中该工具的 global 规则集成 agents-template.md；若无法可靠识别则明确要求用户指定 agent 类型；若工具为 Cursor，则需把模板写入 ~/.cursor/rules/gitmemo.mdc（带必需 YAML frontmatter），并在 Windows 上使用目录 Junction（mklink /J，无需管理员权限）将 ~/.cursor/skills/gitmemo 创建为指向 ~/.agents/skills/gitmemo 的链接，且命令需幂等：若路径已存在先删除，再创建；最后汇报安装路径、commit、agent 类型和指令集成结果。
```

- 安装到全局（按工具显式指定，推荐）
  - Codex
  ```text
  根据 https://github.com/fonlan/gitmemo/blob/main/INSTALL.md 的流程，以 global 模式安装 gitmemo，并按 Codex 的 global 规则集成 agents-template.md；最后汇报安装路径、commit 和指令集成结果。
  ```
  - Claude Code
  ```text
  根据 https://github.com/fonlan/gitmemo/blob/main/INSTALL.md 的流程，以 global 模式安装 gitmemo，并按 Claude Code 的 global 规则集成 agents-template.md；最后汇报安装路径、commit 和指令集成结果。
  ```
  - Gemini CLI
  ```text
  根据 https://github.com/fonlan/gitmemo/blob/main/INSTALL.md 的流程，以 global 模式安装 gitmemo，并按 Gemini CLI 的 global 规则集成 agents-template.md；最后汇报安装路径、commit 和指令集成结果。
  ```
  - GitHub Copilot
  ```text
  根据 https://github.com/fonlan/gitmemo/blob/main/INSTALL.md 的流程，以 global 模式安装 gitmemo，并按 GitHub Copilot 的 global 规则集成 agents-template.md；最后汇报安装路径、commit 和指令集成结果。
  ```
  - Cursor
  ```text
  根据 https://github.com/fonlan/gitmemo/blob/main/INSTALL.md 的流程，以 global 模式安装 gitmemo，并按 Cursor 的 global 规则集成 agents-template.md（写入 ~/.cursor/rules/gitmemo.mdc 并添加必需 YAML frontmatter；Windows 上使用目录 Junction（mklink /J，无需管理员权限）将 ~/.cursor/skills/gitmemo 创建为指向 ~/.agents/skills/gitmemo 的链接，且命令需幂等：若路径已存在先删除，再创建）；最后汇报安装路径、commit 和指令集成结果。
  ```
- 安装到当前项目
```text
根据 https://github.com/fonlan/gitmemo/blob/main/INSTALL.md 的流程，以 project 模式安装当前仓库的 gitmemo，并汇报安装路径、commit 和指令集成同步结果。
```

安装完成后，代理会在任务过程中自动处理 `.mem` 初始化、检索、读取、写入和删除；用户不需要手动介入记忆操作。

## 代理工作流

### 1. 开始任务前：先搜索

1. 从用户请求提取 3-5 个关键词
2. 先执行 `search`（`skip=0`）
3. 若返回的相关结果超过 5 条，先由代理按相关性选出最可能的 5 条（关键词重合度、标题明确性、时间新近性）再读取
4. 若无相关结果，再分页执行 `skip=100`、`skip=200`
5. 命中后仅对选中的条目使用 `read` 查看详情并复用结论

### 2. 完成任务后：写入记忆

仅在以下条件都满足时写入：

- 任务已完成
- 任务与当前仓库相关
- 以下至少一条成立：
  - 产出有复用价值
  - 用户在请求中明确要求“记住”本次请求/任务

以下情况不写入：

- 纯闲聊/纯问答（除非用户明确要求“记住”）
- 任务未完成或仍在等待用户反馈
- 与当前仓库无关

若用户明确要求“记住”，可覆盖“产出有复用价值”这一条，但仍必须满足“任务已完成”且“与当前仓库相关”。

### 3. 用户不满意：删除并重写

1. 执行 `delete <commit_hash>`
2. 按反馈重做任务
3. 重新写入新的记忆条目
