#!/usr/bin/env bash
# Verifica requisitos para compilar o Project Infinity X (Android 17)
# Uso: ./check-build-reqs.sh [diretório-do-source]   (padrão: ~/android/infinity)

DIR="${1:-$HOME/android/infinity}"
mkdir -p "$DIR" 2>/dev/null

ok()   { printf '  [OK]    %s\n' "$1"; }
warn() { printf '  [AVISO] %s\n' "$1"; }
fail() { printf '  [FALTA] %s\n' "$1"; }

echo "== CPU"
threads=$(nproc)
[ "$threads" -ge 8 ] && ok "$threads threads" || warn "$threads threads (build vai ser lenta)"

echo "== Memória"
ram=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
swap=$(awk '/SwapTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
if   [ "$ram" -ge 32 ]; then ok "RAM: ${ram} GB"
elif [ "$ram" -ge 16 ]; then warn "RAM: ${ram} GB (funciona com swap/zram e -j menor)"
else fail "RAM: ${ram} GB (insuficiente)"; fi
total=$((ram + swap))
[ "$total" -ge 32 ] && ok "RAM + swap: ${total} GB" || warn "RAM + swap: ${total} GB (recomendado >= 32 GB)"

echo "== Disco em $DIR"
free=$(df -BG --output=avail "$DIR" | tail -1 | tr -dc '0-9')
if   [ "$free" -ge 300 ]; then ok "Livre: ${free} GB"
elif [ "$free" -ge 250 ]; then warn "Livre: ${free} GB (no limite; reduza o ccache)"
else fail "Livre: ${free} GB (recomendado >= 300 GB)"; fi

fs=$(stat -f -c %T "$DIR")
echo "  Sistema de arquivos: $fs"
if [ "$fs" = "btrfs" ]; then
    if lsattr -d "$DIR" 2>/dev/null | awk '{print $1}' | grep -q C; then
        ok "btrfs com No_COW (+C) no diretório"
    else
        warn "btrfs sem No_COW: rode 'chattr +C $DIR' com o diretório ainda vazio"
    fi
fi

echo "== Limite de arquivos abertos"
nofile=$(ulimit -n)
[ "$nofile" -ge 16384 ] && ok "ulimit -n: $nofile" || warn "ulimit -n: $nofile (recomendado >= 16384)"

echo "== Comandos"
for c in git git-lfs repo ccache python3 curl zip unzip rsync xz bc bison flex make; do
    command -v "$c" >/dev/null 2>&1 && ok "$c" || fail "$c"
done
git lfs version >/dev/null 2>&1 || warn "git-lfs instalado mas não inicializado? rode 'git lfs install'"
