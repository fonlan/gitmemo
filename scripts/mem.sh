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

normalize_entry_file() {
    local file="$1"
    if [ -z "$file" ]; then
        echo ""
        return
    fi

    case "$file" in
        entries/*) echo "$file" ;;
        *) echo "entries/$file" ;;
    esac
}

is_safe_entry_path() {
    local file="$1"
    case "$file" in
        /*|*../*|*/..|../*|*\\*|*:*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

slugify_title() {
    local title="$1"
    local slug
    slug=$(printf '%s' "$title" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
    if [ -z "$slug" ]; then
        slug="memory-entry"
    fi
    echo "$slug"
}

cmd_write() {
    ensure_init
    local file="" title="" body="" content="" content_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)         file="$2";         shift 2;;
            --title)        title="$2";        shift 2;;
            --body)         body="$2";         shift 2;;
            --content)      content="$2";      shift 2;;
            --content-file) content_file="$2"; shift 2;;
            *) echo "Unknown option: $1" >&2; return 1;;
        esac
    done

    if [ -z "$title" ]; then
        echo "Usage: mem.sh write --title <title> [--file <path>] (--content <markdown> | --content-file <path>) [--body <body>]" >&2
        return 1
    fi

    if [ -n "$content" ] && [ -n "$content_file" ]; then
        echo "Error: use only one of --content or --content-file" >&2
        return 1
    fi

    if [ -z "$content" ] && [ -z "$content_file" ]; then
        echo "Error: missing content. Use --content or --content-file." >&2
        return 1
    fi

    if [ -n "$content_file" ] && [ ! -f "$content_file" ]; then
        echo "Error: content file not found: $content_file" >&2
        return 1
    fi

    if [ -z "$file" ]; then
        local ts slug
        ts=$(date -u +"%Y%m%dT%H%M%SZ")
        slug=$(slugify_title "$title")
        file="entries/$ts-$slug.md"
    else
        file=$(normalize_entry_file "$file")
    fi

    if ! is_safe_entry_path "$file"; then
        echo "Error: invalid file path: $file" >&2
        return 1
    fi

    case "$file" in
        *.md) ;;
        *) file="${file}.md" ;;
    esac

    sync_branch >/dev/null

    local full_path
    full_path="$MEM_DIR/$file"
    mkdir -p "$(dirname "$full_path")"

    if [ -n "$content_file" ]; then
        cat "$content_file" > "$full_path"
    else
        printf '%s\n' "$content" > "$full_path"
    fi

    git -C "$MEM_DIR" add "$file"
    if [ -n "$body" ]; then
        git -C "$MEM_DIR" commit -q -m "$title" -m "$body"
    else
        git -C "$MEM_DIR" commit -q -m "$title"
    fi

    local hash
    hash=$(git -C "$MEM_DIR" rev-parse HEAD)
    echo "OK: $hash|$file"
}

cmd_init() {
    ensure_init
    echo "OK: Memory repo initialized at $MEM_DIR"
}

cmd_search() {
    ensure_init
    local keywords="${1:-}"
    shift || true
    local skip="0"
    local mode="auto"

    if [ -z "$keywords" ]; then
        echo "Usage: mem.sh search <keywords_csv> [skip] [mode] [--mode <and|or|auto>]" >&2
        return 1
    fi

    if [ $# -gt 0 ] && [[ "${1:-}" =~ ^-?[0-9]+$ ]]; then
        skip="$1"
        shift
    fi

    if [ $# -gt 0 ] && [ "${1:-}" != "--mode" ]; then
        mode="$1"
        shift
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --mode)
                if [ $# -lt 2 ]; then
                    echo "Error: --mode requires a value (and|or|auto)" >&2
                    return 1
                fi
                mode="$2"
                shift 2
                ;;
            *)
                echo "Unknown option for search: $1" >&2
                return 1
                ;;
        esac
    done

    if ! [[ "$skip" =~ ^[0-9]+$ ]]; then
        echo "Error: skip must be a non-negative integer" >&2
        return 1
    fi

    mode=$(echo "$mode" | tr '[:upper:]' '[:lower:]')
    case "$mode" in
        and|or|auto) ;;
        *)
            echo "Error: mode must be one of: and, or, auto" >&2
            return 1
            ;;
    esac

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

    run_search_for_mode() {
        local search_mode="$1"
        local search_skip="$2"
        local mode_args=()
        [ "$search_mode" = "and" ] && mode_args+=(--all-match)

        local limit=100
        local batch_size=200
        local raw_skip=0
        local remaining_skip="$search_skip"
        local results=()
        local reached_limit=0

        local active_entries
        active_entries=$(git -C "$MEM_DIR" ls-tree -r --name-only HEAD -- entries/ 2>/dev/null || true)
        local active_entries_nl=$'\n'"$active_entries"$'\n'

        while [ "${#results[@]}" -lt "$limit" ]; do
            local batch_output
            batch_output=$(git -C "$MEM_DIR" log "${grep_args[@]}" "${mode_args[@]}" \
                -i --skip="$raw_skip" --max-count="$batch_size" \
                --format=$'%H\t%s\t%cd' --date=iso \
                --name-only --all -- entries/ 2>/dev/null || true)

            [ -z "$batch_output" ] && break

            local batch_count=0
            local current_hash=""
            local current_subject=""
            local current_date=""
            local current_file=""

            while IFS= read -r line; do
                [ -z "$line" ] && continue

                local parsed_hash parsed_subject parsed_date
                IFS=$'\t' read -r parsed_hash parsed_subject parsed_date <<< "$line"

                if [[ "$parsed_hash" =~ ^[0-9a-f]{40}$ ]]; then
                    if [ -n "$current_hash" ]; then
                        if [[ "$current_subject" != delete:\ remove* ]] && [ -n "$current_file" ] && [[ "$active_entries_nl" == *$'\n'"$current_file"$'\n'* ]]; then
                            if [ "$remaining_skip" -gt 0 ]; then
                                remaining_skip=$((remaining_skip - 1))
                            else
                                results+=("$current_hash|$current_subject|$current_date")
                                if [ "${#results[@]}" -ge "$limit" ]; then
                                    reached_limit=1
                                    break
                                fi
                            fi
                        fi
                    fi

                    current_hash="$parsed_hash"
                    current_subject="$parsed_subject"
                    current_date="$parsed_date"
                    current_file=""
                    batch_count=$((batch_count + 1))
                    continue
                fi

                if [ -z "$current_file" ] && [[ "$line" == entries/*.md ]]; then
                    current_file="$line"
                fi
            done <<< "$batch_output"

            if [ "$reached_limit" -ne 1 ] && [ -n "$current_hash" ]; then
                if [[ "$current_subject" != delete:\ remove* ]] && [ -n "$current_file" ] && [[ "$active_entries_nl" == *$'\n'"$current_file"$'\n'* ]]; then
                    if [ "$remaining_skip" -gt 0 ]; then
                        remaining_skip=$((remaining_skip - 1))
                    else
                        results+=("$current_hash|$current_subject|$current_date")
                        if [ "${#results[@]}" -ge "$limit" ]; then
                            reached_limit=1
                        fi
                    fi
                fi
            fi

            [ "$reached_limit" -eq 1 ] && break
            [ "$batch_count" -lt "$batch_size" ] && break
            raw_skip=$((raw_skip + batch_size))
        done

        printf '%s\n' "${results[@]}"
    }

    if [ "$mode" = "auto" ]; then
        local auto_min_results=3
        local and_results and_count
        and_results="$(run_search_for_mode and "$skip")"
        and_count=$(printf '%s\n' "$and_results" | awk 'NF { c++ } END { print c + 0 }')

        if [ "$and_count" -ge "$auto_min_results" ]; then
            printf '%s\n' "$and_results" | sed '/^$/d'
        else
            run_search_for_mode or "$skip"
        fi
        return 0
    fi

    run_search_for_mode "$mode" "$skip"
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
    write)   shift; cmd_write "$@";;
    delete)  shift; cmd_delete "$@";;
    *)
        echo "Usage: mem.sh {init|search|read|write|delete}" >&2
        echo "  init                                    Initialize .mem repo" >&2
        echo "  search <keywords_csv> [skip] [mode] [--mode M]  Search memories (M: and|or|auto)" >&2
        echo "  read <commit_hash>                      Read memory content" >&2
        echo "  write --title T [--file F] (--content C | --content-file P) [--body B]" >&2
        echo "  delete <commit_hash>                    Delete memory entry" >&2
        ;;
esac
