# GitMemo Skill

这是一个为编码代理提供长期记忆能力的全自动 Skill，基于**本地** `.mem` Git 仓库存储任务历史，且仅依赖 Git；用户无需手动执行记忆相关命令。

## 功能概览

- 将已完成任务沉淀为 `.mem/entries/` 下的 Markdown 记忆条目
- 在代理任务过程中自动执行：`init`、`search`、`read`、`commit`、`delete`
- `commit` 时自动将 `.mem` 分支与当前项目分支对齐
- 可通过各类代理指令文件统一约束记忆流程

## Git Memory 与向量数据库 Memory 对比

| 方案 | 优点 | 缺点 | 更适合 |
| --- | --- | --- | --- |
| 基于 Git 的 Memory（GitMemo） | 可审计、可追溯（有完整 Git 历史）；仅依赖 Git，部署简单；与代码分支天然对齐，便于代码评审 | 语义检索能力较弱（主要靠关键词/结构化文本）；数据量很大时检索效率不如向量索引；跨仓库聚合能力较弱 | 单仓库或中小规模团队；重视可解释性、审计和低运维成本 |
| 基于向量数据库的 Memory | 语义检索强，能处理同义改写和模糊问题；适合海量文本与跨项目知识库；可结合重排模型提升召回/排序效果 | 需要额外基础设施（向量库、Embedding 服务）；成本和运维复杂度更高；结果可解释性通常弱于 Git 历史 | 大规模知识库、跨项目检索、需要更高语义召回率的场景 |

实践建议：优先用 Git Memory 作为“事实层”（可审计、可回放），在需要更强语义召回时叠加向量检索作为“发现层”。

## 目录说明

- `SKILL.md`：技能定义与流程规则
- `agents-template.md`：可复制到代理项目级指令文件的模板片段
- `scripts/mem.ps1`：供代理调用的 Windows 运行时接口
- `scripts/mem.sh`：供代理调用的 Linux/macOS 运行时接口

## 快速开始

### 1. 将本 Skill 安装到你的项目中

在项目根目录执行：

```bash
git clone https://github.com/fonlan/gitmemo.git .agents/skills/gitmemo
```

或使用子模块：

```bash
git submodule add https://github.com/fonlan/gitmemo.git .agents/skills/gitmemo
```

### 2. 将 `agents-template.md` 指令写入你的 AI 工具

把 `./.agents/skills/gitmemo/agents-template.md` 内容复制到对应工具的项目级指令文件：

| AI 工具 | 项目指令文件 | 说明 |
| --- | --- | --- |
| Claude Code | `CLAUDE.md` | Claude Code 会从该文件读取项目规则。 |
| Codex | `AGENTS.md` | Codex 会读取仓库/用户级 `AGENTS.md` 指令。 |
| GitHub Copilot | `.github/copilot-instructions.md` | 也可在 `.github/instructions/*.instructions.md` 中写更细粒度规则。 |
| Trae | `.trae/rules/project_rules.md` | 可在 Trae 的 “Rules > Project Rules” 中创建并粘贴同样指令。 |
| 其他代理工具 | `AGENTS.md`（推荐） | 如果工具支持 `AGENTS.md`，可直接复用同一模板。 |

完成以上配置后，代理会在任务过程中自动处理 `.mem` 初始化、检索、读取、写入和删除；用户不需要手动介入记忆操作。

## 代理工作流

### 1. 开始任务前：先搜索

1. 从用户请求提取 3-5 个关键词
2. 先执行 `search`（`skip=0`）
3. 若无相关结果，再分页执行 `skip=100`、`skip=200`
4. 命中后使用 `read` 查看详情并复用结论

### 2. 完成任务后：写入记忆

仅在以下条件都满足时写入：

- 任务已完成
- 任务与当前仓库相关
- 产出有复用价值

以下情况不写入：

- 纯闲聊/纯问答
- 任务未完成或仍在等待用户反馈
- 与当前仓库无关

### 3. 用户不满意：删除并重写

1. 执行 `delete <commit_hash>`
2. 按反馈重做任务
3. 重新写入新的记忆条目
