#!/usr/bin/env bash
# Compila o Infinity X para o sake, com verificações antes e resumo depois.
# Uso: bash scripts/build.sh [vanilla|gapps|microg]   (padrão: DEFAULT_VARIANT do config.sh)
#
#   vanilla  Infinity X puro, sem Google           (WITH_GAPPS=false)
#   gapps    Infinity X puro, com Google           (WITH_GAPPS=true)
#   microg   vanilla + vendor/extra: microG, F-Droid, Seedvault, Etar e assistente inicial
#            (variante local: precisa de arquivos que não estão neste repositório)
set -uo pipefail
source "$(dirname "$0")/lib.sh"

VARIANT="${1:-$DEFAULT_VARIANT}"
case "$VARIANT" in
    vanilla) WITH_GAPPS=false; WITH_MICROG=false ;;
    gapps)   WITH_GAPPS=true;  WITH_MICROG=false ;;
    microg)  WITH_GAPPS=false; WITH_MICROG=true  ;;
    *) die "Variante desconhecida: $VARIANT (use vanilla, gapps ou microg)" ;;
esac
# Extras do config.local.sh: só valem na variante microg
WITH_JOYPIXELS="${WITH_JOYPIXELS:-false}"
[ "$VARIANT" = microg ] || WITH_JOYPIXELS=false
export WITH_GAPPS WITH_MICROG WITH_JOYPIXELS   # lidos pelo vendor/infinity e pelo vendor/extra

STAMP="$(date +%Y%m%d-%H%M)"
mkdir -p "$PORT/logs" "$PORT/builds"
LOG="$PORT/logs/build-$STAMP-$VARIANT.log"
ERRS="$PORT/logs/errors-$STAMP-$VARIANT.txt"
VARIANT_FILE="$SRC/out/.sake-variant"   # variante da última build neste out/

# ---------- Verificações ----------
info "Variante: $VARIANT"
info "Verificando o ambiente"

[ -f "$SRC/build/envsetup.sh" ] || die "Source não encontrado em $SRC"

check_patch() {
    patch_applied "$1" "$2" || die "Patch não aplicado: ${2#"$PORT/patches/"}. Rode: bash scripts/sync.sh"
}
for_each_patch check_patch

# Firmware .332 (patches/vendor/asus/sake): as imagens não vêm do git
mk="$SRC/vendor/asus/sake/Android.mk"
for img in $(grep -o 'extra/firmware/[a-z_0-9]*\.img' "$mk" 2>/dev/null); do
    [ -s "$PORT/vendor-extra/firmware/${img##*/}" ] || die "Falta vendor-extra/firmware/${img##*/}. Rode: bash scripts/get-firmware.sh <zip do .332>"
done

[ -f "$SRC/device/asus/sake/infinity_sake.mk" ] || die "Árvore do sake sem infinity_sake.mk. Rode: bash scripts/sync.sh"
! grep -q "^WITH_GAPPS" "$SRC/device/asus/sake/infinity_sake.mk" \
    || die "A árvore ainda fixa WITH_GAPPS (falta o commit 'Let the build choose the GApps variant')"

case "$VARIANT" in
    gapps)
        [ -d "$SRC/vendor/pixel/gms" ] || die "vendor/pixel/gms não existe. Rode: bash scripts/sync.sh" ;;
    microg)
        [ -d "$SRC/vendor/partner_gms" ] || die "vendor/partner_gms não existe. Rode: bash scripts/sync.sh"
        [ -d "$SRC/packages/apps/Seedvault" ] || die "packages/apps/Seedvault não existe. Rode: bash scripts/sync.sh"
        [ -d "$SRC/packages/apps/SetupWizard" ] || die "packages/apps/SetupWizard não existe. Rode: bash scripts/sync.sh"
        # Sem o signature spoofing do framework, o microG instala mas não funciona
        grep -q "isMicrogSigned" "$SRC/frameworks/base/core/java/com/android/internal/content/MicrogUtils.java" 2>/dev/null \
            || die "frameworks/base sem MicrogUtils.isMicrogSigned (signature spoofing): o microG não funcionaria"
        if [ "$WITH_JOYPIXELS" = true ]; then
            [ -s "$PORT/vendor-extra/joypixels/JoyPixels.ttf" ] \
                || die "WITH_JOYPIXELS=true, mas falta a fonte. Rode: bash scripts/get-joypixels.sh (ou ponha WITH_JOYPIXELS=false no config.sh)"
        fi ;;
esac

free_gb=$(df -BG --output=avail "$SRC" | tail -1 | tr -dc '0-9')
[ "$free_gb" -ge "$MIN_FREE_GB" ] || die "Só ${free_gb} GB livres em $SRC (mínimo: ${MIN_FREE_GB} GB)"

if [ "$LOWMEM" = true ]; then
    mem_gb=$(awk '/MemTotal|SwapTotal/ {s += $2} END {printf "%d", s/1024/1024}' /proc/meminfo)
    [ "$mem_gb" -ge "$MIN_MEM_GB" ] \
        || die "RAM + swap = ${mem_gb} GB (mínimo: ${MIN_MEM_GB} GB). Rode antes: sudo bash $PORT/scripts/lowmem.sh on"
    # A soma RAM + swap não basta: sem zram e swappiness alto, o kernel descarta
    # o cache de arquivos e a análise do Soong entra em thrashing
    grep -q '^/dev/zram' /proc/swaps \
        || die "zram não está ativo. Rode antes: sudo bash $PORT/scripts/lowmem.sh on"
    [ "$(cat /proc/sys/vm/swappiness)" -ge 100 ] \
        || die "vm.swappiness = $(cat /proc/sys/vm/swappiness) (esperado 180). Rode antes: sudo bash $PORT/scripts/lowmem.sh on"
    ! systemctl is-active -q earlyoom \
        || die "earlyoom está ativo e mataria a análise do Soong. Rode antes: sudo bash $PORT/scripts/lowmem.sh on"
