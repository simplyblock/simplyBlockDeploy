#!/usr/bin/env bash
# Pull upstream changes from each component's upstream repository into this monorepo.
# Each component is tracked as a git subtree. Run this from the repo root on the main branch.

set -euo pipefail

# shellcheck source=components.sh
source "$(dirname "$0")/components.sh"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo "error: must be on the main branch (currently on '$CURRENT_BRANCH')" >&2
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "error: working tree is not clean; commit or stash changes first" >&2
    exit 1
fi

FAILED=()

for entry in "${COMPONENTS[@]}"; do
    read -r prefix remote branch <<< "$entry"
    echo "==> Pulling $remote/$branch into $prefix/"
    if git subtree pull --prefix="$prefix" "$remote" "$branch" --squash -m "Chore: update $prefix from upstream $remote/$branch"; then
        echo "    ok"
    else
        echo "    FAILED — resolve conflicts, then re-run or complete the merge manually" >&2
        FAILED+=("$prefix")
    fi
    echo
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "The following components did not update cleanly: ${FAILED[*]}" >&2
    exit 1
fi

echo "All components updated."
