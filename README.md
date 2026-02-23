[Chinese Version (README_CN.md)](./README_CN.md)

# GitMemo Skill

A fully automated skill that gives coding agents long-term memory through a **local** `.mem` Git repository. Git is the only dependency, and users do not need to run memory commands manually.

## Overview

- Stores completed task outcomes as markdown entries under `.mem/entries/`
- Runs memory operations automatically (`init`, `search`, `read`, `commit`, `delete`) during agent tasks
- Supports `search` match modes: `and`, `or`, and default `auto` (AND-first, OR fallback)
- Aligns the `.mem` branch with the current project branch on commit
- Integrates with agent instruction files so all agents follow the same memory policy

## Git-Based vs Vector-DB Memory

| Approach | Strengths | Weaknesses | Best Fit |
| --- | --- | --- | --- |
| Git-based memory (GitMemo) | Fully auditable and traceable via Git history; Git-only dependency and simple setup; naturally aligned with code branches and review workflows | Weaker semantic retrieval (mostly keyword/structured text driven); less efficient than vector indexes at very large scale; weaker cross-repo aggregation | Single-repo or small/medium teams that prioritize explainability, auditability, and low ops cost |
| Vector-database memory | Strong semantic search for paraphrases and fuzzy queries; scales well for large corpora and cross-project knowledge; can improve recall/ranking with rerankers | Requires extra infra (vector DB + embedding service); higher cost and ops complexity; usually less interpretable than Git history | Large knowledge bases, cross-project retrieval, and use cases that need high semantic recall |

Practical guidance: use Git memory as the auditable "source-of-truth layer", then add vector retrieval as a "discovery layer" when semantic recall becomes a bottleneck.

## File Layout

- `SKILL.md`: skill definition and workflow rules
- `agents-template.md`: snippet to append to your agent instruction file
- `scripts/mem.ps1`: Windows runtime interface used by agents
- `scripts/mem.sh`: Linux/macOS runtime interface used by agents

## Quick Start

### 1. Install this skill into your project

From your project root:

```bash
git clone https://github.com/fonlan/gitmemo.git .agents/skills/gitmemo
```

Or add it as a submodule:

```bash
git submodule add https://github.com/fonlan/gitmemo.git .agents/skills/gitmemo
```

### 2. Add `agents-template.md` instructions to your AI tool

Copy the content of `./.agents/skills/gitmemo/agents-template.md` into your tool's project-level instruction file:

| AI tool | Project instruction file | Notes |
| --- | --- | --- |
| Claude Code | `CLAUDE.md` | Claude Code loads project memory from this file. |
| Codex | `AGENTS.md` | Codex reads repo/user `AGENTS.md` instructions. |
| GitHub Copilot | `.github/copilot-instructions.md` | You can also add scoped rules under `.github/instructions/*.instructions.md`. |
| Trae | `.trae/rules/project_rules.md` | Create via Trae "Rules > Project Rules" and paste the same workflow instructions. |
| Other agent tools | `AGENTS.md` (recommended) | If the tool supports `AGENTS.md`, reuse the same template directly. |

After setup, the agent handles `.mem` initialization, search, read, write, and delete automatically during tasks. No user-side memory command operations are required.

## Agent Workflow

### 1. Before Work: Search

1. Extract 3-5 keywords from the user request.
2. Run `search` with `skip=0`.
3. If more than 5 relevant results are returned, let the agent select only the 5 most likely memories (keyword overlap, title specificity, recency) before reading.
4. If not relevant, paginate with `skip=100` and `skip=200`.
5. If relevant memories exist, run `read` only on the selected memories and reuse conclusions when appropriate.

### 2. After Completion: Write

Write memory only when all are true:

- Task is complete
- Task is related to the current repository
- One of the following is true:
  - Outcome is valuable and reusable
  - User explicitly asked to remember this request/task

If the user explicitly asked to remember, that overrides the "valuable and reusable" requirement, but task completion and repository relevance are still required.

Do not write memory for incomplete tasks or requests unrelated to the current repository. For casual chat or pure Q&A, do not write unless the user explicitly asked to remember.

### 3. If User Is Unsatisfied: Delete and Rewrite

1. Run `delete <commit_hash>`
2. Redo the task based on feedback
3. Write a corrected memory entry