fi

if [ -z "${TMUX:-}" ]; then
    warn "Fora do tmux: se o terminal/SSH cair, a build morre."
    confirm "Continuar mesmo assim?" || exit 1
fi

# ---------- vendor/extra ----------
# Sempre copiado; o product.mk só age com WITH_MICROG=true (nas outras
# variantes ele não adiciona nada).
info "Atualizando vendor/extra"
mkdir -p "$PORT/vendor-extra"   # pode não existir (é local); então vendor/extra fica vazio
rsync -a --delete "$PORT/vendor-extra/" "$SRC/vendor/extra/" || die "Falha ao copiar vendor-extra"

# ---------- Patches por variante ----------
# variants/<variante>/patches: aplicados só nesta variante; nas outras o
# projeto volta ao commit do manifest (vanilla e gapps ficam intactas).
info "Ajustando patches por variante"
sync_variant_patches "$VARIANT"

# ---------- Ambiente da build ----------
ulimit -n 65536

CCACHE_EXEC="$(command -v ccache)" || die "ccache não instalado"
export USE_CCACHE=1 CCACHE_EXEC CCACHE_DIR
mkdir -p "$CCACHE_DIR/tmp"
ccache -o temporary_dir="$CCACHE_DIR/tmp"
ccache -M "$CCACHE_SIZE" >/dev/null

if [ "$LOWMEM" = true ]; then
    export SAKE_LOWMEM_BUILD=true        # ativa device/asus/sake/lowmem.mk
    export ALLOW_MISSING_DEPENDENCIES=true
    export GOGC="${GOGC:-30}"            # precisa do patch em build/soong
fi

cd "$SRC" || die "Não consegui entrar em $SRC"
set +u   # o envsetup.sh do Android não é compatível com "set -u"
source build/envsetup.sh
lunch infinity_sake-userdebug || die "lunch falhou"

# ---------- Verificações depois do lunch ----------
pkgs="$(get_build_var PRODUCT_PACKAGES | tr ' ' '\n')"
has_pkg() { grep -qx "$1" <<<"$pkgs"; }

if [ "$LOWMEM" = true ]; then
    get_build_var PRODUCT_SOURCE_ROOT_DIRS | grep -q -- "-cts/" \
        || die "LOWMEM=true, mas o lowmem.mk não foi aplicado (PRODUCT_SOURCE_ROOT_DIRS sem -cts/)"
fi

case "$VARIANT" in
    vanilla)
        if has_pkg GmsCore || has_pkg Phonesky; then
            die "Variante vanilla, mas há pacotes do Google/microG no produto"
        fi ;;
    gapps)
        has_pkg Phonesky || die "Variante gapps, mas a Play Store (Phonesky) não está no produto"
        ! has_pkg GmsCore || die "Variante gapps, mas o microG (GmsCore) também está no produto" ;;
    microg)
        for p in GmsCore FakeStore GsfProxy FDroid Seedvault Etar LineageSetupWizard; do
            has_pkg "$p" || die "Variante microg, mas o pacote $p não está no produto"
        done
        ! has_pkg Phonesky || die "Variante microg, mas a Play Store do Google também está no produto"
        # O overlay do vendor/extra precisa vir antes do overlay do Infinity
        # (o primeiro da lista tem prioridade) para o Seedvault ser o backup padrão
        overlays="$(get_build_var PRODUCT_PACKAGE_OVERLAYS | tr ' ' '\n')"
        i_extra=$(grep -nx "vendor/extra/overlay/microg" <<<"$overlays" | cut -d: -f1)
        i_inf=$(grep -nx "vendor/infinity/overlay/common" <<<"$overlays" | cut -d: -f1)
        [ -n "$i_extra" ] && [ -n "$i_inf" ] && [ "$i_extra" -lt "$i_inf" ] \
            || die "O overlay do vendor/extra não tem prioridade sobre o do Infinity (Seedvault não seria o backup padrão)" ;;
esac

# ---------- Troca de variante ----------
# Ao trocar de variante, apaga as imagens e os arquivos instalados da anterior
# (os objetos compilados ficam), para nada de uma variante sobrar na outra.
last="$(cat "$VARIANT_FILE" 2>/dev/null || echo desconhecida)"
if [ "$last" != "$VARIANT" ]; then
    info "Última build neste out/: $last. Rodando 'm installclean' para trocar para $VARIANT"
    m installclean || die "m installclean falhou"
fi
echo "$VARIANT" > "$VARIANT_FILE"

# ---------- Build ----------
info "Compilando (log: $LOG)"
m bacon -j"$JOBS" -k 0 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}

# ---------- Resultado ----------
if [ "$status" -eq 0 ]; then
    zip=$(ls -t out/target/product/sake/Project_Infinity-X-*.zip | head -1)
    name="$(basename "$zip")"
    # O Infinity só conhece GAPPS/VANILLA no nome; na microG, deixa claro na cópia
    [ "$VARIANT" = microg ] && name="${name/VANILLA/MICROG}"
    dest="$PORT/builds/$(date +%F)-$VARIANT"
    mkdir -p "$dest"
    cp -v "$zip" "$dest/$name"
    cp -v out/target/product/sake/{boot,vendor_boot}.img "$dest/"
    (cd "$dest" && sha256sum -- * > SHA256SUMS)
    info "Build OK ($VARIANT). Arquivos em: $dest"
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

printf '\n========== Resumo dos erros (%s) ==========\n' "$ERRS"
cat "$ERRS"
exit 1
