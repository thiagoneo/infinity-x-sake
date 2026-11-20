#!/usr/bin/env bash
# Prepara (ou desfaz) o sistema para compilar o Android com pouca RAM.
# Uso: sudo bash lowmem.sh on    -> antes da build   (ZRAM_SIZE=24G para mudar o tamanho)
#      sudo bash lowmem.sh off   -> depois da build
set -euo pipefail

ZRAM_SIZE="${ZRAM_SIZE:-16G}"

zram_swaps() {   # dispositivos zram em uso como swap
    swapon --show=NAME --noheadings | grep '^/dev/zram' || true
}

case "${1:-}" in
on)
    if [ -n "$(zram_swaps)" ]; then
        echo "zram já ativo como swap: $(zram_swaps | tr '\n' ' ')"
    else
        # zram: swap comprimido na RAM, com prioridade acima do swap em disco
        modprobe zram
        dev=$(zramctl --find --size "$ZRAM_SIZE" --algorithm zstd)
        mkswap "$dev" >/dev/null
        swapon -p 100 "$dev"
    fi

    # Com zram, o kernel deve preferir mandar páginas para o swap (zram é rápido)
    # e ler uma página por vez (page-cluster=0), em vez de blocos de 8.
    sysctl -q vm.swappiness=180 vm.page-cluster=0

    # earlyoom mata o soong_build com 10% de swap livre; o OOM killer do kernel
    # continua como última proteção.
    systemctl stop earlyoom 2>/dev/null || true

    swapon --show
    free -h

    # Confere o resultado em vez de confiar que deu certo
    [ -n "$(zram_swaps)" ] || { echo "ERRO: zram não ficou ativo" >&2; exit 1; }
    [ "$(sysctl -n vm.swappiness)" = 180 ] || { echo "ERRO: swappiness não foi aplicado" >&2; exit 1; }
    ! systemctl is-active -q earlyoom || { echo "ERRO: earlyoom continua ativo" >&2; exit 1; }
    echo "OK: modo de pouca memória ativo"
    ;;
off)
    # Desfaz qualquer zram em uso como swap (não só o criado por este script)
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
    echo "Uso: sudo bash $0 on|off" >&2
    exit 1
    ;;
esac
