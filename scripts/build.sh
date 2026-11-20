#!/usr/bin/env bash
# Builds Infinity X for sake, with checks before and a summary after.
# Usage: bash scripts/build.sh [vanilla|gapps|microg]   (default: DEFAULT_VARIANT from config.sh)
#
#   vanilla  Plain Infinity X, without Google     (WITH_GAPPS=false)
#   gapps    Plain Infinity X, with Google        (WITH_GAPPS=true)
#   microg   vanilla + vendor/extra: microG, F-Droid, Seedvault, Etar and setup wizard
#            (local variant: needs files that are not in this repository)
set -uo pipefail
source "$(dirname "$0")/lib.sh"

VARIANT="${1:-$DEFAULT_VARIANT}"
case "$VARIANT" in
    vanilla) WITH_GAPPS=false; WITH_MICROG=false ;;
    gapps)   WITH_GAPPS=true;  WITH_MICROG=false ;;
    microg)  WITH_GAPPS=false; WITH_MICROG=true  ;;
    *) die "Unknown variant: $VARIANT (use vanilla, gapps or microg)" ;;
esac
# Extras from config.local.sh: only apply to the microg variant
WITH_JOYPIXELS="${WITH_JOYPIXELS:-false}"
[ "$VARIANT" = microg ] || WITH_JOYPIXELS=false
export WITH_GAPPS WITH_MICROG WITH_JOYPIXELS   # read by vendor/infinity and vendor/extra

STAMP="$(date +%Y%m%d-%H%M)"
mkdir -p "$PORT/logs" "$PORT/builds"
LOG="$PORT/logs/build-$STAMP-$VARIANT.log"
ERRS="$PORT/logs/errors-$STAMP-$VARIANT.txt"
VARIANT_FILE="$SRC/out/.sake-variant"   # variant of the last build in this out/

# ---------- Checks ----------
info "Variant: $VARIANT"
info "Checking the environment"

[ -f "$SRC/build/envsetup.sh" ] || die "Source not found at $SRC"

check_patch() {
    patch_applied "$1" "$2" || die "Patch not applied: ${2#"$PORT/patches/"}. Run: bash scripts/sync.sh"
}
for_each_patch check_patch

# Local firmware (patches/vendor/asus/sake): the images do not come from git
mk="$SRC/vendor/asus/sake/Android.mk"
for img in $(grep -o 'extra/firmware/[a-z_0-9]*\.img' "$mk" 2>/dev/null); do
    [ -s "$PORT/vendor-extra/firmware/${img##*/}" ] || die "Missing vendor-extra/firmware/${img##*/}. Run: bash scripts/get-firmware.sh <firmware zip>"
done

[ -f "$SRC/device/asus/sake/infinity_sake.mk" ] || die "sake tree has no infinity_sake.mk. Run: bash scripts/sync.sh"
! grep -q "^WITH_GAPPS" "$SRC/device/asus/sake/infinity_sake.mk" \
    || die "The tree still hardcodes WITH_GAPPS (missing the 'Let the build choose the GApps variant' commit)"

case "$VARIANT" in
    gapps)
        [ -d "$SRC/vendor/pixel/gms" ] || die "vendor/pixel/gms does not exist. Run: bash scripts/sync.sh" ;;
    microg)
        [ -d "$SRC/vendor/partner_gms" ] || die "vendor/partner_gms does not exist. Run: bash scripts/sync.sh"
        [ -d "$SRC/packages/apps/Seedvault" ] || die "packages/apps/Seedvault does not exist. Run: bash scripts/sync.sh"
        [ -d "$SRC/packages/apps/SetupWizard" ] || die "packages/apps/SetupWizard does not exist. Run: bash scripts/sync.sh"
        # Without the framework's signature spoofing, microG installs but does not work
        grep -q "isMicrogSigned" "$SRC/frameworks/base/core/java/com/android/internal/content/MicrogUtils.java" 2>/dev/null \
            || die "frameworks/base lacks MicrogUtils.isMicrogSigned (signature spoofing): microG would not work"
        if [ "$WITH_JOYPIXELS" = true ]; then
            [ -s "$PORT/vendor-extra/joypixels/JoyPixels.ttf" ] \
                || die "WITH_JOYPIXELS=true, but the font is missing. Run: bash scripts/get-joypixels.sh (or set WITH_JOYPIXELS=false in config.local.sh)"
        fi ;;
esac

free_gb=$(df -BG --output=avail "$SRC" | tail -1 | tr -dc '0-9')
[ "$free_gb" -ge "$MIN_FREE_GB" ] || die "Only ${free_gb} GB free in $SRC (minimum: ${MIN_FREE_GB} GB)"

if [ "$LOWMEM" = true ]; then
    mem_gb=$(awk '/MemTotal|SwapTotal/ {s += $2} END {printf "%d", s/1024/1024}' /proc/meminfo)
    [ "$mem_gb" -ge "$MIN_MEM_GB" ] \
        || die "RAM + swap = ${mem_gb} GB (minimum: ${MIN_MEM_GB} GB). Run first: sudo bash $PORT/scripts/lowmem.sh on"
    # RAM + swap alone is not enough: without zram and a high swappiness, the
    # kernel drops the file cache and the Soong analysis starts thrashing
    grep -q '^/dev/zram' /proc/swaps \
        || die "zram is not active. Run first: sudo bash $PORT/scripts/lowmem.sh on"
    [ "$(cat /proc/sys/vm/swappiness)" -ge 100 ] \
        || die "vm.swappiness = $(cat /proc/sys/vm/swappiness) (expected 180). Run first: sudo bash $PORT/scripts/lowmem.sh on"
    ! systemctl is-active -q earlyoom \
        || die "earlyoom is active and would kill the Soong analysis. Run first: sudo bash $PORT/scripts/lowmem.sh on"
