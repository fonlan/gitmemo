# >>> gitmemo:agents-template:start
## Memory Workflow (GitMemo)

This project uses the gitmemo skill (`.mem` git repo) for AI long-term memory.

- **Before working**: use the gitmemo skill `search` interface to find relevant past solutions; do not search by directly listing files under `.mem`; reuse if applicable.
- **Read limit**: if search returns more than 5 relevant memories, the AI must select only the 5 most likely ones before calling `read` (prioritize keyword overlap, title specificity, and recency).
- **After completing a task**: write a memory if the task is repo-related and complete, and either produced a valuable outcome or the user explicitly asked to remember. If the user explicitly asked to remember, that overrides the "valuable outcome" requirement.
- **User unsatisfied**: delete the memory, redo, and rewrite.
# <<< gitmemo:agents-template:end
