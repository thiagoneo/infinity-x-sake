#!/usr/bin/env bash
# Updates the source and reapplies the local patches.
# Usage: bash scripts/sync.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[ -d "$SRC/.repo" ] || die "Source not found at $SRC (set SRC in config.sh)"
[ "$GITHUB_USER" != "YOUR_USER" ] || die "Set GITHUB_USER in config.sh"

cd "$SRC"

# 1. Local manifests, generated from the templates with the config.sh values:
#    sake.xml.in (device) and, if present, sake-microg.xml.in (local)
mkdir -p .repo/local_manifests
for t in sake sake-microg; do
    rm -f ".repo/local_manifests/$t.xml"   # remove old link/copy
    [ -f "$PORT/local_manifests/$t.xml.in" ] || continue
    sed -e "s/@GITHUB_USER@/$GITHUB_USER/" -e "s/@TREE_BRANCH@/$TREE_BRANCH/" \
        "$PORT/local_manifests/$t.xml.in" > ".repo/local_manifests/$t.xml"
done

# 2. Sync
info "repo sync"
repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j"$SYNC_JOBS"

# 3. Global patches from patches/ (the sync undoes them; reapply only what is missing).
#    The ones in variants/ are applied by build.sh, depending on the variant.
apply_patch() {   # $1 = project, $2 = patch
    local name="${2#"$PORT/patches/"}"
    if patch_applied "$1" "$2"; then
        info "already applied: $name"
        return
    fi
    info "applying:        $name"
    if ! git -C "$1" am --3way -q "$2"; then
        git -C "$1" am --abort || true
        die "Patch $name no longer applies (the project changed in the sync). See the error above."
    fi
}
for_each_patch apply_patch

# 4. Is the sake tree your fork?
[ -f device/asus/sake/infinity_sake.mk ] && [ -f device/asus/sake/lowmem.mk ] \
    || die "device/asus/sake has no infinity_sake.mk/lowmem.mk. Does sake.xml point to your fork?"

# 5. Did LineageOS update the sake tree? (warning only)
ensure_full_history device/asus/sake "https://github.com/$GITHUB_USER/android_device_asus_sake" "$TREE_BRANCH"
if git -C device/asus/sake fetch -q "$UPSTREAM_URL" "$UPSTREAM_BRANCH" 2>/dev/null; then
    n=$(git -C device/asus/sake rev-list --count HEAD..FETCH_HEAD)
    [ "$n" -gt 0 ] && warn "LineageOS has $n new commit(s) in the sake tree. Run: bash scripts/update-tree.sh"
fi

info "Sync done. Next step: bash scripts/build.sh"
