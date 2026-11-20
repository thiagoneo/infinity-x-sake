#!/usr/bin/env bash
# Port cleanup: old zips, old builds/ and logs/, ccache and, optionally,
# git gc of the source and btrfs (snapper) snapshots.
# Each step shows what it will delete and asks for confirmation.
#
# Usage: bash scripts/cleanup.sh [--gc] [--snapshots]
#   --gc         git gc on every project of the source (slow, frees a few GB)
#   --snapshots  deletes old snapper snapshots that contain the port folders
set -euo pipefail
source "$(dirname "$0")/lib.sh"

DO_GC=false
DO_SNAP=false
for a in "$@"; do
    case "$a" in
        --gc)        DO_GC=true ;;
        --snapshots) DO_SNAP=true ;;
        *) die "Unknown option: $a (use --gc and/or --snapshots)" ;;
    esac
done

show_free() { df -h --output=avail,target "$SRC" | tail -1; }
info "Free before: $(show_free)"

# ---------- 1. Old zips in out/ ----------
OUTDIR="$SRC/out/target/product/sake"
if [ -d "$OUTDIR" ]; then
    mapfile -t old_zips < <(ls -1t "$OUTDIR"/Project_Infinity-X-*.zip 2>/dev/null | tail -n +2)
    if [ "${#old_zips[@]}" -gt 0 ]; then
        info "Old zips in out/ (the newest is kept):"
        printf '    %s\n' "${old_zips[@]}"
        confirm "Delete?" && rm -f -- "${old_zips[@]}"
    fi
fi

# ---------- 2. Old builds/ ----------
if [ -d "$PORT/builds" ]; then
    mapfile -t old_builds < <(ls -1d "$PORT"/builds/*/ 2>/dev/null | sort | head -n -"$KEEP_BUILDS")
    if [ "${#old_builds[@]}" -gt 0 ]; then
        info "Old builds (the $KEEP_BUILDS newest are kept):"
        printf '    %s\n' "${old_builds[@]}"
        confirm "Delete?" && rm -rf -- "${old_builds[@]}"
    fi
fi

# ---------- 3. Old logs/ ----------
if [ -d "$PORT/logs" ]; then
    mapfile -t old_logs < <(find "$PORT/logs" -type f -mtime +"$KEEP_LOG_DAYS")
    if [ "${#old_logs[@]}" -gt 0 ]; then
        info "${#old_logs[@]} log(s) older than $KEEP_LOG_DAYS days"
        confirm "Delete?" && rm -f -- "${old_logs[@]}"
    fi
fi

# ---------- 4. ccache: trim to the configured limit ----------
if command -v ccache >/dev/null && [ -d "$CCACHE_DIR" ]; then
    info "ccache: trimming to the $CCACHE_SIZE limit"
    CCACHE_DIR="$CCACHE_DIR" ccache -M "$CCACHE_SIZE" >/dev/null
    CCACHE_DIR="$CCACHE_DIR" ccache -c >/dev/null
fi

# ---------- 5. git gc on the source (optional) ----------
if [ "$DO_GC" = true ]; then
    info "git gc on every project (may take a long time)"
    confirm "Continue?" && (cd "$SRC" && repo forall -c 'git gc --prune=now -q')
fi

# ---------- 6. btrfs snapshots (optional) ----------
# A deleted file keeps using space while a snapshot containing it exists.
# Only snapper configs whose subvolume is the same as one of the port folders
# are considered (comparing the subvolume ID, not the path).
if [ "$DO_SNAP" = true ]; then
    command -v snapper >/dev/null || die "snapper is not installed"

    paths=("$PORT/builds" "$PORT/logs" "$SRC" "$SRC/out" "$CCACHE_DIR")
    declare -A path_ids=()
    for p in "${paths[@]}"; do
        [ -e "$p" ] || continue
        id=$(sudo btrfs inspect-internal rootid "$p" 2>/dev/null) || continue
        path_ids[$id]+="$p "
    done

    found=false
    builds_in_snapshots=false
    while IFS=, read -r conf subvol; do
        [ -n "$conf" ] || continue
        sid=$(sudo btrfs inspect-internal rootid "$subvol" 2>/dev/null) || continue
        [ -n "${path_ids[$sid]:-}" ] || continue
        found=true
        [[ "${path_ids[$sid]}" == *"$PORT/builds "* ]] && builds_in_snapshots=true

        info "Config '$conf' ($subvol) contains: ${path_ids[$sid]}"
        # Snapshot numbers (without 0, the current system), oldest to newest
        mapfile -t nums < <(sudo snapper --csvout -c "$conf" list --columns number \
                            | tail -n +2 | grep -vx 0 | sort -n)
        mapfile -t to_del < <(printf '%s\n' "${nums[@]}" | head -n -"$KEEP_SNAPSHOTS")
        if [ "${#to_del[@]}" -eq 0 ] || [ -z "${to_del[0]}" ]; then
            info "  Nothing to delete (the $KEEP_SNAPSHOTS newest are kept)"
            continue
        fi
        sudo snapper -c "$conf" list | grep -E "^ *($(IFS='|'; echo "${to_del[*]}")) " || true
        confirm "Delete ${#to_del[@]} snapshot(s) of '$conf' (the $KEEP_SNAPSHOTS newest are kept)?" \
            && sudo snapper -c "$conf" delete --sync "${to_del[@]}"
    done < <(sudo snapper --csvout list-configs --columns config,subvolume | tail -n +2)

    if [ "$found" = false ]; then
        info "No snapper snapshot contains the port folders."
    elif [ "$builds_in_snapshots" = true ]; then
        warn "builds/ is inside a subvolume with snapshots. To keep it out of them for good, see the README (\"Keeping builds/ out of snapshots\")."
    fi
fi

info "Free after: $(show_free)"
