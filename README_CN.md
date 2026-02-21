# GitMemo Skill

这是一个为编码代理提供长期记忆能力的轻量级 Skill，基于**本地** `.mem` Git 仓库存储任务历史，且仅依赖 Git。

## 功能概览

- 将已完成任务沉淀为 `.mem/entries/` 下的 Markdown 记忆条目
- 提供完整接口：`init`、`search`、`read`、`commit`、`delete`
- `commit` 时自动将 `.mem` 分支与当前项目分支对齐
- 可通过 `AGENTS.md` 强制所有代理遵循统一记忆流程

## Git Memory 与向量数据库 Memory 对比

| 方案 | 优点 | 缺点 | 更适合 |
| --- | --- | --- | --- |
| 基于 Git 的 Memory（GitMemo） | 可审计、可追溯（有完整 Git 历史）；仅依赖 Git，部署简单；与代码分支天然对齐，便于代码评审 | 语义检索能力较弱（主要靠关键词/结构化文本）；数据量很大时检索效率不如向量索引；跨仓库聚合能力较弱 | 单仓库或中小规模团队；重视可解释性、审计和低运维成本 |
| 基于向量数据库的 Memory | 语义检索强，能处理同义改写和模糊问题；适合海量文本与跨项目知识库；可结合重排模型提升召回/排序效果 | 需要额外基础设施（向量库、Embedding 服务）；成本和运维复杂度更高；结果可解释性通常弱于 Git 历史 | 大规模知识库、跨项目检索、需要更高语义召回率的场景 |

实践建议：优先用 Git Memory 作为“事实层”（可审计、可回放），在需要更强语义召回时叠加向量检索作为“发现层”。

## 目录说明

- `SKILL.md`：技能定义与流程规则
- `agents-template.md`：可复制到项目 `AGENTS.md` 的模板片段
- `scripts/mem.ps1`：Windows 脚本入口
- `scripts/mem.sh`：Linux/macOS 脚本入口

## 快速开始

请在项目根目录执行命令（不要在 `.mem` 目录内执行）。

### Windows (PowerShell)

```powershell
./scripts/mem.ps1 init
./scripts/mem.ps1 search "auth,rate-limit" 0
./scripts/mem.ps1 read <commit_hash>
./scripts/mem.ps1 commit --file "entries/<timestamp>-<slug>.md" --title "[module] action object purpose" --body "summary..."
./scripts/mem.ps1 delete <commit_hash>
```

### Linux/macOS (Bash)

```bash
bash ./scripts/mem.sh init
bash ./scripts/mem.sh search "auth,rate-limit" 0
bash ./scripts/mem.sh read <commit_hash>
bash ./scripts/mem.sh commit --file "entries/<timestamp>-<slug>.md" --title "[module] action object purpose" --body "summary..."
bash ./scripts/mem.sh delete <commit_hash>
```

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

## 记忆条目格式

每条记忆都是 `.mem/entries/` 下的 Markdown 文件，使用 YAML front matter：

```md
---
date: 2026-02-19T15:10:10Z
status: done
repo_branch: main
repo_commit: 9f3e1a2
mem_branch: main
related_paths:
  - src/auth/login.ts
tags:
  - auth
  - security
---

### Original User Request
(verbatim)

### AI Understanding
- Goal:
- Constraints:
- Out of scope:

### Final Outcome
- Output 1:
```

文件命名约定：

- `<timestamp>-<slug>.md`（例如 `20260219T151010Z-add-auth-rate-limit.md`）

## 提交信息约定

- 标题：`[module] action + object + purpose`
- 正文包含 1-3 句任务摘要
- 正文包含元数据行：`date`、`tags`、`related-paths`

## AGENTS.md 接入

将 `agents-template.md` 内容复制到你的项目 `AGENTS.md`，即可让代理默认遵循 GitMemo 记忆策略。
