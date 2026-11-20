#!/usr/bin/env bash
# Prepares (or reverts) the system to build Android with little RAM.
# Usage: sudo bash lowmem.sh on    -> before the build   (ZRAM_SIZE=24G to change the size)
#        sudo bash lowmem.sh off   -> after the build
set -euo pipefail

ZRAM_SIZE="${ZRAM_SIZE:-16G}"

zram_swaps() {   # zram devices in use as swap
    swapon --show=NAME --noheadings | grep '^/dev/zram' || true
}

case "${1:-}" in
on)
    if [ -n "$(zram_swaps)" ]; then
        echo "zram already active as swap: $(zram_swaps | tr '\n' ' ')"
    else
        # zram: compressed swap in RAM, with higher priority than disk swap
        modprobe zram
        dev=$(zramctl --find --size "$ZRAM_SIZE" --algorithm zstd)
        mkswap "$dev" >/dev/null
        swapon -p 100 "$dev"
    fi

    # With zram, the kernel should prefer swapping pages out (zram is fast)
    # and read one page at a time (page-cluster=0) instead of blocks of 8.
    sysctl -q vm.swappiness=180 vm.page-cluster=0

    # earlyoom kills soong_build at 10% free swap; the kernel's OOM killer
    # remains as the last line of defense.
    systemctl stop earlyoom 2>/dev/null || true

    swapon --show
    free -h

    # Check the result instead of assuming it worked
    [ -n "$(zram_swaps)" ] || { echo "ERROR: zram did not become active" >&2; exit 1; }
    [ "$(sysctl -n vm.swappiness)" = 180 ] || { echo "ERROR: swappiness was not applied" >&2; exit 1; }
    ! systemctl is-active -q earlyoom || { echo "ERROR: earlyoom is still active" >&2; exit 1; }
    echo "OK: low-memory mode active"
    ;;
off)
    # Undo any zram in use as swap (not only the one created by this script)
    for d in $(zram_swaps); do
        swapoff "$d"
        zramctl --reset "$d"
    done
    modprobe -r zram 2>/dev/null || true
    sysctl -q vm.swappiness=60 vm.page-cluster=3
    systemctl start earlyoom 2>/dev/null || true
    swapon --show
    ;;
*)
    echo "Usage: sudo bash $0 on|off" >&2
    exit 1
    ;;
esac
