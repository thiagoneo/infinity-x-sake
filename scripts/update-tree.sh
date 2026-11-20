#!/usr/bin/env bash
# Traz as atualizações do LineageOS para a árvore do sake no seu fork:
# reaplica os seus commits por cima do upstream (rebase) e envia ao GitHub.
# Uso: bash scripts/update-tree.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

TREE="$SRC/device/asus/sake"
cd "$TREE"

[ -z "$(git status --porcelain)" ] || die "Há alterações não commitadas em $TREE"

ensure_full_history "$TREE" "https://github.com/$GITHUB_USER/android_device_asus_sake" "$TREE_BRANCH"
git fetch -q "$UPSTREAM_URL" "$UPSTREAM_BRANCH"
n=$(git rev-list --count HEAD..FETCH_HEAD)
[ "$n" -gt 0 ] || { info "Árvore já está em dia com o LineageOS."; exit 0; }

info "Commits novos do LineageOS:"
git log --oneline HEAD..FETCH_HEAD
confirm "Reaplicar os seus commits por cima deles?" || exit 1

if ! git rebase FETCH_HEAD; then
    git rebase --abort
    die "Conflito no rebase (o LineageOS mexeu nas mesmas linhas). Nada foi alterado."
fi

git log --oneline -5
confirm "Enviar para github.com/$GITHUB_USER/android_device_asus_sake ($TREE_BRANCH)?" || exit 1
git push --force-with-lease "https://github.com/$GITHUB_USER/android_device_asus_sake" "HEAD:refs/heads/$TREE_BRANCH"
info "Pronto. A próxima build usa a árvore atualizada."
