#!/usr/bin/env bash
# Checks the requirements to build Project Infinity X (Android 17)
# Usage: ./check-build-reqs.sh [source-directory]   (default: ~/android/infinity)

DIR="${1:-$HOME/android/infinity}"
mkdir -p "$DIR" 2>/dev/null

ok()   { printf '  [OK]      %s\n' "$1"; }
warn() { printf '  [WARN]    %s\n' "$1"; }
fail() { printf '  [MISSING] %s\n' "$1"; }

echo "== CPU"
threads=$(nproc)
[ "$threads" -ge 8 ] && ok "$threads threads" || warn "$threads threads (the build will be slow)"

echo "== Memory"
ram=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
swap=$(awk '/SwapTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
if   [ "$ram" -ge 32 ]; then ok "RAM: ${ram} GB"
elif [ "$ram" -ge 16 ]; then warn "RAM: ${ram} GB (works with swap/zram and a lower -j)"
else fail "RAM: ${ram} GB (not enough)"; fi
total=$((ram + swap))
[ "$total" -ge 32 ] && ok "RAM + swap: ${total} GB" || warn "RAM + swap: ${total} GB (>= 32 GB recommended)"

echo "== Disk at $DIR"
free=$(df -BG --output=avail "$DIR" | tail -1 | tr -dc '0-9')
if   [ "$free" -ge 300 ]; then ok "Free: ${free} GB"
elif [ "$free" -ge 250 ]; then warn "Free: ${free} GB (tight; shrink ccache)"
else fail "Free: ${free} GB (>= 300 GB recommended)"; fi

fs=$(stat -f -c %T "$DIR")
echo "  Filesystem: $fs"
if [ "$fs" = "btrfs" ]; then
    if lsattr -d "$DIR" 2>/dev/null | awk '{print $1}' | grep -q C; then
        ok "btrfs with No_COW (+C) on the directory"
    else
        warn "btrfs without No_COW: run 'chattr +C $DIR' while the directory is still empty"
    fi
fi

echo "== Open file limit"
nofile=$(ulimit -n)
[ "$nofile" -ge 16384 ] && ok "ulimit -n: $nofile" || warn "ulimit -n: $nofile (>= 16384 recommended)"

echo "== Commands"
for c in git git-lfs repo ccache python3 curl zip unzip rsync xz bc bison flex make; do
    command -v "$c" >/dev/null 2>&1 && ok "$c" || fail "$c"
done
git lfs version >/dev/null 2>&1 || warn "git-lfs installed but not initialized? Run 'git lfs install'"
