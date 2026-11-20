#!/usr/bin/env bash
# Limpeza do port: zips antigos, builds/ e logs/ antigos, ccache e,
# opcionalmente, git gc do source e snapshots do btrfs (snapper).
# Cada etapa mostra o que vai apagar e pede confirmação.
#
# Uso: bash scripts/cleanup.sh [--gc] [--snapshots]
#   --gc         git gc em todos os projetos do source (lento, libera alguns GB)
#   --snapshots  apaga snapshots antigos do snapper que contêm as pastas do port
set -euo pipefail
source "$(dirname "$0")/lib.sh"

DO_GC=false
DO_SNAP=false
for a in "$@"; do
    case "$a" in
        --gc)        DO_GC=true ;;
        --snapshots) DO_SNAP=true ;;
        *) die "Opção desconhecida: $a (use --gc e/ou --snapshots)" ;;
    esac
done

show_free() { df -h --output=avail,target "$SRC" | tail -1; }
info "Livre antes: $(show_free)"

# ---------- 1. Zips antigos no out/ ----------
OUTDIR="$SRC/out/target/product/sake"
if [ -d "$OUTDIR" ]; then
    mapfile -t old_zips < <(ls -1t "$OUTDIR"/Project_Infinity-X-*.zip 2>/dev/null | tail -n +2)
    if [ "${#old_zips[@]}" -gt 0 ]; then
        info "Zips antigos no out/ (o mais recente fica):"
        printf '    %s\n' "${old_zips[@]}"
        confirm "Apagar?" && rm -f -- "${old_zips[@]}"
    fi
fi

# ---------- 2. builds/ antigas ----------
if [ -d "$PORT/builds" ]; then
    mapfile -t old_builds < <(ls -1d "$PORT"/builds/*/ 2>/dev/null | sort | head -n -"$KEEP_BUILDS")
    if [ "${#old_builds[@]}" -gt 0 ]; then
        info "Builds antigas (ficam as $KEEP_BUILDS mais recentes):"
        printf '    %s\n' "${old_builds[@]}"
        confirm "Apagar?" && rm -rf -- "${old_builds[@]}"
    fi
fi

# ---------- 3. logs/ antigos ----------
if [ -d "$PORT/logs" ]; then
    mapfile -t old_logs < <(find "$PORT/logs" -type f -mtime +"$KEEP_LOG_DAYS")
    if [ "${#old_logs[@]}" -gt 0 ]; then
        info "${#old_logs[@]} log(s) com mais de $KEEP_LOG_DAYS dias"
        confirm "Apagar?" && rm -f -- "${old_logs[@]}"
    fi
fi

# ---------- 4. ccache: reduz ao limite configurado ----------
if command -v ccache >/dev/null && [ -d "$CCACHE_DIR" ]; then
    info "ccache: limpando até o limite de $CCACHE_SIZE"
    CCACHE_DIR="$CCACHE_DIR" ccache -M "$CCACHE_SIZE" >/dev/null
    CCACHE_DIR="$CCACHE_DIR" ccache -c >/dev/null
fi

# ---------- 5. git gc no source (opcional) ----------
if [ "$DO_GC" = true ]; then
    info "git gc em todos os projetos (pode levar muito tempo)"
    confirm "Continuar?" && (cd "$SRC" && repo forall -c 'git gc --prune=now -q')
fi

# ---------- 6. Snapshots do btrfs (opcional) ----------
# Arquivo apagado continua ocupando espaço enquanto existir um snapshot que o
# contenha. Aqui só entram configs do snapper cujo subvolume é o mesmo de
# alguma pasta do port (comparando o ID do subvolume, não o caminho).
if [ "$DO_SNAP" = true ]; then
    command -v snapper >/dev/null || die "snapper não instalado"

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

        info "Config '$conf' ($subvol) contém: ${path_ids[$sid]}"
        # Números dos snapshots (sem o 0, que é o sistema atual), do mais antigo ao mais novo
        mapfile -t nums < <(sudo snapper --csvout -c "$conf" list --columns number \
                            | tail -n +2 | grep -vx 0 | sort -n)
        mapfile -t to_del < <(printf '%s\n' "${nums[@]}" | head -n -"$KEEP_SNAPSHOTS")
        if [ "${#to_del[@]}" -eq 0 ] || [ -z "${to_del[0]}" ]; then
            info "  Nada a apagar (ficam os $KEEP_SNAPSHOTS mais recentes)"
            continue
        fi
        sudo snapper -c "$conf" list | grep -E "^ *($(IFS='|'; echo "${to_del[*]}")) " || true
        confirm "Apagar ${#to_del[@]} snapshot(s) de '$conf' (ficam os $KEEP_SNAPSHOTS mais recentes)?" \
            && sudo snapper -c "$conf" delete --sync "${to_del[@]}"
    done < <(sudo snapper --csvout list-configs --columns config,subvolume | tail -n +2)

    if [ "$found" = false ]; then
        info "Nenhum snapshot do snapper contém as pastas do port."
    elif [ "$builds_in_snapshots" = true ]; then
        warn "builds/ está dentro de um subvolume com snapshots. Para tirá-la dos snapshots de vez, veja o README (\"builds/ fora dos snapshots\")."
    fi
fi

info "Livre depois: $(show_free)"