fi

if [ -z "${TMUX:-}" ]; then
    warn "Not in tmux: if the terminal/SSH session drops, the build dies."
    confirm "Continue anyway?" || exit 1
fi

# ---------- vendor/extra ----------
# Always copied; product.mk only acts with WITH_MICROG=true (in the other
# variants it adds nothing).
info "Updating vendor/extra"
mkdir -p "$PORT/vendor-extra"   # may not exist (it is local); then vendor/extra stays empty
rsync -a --delete "$PORT/vendor-extra/" "$SRC/vendor/extra/" || die "Failed to copy vendor-extra"

# ---------- Per-variant patches ----------
# variants/<variant>/patches: applied only to this variant; in the others the
# project goes back to the manifest commit (vanilla and gapps stay untouched).
info "Adjusting per-variant patches"
sync_variant_patches "$VARIANT"

# ---------- Build environment ----------
ulimit -n 65536

CCACHE_EXEC="$(command -v ccache)" || die "ccache is not installed"
export USE_CCACHE=1 CCACHE_EXEC CCACHE_DIR
mkdir -p "$CCACHE_DIR/tmp"
ccache -o temporary_dir="$CCACHE_DIR/tmp"
ccache -M "$CCACHE_SIZE" >/dev/null

if [ "$LOWMEM" = true ]; then
    export SAKE_LOWMEM_BUILD=true        # enables device/asus/sake/lowmem.mk
    export ALLOW_MISSING_DEPENDENCIES=true
    export GOGC="${GOGC:-30}"            # needs the build/soong patch
fi

cd "$SRC" || die "Could not cd into $SRC"
set +u   # Android's envsetup.sh does not work with "set -u"
source build/envsetup.sh
lunch infinity_sake-userdebug || die "lunch failed"

# ---------- Post-lunch checks ----------
pkgs="$(get_build_var PRODUCT_PACKAGES | tr ' ' '\n')"
has_pkg() { grep -qx "$1" <<<"$pkgs"; }

if [ "$LOWMEM" = true ]; then
    get_build_var PRODUCT_SOURCE_ROOT_DIRS | grep -q -- "-cts/" \
        || die "LOWMEM=true, but lowmem.mk was not applied (PRODUCT_SOURCE_ROOT_DIRS without -cts/)"
fi

case "$VARIANT" in
    vanilla)
        if has_pkg GmsCore || has_pkg Phonesky; then
            die "vanilla variant, but the product has Google/microG packages"
        fi ;;
    gapps)
        has_pkg Phonesky || die "gapps variant, but the Play Store (Phonesky) is not in the product"
        ! has_pkg GmsCore || die "gapps variant, but microG (GmsCore) is in the product too" ;;
    microg)
        for p in GmsCore FakeStore GsfProxy FDroid Seedvault Etar LineageSetupWizard; do
            has_pkg "$p" || die "microg variant, but package $p is not in the product"
        done
        ! has_pkg Phonesky || die "microg variant, but Google's Play Store is in the product too"
        # The vendor/extra overlay must come before the Infinity overlay (the
        # first one in the list wins) so Seedvault is the default backup
        overlays="$(get_build_var PRODUCT_PACKAGE_OVERLAYS | tr ' ' '\n')"
        i_extra=$(grep -nx "vendor/extra/overlay/microg" <<<"$overlays" | cut -d: -f1)
        i_inf=$(grep -nx "vendor/infinity/overlay/common" <<<"$overlays" | cut -d: -f1)
        [ -n "$i_extra" ] && [ -n "$i_inf" ] && [ "$i_extra" -lt "$i_inf" ] \
            || die "The vendor/extra overlay does not take priority over Infinity's (Seedvault would not be the default backup)" ;;
esac

# ---------- Variant switch ----------
# When the variant changes, delete the previous variant's images and installed
# files (compiled objects stay), so nothing from one variant leaks into another.
last="$(cat "$VARIANT_FILE" 2>/dev/null || echo unknown)"
if [ "$last" != "$VARIANT" ]; then
    info "Last build in this out/: $last. Running 'm installclean' to switch to $VARIANT"
    m installclean || die "m installclean failed"
fi
echo "$VARIANT" > "$VARIANT_FILE"

# ---------- Build ----------
info "Building (log: $LOG)"
m bacon -j"$JOBS" -k 0 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}

# ---------- Result ----------
if [ "$status" -eq 0 ]; then
    zip=$(ls -t out/target/product/sake/Project_Infinity-X-*.zip | head -1)
    name="$(basename "$zip")"
    # Infinity only knows GAPPS/VANILLA in the name; make microG clear in the copy
    [ "$VARIANT" = microg ] && name="${name/VANILLA/MICROG}"
    dest="$PORT/builds/$(date +%F)-$VARIANT"
    mkdir -p "$dest"
    cp -v "$zip" "$dest/$name"
    cp -v out/target/product/sake/{boot,vendor_boot}.img "$dest/"
    (cd "$dest" && sha256sum -- * > SHA256SUMS)
    info "Build OK ($VARIANT). Files in: $dest"
    exit 0
fi

{
    for f in out/soong/siso_output out/siso_output; do
        [ -f "$f" ] || continue
        echo "### $f"
        grep "^FAILED" "$f"
        echo
        grep -oE "missing dependencies: .*" "$f" | sort -u
        grep -E "error:" "$f" | grep -v warning | sort -u | head -50
        echo
    done
} | cut -c1-400 > "$ERRS"

printf '\n========== Error summary (%s) ==========\n' "$ERRS"
cat "$ERRS"
exit 1
