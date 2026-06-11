#!/usr/bin/env bash
# Publish subtree changes from the current branch to each component's upstream repository.
# Each component is tracked as a git subtree. Run this from the repo root.
#
# For every component, this splits the subtree out of the current branch into a
# synthetic linear history and pushes the resulting commit to the matching
# upstream remote under the target branch name.

set -euo pipefail

# shellcheck source=components.sh
source "$(dirname "$0")/components.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--force-with-lease] [branch]

Splits each component subtree from the current monorepo branch (HEAD) and
pushes it to the corresponding upstream remote. If [branch] is omitted, the
current monorepo branch name is used as the target branch on each upstream.

Options:
  --force-with-lease   Pass --force-with-lease to git push (safe force after
                       a rebase: the push is rejected if the remote moved).
  -h, --help           Show this help.
EOF
}

FORCE_WITH_LEASE=0
TARGET_BRANCH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force-with-lease)
            FORCE_WITH_LEASE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [[ -n "$TARGET_BRANCH" ]]; then
                echo "error: unexpected positional argument: $1" >&2
                exit 2
            fi
            TARGET_BRANCH="$1"
            shift
            ;;
    esac
done

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" == "HEAD" ]]; then
    echo "error: detached HEAD; check out a branch first" >&2
    exit 1
fi

if [[ -z "$TARGET_BRANCH" ]]; then
    TARGET_BRANCH="$CURRENT_BRANCH"
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "error: working tree is not clean; commit or stash changes first" >&2
    exit 1
fi

PUSH_ARGS=()
if [[ $FORCE_WITH_LEASE -eq 1 ]]; then
    PUSH_ARGS+=(--force-with-lease)
fi

FAILED=()

for entry in "${COMPONENTS[@]}"; do
    read -r prefix remote _ <<< "$entry"
    echo "==> Splitting $prefix/ from $CURRENT_BRANCH"
    if ! SPLIT_SHA=$(git subtree split --prefix="$prefix" HEAD); then
        echo "    FAILED to split $prefix" >&2
        FAILED+=("$prefix")
        echo
        continue
    fi
    echo "    split commit: $SPLIT_SHA"
    echo "    pushing to $remote $TARGET_BRANCH"
    if git push "${PUSH_ARGS[@]}" "$remote" "$SPLIT_SHA:refs/heads/$TARGET_BRANCH"; then
        echo "    ok"
    else
        echo "    FAILED to push $prefix" >&2
        FAILED+=("$prefix")
    fi
    echo
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "The following components did not publish cleanly: ${FAILED[*]}" >&2
    exit 1
fi

echo "All components published to $TARGET_BRANCH."
