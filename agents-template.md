# >>> gitmemo:agents-template:start
## Memory Workflow (GitMemo)

This project uses the gitmemo skill (`.mem` git repo) for AI long-term memory.

- **Before working**: MUST use GitMemo through the installed skill scripts, not through a bare `gitmemo` executable. Treat `gitmemo` as the skill name, **not** a command name.
  - DO NOT run `gitmemo search`, `gitmemo read`, `gitmemo write`, or list/search `.mem` directly.
  - Resolve `<GITMEMO_SKILL_DIR>` to the directory containing the GitMemo `SKILL.md`, then search with one of:
    - Bash/WSL/Linux/macOS: `bash "<GITMEMO_SKILL_DIR>/scripts/mem.sh" search "<keywords_csv>" 0 --mode auto`
    - Windows PowerShell: `powershell -NoProfile -ExecutionPolicy Bypass -File "<GITMEMO_SKILL_DIR>/scripts/mem.ps1" search "<keywords_csv>" 0 --mode auto`
  - Use the same `mem.sh` / `mem.ps1` script path for `read`, `write`, and `delete`.
  - If the script path cannot be resolved, stop and report the missing GitMemo skill installation path; do not invent a fallback `gitmemo` command.
  - Reuse relevant memories if applicable.
- **Read limit**: if search returns more than 5 relevant memories, the AI must select only the 5 most likely ones before calling `read` (prioritize keyword overlap, title specificity, and recency).
- **After completing a task**: MUST write a memory if the task is repo-related and complete, and either produced a valuable outcome or the user explicitly asked to remember. If the user explicitly asked to remember, that overrides the "valuable outcome" requirement.
- **Operational git-only tasks**: DO NOT write a memory for purely operational VCS actions (e.g., commit/push only) when no new implementation or analysis outcome is produced.
- **User unsatisfied**: MUST delete the memory, redo, and rewrite.

> **⚠ End-of-session checkpoint**: When the user says "no more tasks", "that's all", or the conversation is ending, MUST check whether any completed tasks still need a memory written. Write all pending memories BEFORE closing the conversation.
# <<< gitmemo:agents-template:end
