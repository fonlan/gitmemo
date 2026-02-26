# >>> gitmemo:agents-template:start
## Memory Workflow (GitMemo)

This project uses the gitmemo skill (`.mem` git repo) for AI long-term memory.

- **Before working**: MUST use the gitmemo skill `search` interface to find relevant past solutions; do not search by directly listing files under `.mem`; reuse if applicable.
- **Read limit**: if search returns more than 5 relevant memories, the AI must select only the 5 most likely ones before calling `read` (prioritize keyword overlap, title specificity, and recency).
- **After completing a task**: MUST write a memory if the task is repo-related and complete, and either produced a valuable outcome or the user explicitly asked to remember. If the user explicitly asked to remember, that overrides the "valuable outcome" requirement.
- **User unsatisfied**: MUST delete the memory, redo, and rewrite.

> **⚠ End-of-session checkpoint**: When the user says "no more tasks", "that's all", or the conversation is ending, MUST check whether any completed tasks still need a memory written. Write all pending memories BEFORE closing the conversation.
# <<< gitmemo:agents-template:end
