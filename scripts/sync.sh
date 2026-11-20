#!/usr/bin/env bash
# Atualiza o source e reaplica os patches locais.
# Uso: bash scripts/sync.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[ -d "$SRC/.repo" ] || die "Source não encontrado em $SRC (ajuste SRC no config.sh)"
[ "$GITHUB_USER" != "SEU_USUARIO" ] || die "Defina GITHUB_USER no config.sh"

cd "$SRC"

# 1. Local manifests, gerados a partir dos modelos com os valores do config.sh:
#    sake.xml.in (aparelho) e, se existir, sake-microg.xml.in (local)
mkdir -p .repo/local_manifests
for t in sake sake-microg; do
    rm -f ".repo/local_manifests/$t.xml"   # remove link/cópia antiga
    [ -f "$PORT/local_manifests/$t.xml.in" ] || continue
    sed -e "s/@GITHUB_USER@/$GITHUB_USER/" -e "s/@TREE_BRANCH@/$TREE_BRANCH/" \
        "$PORT/local_manifests/$t.xml.in" > ".repo/local_manifests/$t.xml"
done

# 2. Sync
info "repo sync"
repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j"$SYNC_JOBS"

# 3. Patches globais de patches/ (o sync desfaz; reaplica só o que falta).
#    Os de variants/ são aplicados pelo build.sh, conforme a variante.
apply_patch() {   # $1 = projeto, $2 = patch
    local name="${2#"$PORT/patches/"}"
    if patch_applied "$1" "$2"; then
        info "já aplicado: $name"
        return
    fi
    info "aplicando:   $name"
    if ! git -C "$1" am --3way -q "$2"; then
        git -C "$1" am --abort || true
        die "O patch $name não encaixa mais (o projeto mudou no sync). Me mande o erro acima."
    fi
}
for_each_patch apply_patch

# 4. Árvore do sake: é a do seu fork?
[ -f device/asus/sake/infinity_sake.mk ] && [ -f device/asus/sake/lowmem.mk ] \
    || die "device/asus/sake não tem infinity_sake.mk/lowmem.mk. O sake.xml aponta para o seu fork?"

# 5. O LineageOS atualizou a árvore do sake? (só avisa)
ensure_full_history device/asus/sake "https://github.com/$GITHUB_USER/android_device_asus_sake" "$TREE_BRANCH"
if git -C device/asus/sake fetch -q "$UPSTREAM_URL" "$UPSTREAM_BRANCH" 2>/dev/null; then
    n=$(git -C device/asus/sake rev-list --count HEAD..FETCH_HEAD)
    [ "$n" -gt 0 ] && warn "O LineageOS tem $n commit(s) novo(s) na árvore do sake. Rode: bash scripts/update-tree.sh"
fi

info "Sync concluído. Próximo passo: bash scripts/build.sh"
