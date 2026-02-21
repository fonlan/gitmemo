#!/usr/bin/env bash
set -euo pipefail

MEM_DIR=""

find_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || echo "$(pwd)"
}

get_branch() {
    local dir="$1"
    local branch
    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""
    if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
        branch="main"
    fi
    echo "$branch"
}

resolve_mem_dir() {
    local root
    root=$(find_repo_root)
    MEM_DIR="$root/.mem"
}

ensure_init() {
    resolve_mem_dir
    if [ ! -d "$MEM_DIR/.git" ]; then
        mkdir -p "$MEM_DIR/entries"
        git -C "$MEM_DIR" init -q
        touch "$MEM_DIR/entries/.gitkeep"
        git -C "$MEM_DIR" add .
        git -C "$MEM_DIR" commit -q -m "init: initialize memory repo"
    fi
}

sync_branch() {
    local root
    root=$(find_repo_root)
    local repo_branch
    repo_branch=$(get_branch "$root")
    local mem_branch
    mem_branch=$(get_branch "$MEM_DIR")

    if [ "$mem_branch" != "$repo_branch" ]; then
        if git -C "$MEM_DIR" show-ref --verify --quiet "refs/heads/$repo_branch" 2>/dev/null; then
            git -C "$MEM_DIR" checkout -q "$repo_branch"
        else
            git -C "$MEM_DIR" checkout -q -b "$repo_branch"
        fi
    fi
    echo "$repo_branch"
}

cmd_init() {
    ensure_init
    echo "OK: Memory repo initialized at $MEM_DIR"
}

cmd_search() {
    ensure_init
    local keywords="${1:-}"
    local skip="${2:-0}"

    if [ -z "$keywords" ]; then
        echo "Usage: mem.sh search <keywords_csv> [skip]" >&2
        return 1
    fi

    local grep_args=()
    IFS=',' read -ra kw_array <<< "$keywords"
    for kw in "${kw_array[@]}"; do
        kw=$(echo "$kw" | xargs)
        [ -n "$kw" ] && grep_args+=(--grep="$kw")
    done

    if [ ${#grep_args[@]} -eq 0 ]; then
        echo "Error: no valid keywords" >&2
        return 1
    fi

    git -C "$MEM_DIR" log "${grep_args[@]}" \
        -i --skip="$skip" --max-count=100 \
        --format="%H|%s|%cd" --date=iso --all 2>/dev/null || true
}

cmd_read() {
    ensure_init
    local commit_hash="${1:-}"

    if [ -z "$commit_hash" ]; then
        echo "Usage: mem.sh read <commit_hash>" >&2
        return 1
    fi

    local file
    file=$(git -C "$MEM_DIR" diff-tree --no-commit-id --name-only -r "$commit_hash" -- entries/ 2>/dev/null | head -1)

    if [ -z "$file" ]; then
        file=$(git -C "$MEM_DIR" diff-tree --root --no-commit-id --name-only -r "$commit_hash" -- entries/ 2>/dev/null | head -1)
    fi

    if [ -n "$file" ]; then
        git -C "$MEM_DIR" show "$commit_hash:$file" 2>/dev/null
    else
        echo "Error: no entry file found in commit $commit_hash" >&2
        return 1
    fi
}

cmd_commit() {
    ensure_init
    local file="" title="" body=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)  file="$2";  shift 2;;
            --title) title="$2"; shift 2;;
            --body)  body="$2";  shift 2;;
            *) echo "Unknown option: $1" >&2; return 1;;
        esac
    done

    if [ -z "$file" ] || [ -z "$title" ]; then
        echo "Usage: mem.sh commit --file <path> --title <title> [--body <body>]" >&2
        return 1
    fi

    if [ ! -f "$MEM_DIR/$file" ]; then
        echo "Error: file not found: $MEM_DIR/$file" >&2
        return 1
    fi

    sync_branch >/dev/null

    git -C "$MEM_DIR" add "$file"
    if [ -n "$body" ]; then
        git -C "$MEM_DIR" commit -q -m "$title" -m "$body"
    else
        git -C "$MEM_DIR" commit -q -m "$title"
    fi

    local hash
    hash=$(git -C "$MEM_DIR" rev-parse HEAD)
    echo "OK: $hash"
}

cmd_delete() {
    ensure_init
    local commit_hash="${1:-}"

    if [ -z "$commit_hash" ]; then
        echo "Usage: mem.sh delete <commit_hash>" >&2
        return 1
    fi

    local file
    file=$(git -C "$MEM_DIR" diff-tree --no-commit-id --name-only -r "$commit_hash" -- entries/ 2>/dev/null | head -1)

    if [ -z "$file" ]; then
        file=$(git -C "$MEM_DIR" diff-tree --root --no-commit-id --name-only -r "$commit_hash" -- entries/ 2>/dev/null | head -1)
    fi

    if [ -z "$file" ]; then
        echo "Error: no entry file found in commit $commit_hash" >&2
        return 1
    fi

    if [ -f "$MEM_DIR/$file" ]; then
        git -C "$MEM_DIR" rm -q "$file"
        git -C "$MEM_DIR" commit -q -m "delete: remove $(basename "$file" .md)"
        echo "OK: deleted $file"
    else
        echo "Error: file already deleted: $file" >&2
        return 1
    fi
}

case "${1:-help}" in
    init)    shift; cmd_init "$@";;
    search)  shift; cmd_search "$@";;
    read)    shift; cmd_read "$@";;
    commit)  shift; cmd_commit "$@";;
    delete)  shift; cmd_delete "$@";;
    *)
        echo "Usage: mem.sh {init|search|read|commit|delete}" >&2
        echo "  init                                    Initialize .mem repo" >&2
        echo "  search <keywords_csv> [skip]            Search memories" >&2
        echo "  read <commit_hash>                      Read memory content" >&2
        echo "  commit --file F --title T [--body B]    Commit memory entry" >&2
        echo "  delete <commit_hash>                    Delete memory entry" >&2
        ;;
esac
