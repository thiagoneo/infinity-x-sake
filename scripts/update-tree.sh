#!/usr/bin/env bash
# Brings LineageOS updates into the sake tree in your fork:
# replays your commits on top of upstream (rebase) and pushes to GitHub.
# Usage: bash scripts/update-tree.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

TREE="$SRC/device/asus/sake"
cd "$TREE"

[ -z "$(git status --porcelain)" ] || die "There are uncommitted changes in $TREE"

ensure_full_history "$TREE" "https://github.com/$GITHUB_USER/android_device_asus_sake" "$TREE_BRANCH"
git fetch -q "$UPSTREAM_URL" "$UPSTREAM_BRANCH"
n=$(git rev-list --count HEAD..FETCH_HEAD)
[ "$n" -gt 0 ] || { info "The tree is already up to date with LineageOS."; exit 0; }

info "New LineageOS commits:"
git log --oneline HEAD..FETCH_HEAD
confirm "Replay your commits on top of them?" || exit 1

if ! git rebase FETCH_HEAD; then
    git rebase --abort
    die "Rebase conflict (LineageOS changed the same lines). Nothing was changed."
fi

git log --oneline -5
confirm "Push to github.com/$GITHUB_USER/android_device_asus_sake ($TREE_BRANCH)?" || exit 1
git push --force-with-lease "https://github.com/$GITHUB_USER/android_device_asus_sake" "HEAD:refs/heads/$TREE_BRANCH"
info "Done. The next build uses the updated tree."
