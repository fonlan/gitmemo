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

## File Layout

- `SKILL.md`: skill definition and workflow rules
- `agents-template.md`: snippet to append to your agent instruction file
- `scripts/mem.ps1`: Windows runtime interface used by agents
- `scripts/mem.sh`: Linux/macOS runtime interface used by agents

## Installation

### 1. Manual Install (User-Executed)

Install into the current project from project root:

```bash
git clone https://github.com/fonlan/gitmemo.git .agents/skills/gitmemo
```

Or use a submodule:

```bash
git submodule add https://github.com/fonlan/gitmemo.git .agents/skills/gitmemo
```

Then copy `./.agents/skills/gitmemo/agents-template.md` into your tool's project instruction file:
Copy it as-is, including the marker lines `# >>> gitmemo:agents-template:start` and `# <<< gitmemo:agents-template:end`, so future project-mode auto installs can sync the managed block safely.

| AI tool | Project instruction file | Notes |
| --- | --- | --- |
| Claude Code | `CLAUDE.md` | Claude Code loads project memory from this file. |
| Codex | `AGENTS.md` | Codex reads repo/user `AGENTS.md` instructions. |
| GitHub Copilot | `.github/copilot-instructions.md` | You can also add scoped rules under `.github/instructions/*.instructions.md`. Enable `chat.useAgentsMdFile` in VS Code (open `vscode://settings/chat.useAgentsMdFile`) so Copilot can read `AGENTS.md`. |
| Trae | `.trae/rules/project_rules.md` | Create via Trae "Rules > Project Rules" and paste the same workflow instructions. |
| Other agent tools | `AGENTS.md` (recommended) | If the tool supports `AGENTS.md`, reuse the same template directly. |

### 2. Fully Automated Install (Agent-Executed)

Use `INSTALL.md` as the execution contract for coding agents:

- [INSTALL.md](./INSTALL.md)

Two automation modes are supported:

- Global install to the home skill directory:
  `~/.agents/skills/gitmemo` (Linux/macOS) or `%USERPROFILE%\\.agents\\skills\\gitmemo` (Windows)
- Project install to `<project_root>/.agents/skills/gitmemo`

Example one-sentence prompts:
- Install to global
```text
Follow https://github.com/fonlan/gitmemo/blob/main/INSTALL.md and install gitmemo in global mode, then report installed path, commit, and a manual next step to update your tool instruction file with agents-template.md.
```

- Install to current project
```text
Follow https://github.com/fonlan/gitmemo/blob/main/INSTALL.md and install gitmemo in project mode for the current repository, then report installed path, commit, and instruction integration sync result.
```

After installation, the agent handles `.mem` initialization, search, read, write, and delete automatically during tasks.

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
