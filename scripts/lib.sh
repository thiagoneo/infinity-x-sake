# Funções comuns aos scripts. Carregado com: source "$(dirname "$0")/lib.sh"

PORT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PORT/config.sh"
if [ -f "$PORT/config.local.sh" ]; then
    source "$PORT/config.local.sh"
fi

die()  { printf '\n[ERRO]  %s\n' "$*" >&2; exit 1; }
warn() { printf '[AVISO] %s\n' "$*" >&2; }
info() { printf '==> %s\n' "$*"; }

# Assunto (linha "Subject:") de um arquivo .patch. O git quebra assuntos
# longos em mais de uma linha (as de continuação começam com espaço).
patch_subject() {
    awk '/^Subject: / {
             s = $0
             while ((getline l) > 0 && l ~ /^ /) s = s l
             sub(/^Subject: \[PATCH[^]]*\] /, "", s)
             print s
             exit
         }' "$1"
}

# O commit do patch já está no projeto? (procura o assunto nos últimos 50 commits)
patch_applied() {   # $1 = diretório do projeto, $2 = arquivo .patch
    local subject
    subject="$(patch_subject "$2")"
    git -C "$1" log -n 50 --format=%s | grep -qxF "$subject"
}

# Percorre patches/<caminho do projeto>/*.patch e chama $1 para cada um
# com: <diretório do projeto> <arquivo .patch>
for_each_patch() {
    local p dir
    while IFS= read -r p; do
        dir="${p#"$PORT/patches/"}"
        dir="$SRC/$(dirname "$dir")"
        "$1" "$dir" "$p"
    done < <(find "$PORT/patches" -name '*.patch' | sort)
}

# ---------- Patches por variante ----------
# variants/<variante>/patches/<caminho do projeto>/*.patch só entram na build
# daquela variante. Nas outras, o projeto volta ao estado do manifest
# (m/$MANIFEST_BRANCH) + os patches globais de patches/, se houver.

# Projetos (caminho relativo ao source) com patches em $1
patch_projects() {
    local p
    [ -d "$1" ] || return 0
    while IFS= read -r p; do
        p="${p#"$1/"}"
        dirname "$p"
    done < <(find "$1" -name '*.patch') | sort -u
}

# Patches de um projeto dentro de uma raiz de patches, em ordem
patch_files() {   # $1 = raiz (patches/ ou variants/<v>/patches), $2 = projeto
    [ -d "$1/$2" ] || return 0
    find "$1/$2" -maxdepth 1 -name '*.patch' | sort
}

# Deixa cada projeto que tem patches de alguma variante exatamente com:
# commit do manifest + patches globais + patches da variante $1.
# Só mexe no projeto se os commits atuais forem diferentes do esperado. A
# comparação é pelo conteúdo (git patch-id), não pelo título: um patch
# corrigido com o mesmo título também é reaplicado.
sync_variant_patches() {   # $1 = variante
    local proj dir base want have p
    local -a files
    while IFS= read -r proj; do
        dir="$SRC/$proj"
        base="m/$MANIFEST_BRANCH"
        [ -d "$dir" ] || die "Projeto $proj (de variants/) não existe no source"
        git -C "$dir" rev-parse -q --verify "$base" >/dev/null \
            || die "$proj não tem a referência $base (confira MANIFEST_BRANCH no config.sh)"

        mapfile -t files < <(patch_files "$PORT/patches" "$proj"; \
                             patch_files "$PORT/variants/$1/patches" "$proj")
        want=""
        for p in "${files[@]}"; do
            want+="$(git -C "$dir" patch-id --stable < "$p" | cut -d' ' -f1)"$'\n'
        done
        want="${want%$'\n'}"
        have="$(git -C "$dir" log --reverse -p "$base..HEAD" \
                | git -C "$dir" patch-id --stable | cut -d' ' -f1)"

        if [ "$want" = "$have" ]; then
            info "$proj: já está como a variante $1 precisa"
            continue
        fi
        [ -z "$(git -C "$dir" status --porcelain --untracked-files=no)" ] \
            || die "$proj tem alterações não commitadas. Resolva antes (git -C $dir status)"
        info "$proj: ajustando para a variante $1 (${#files[@]} patch(es))"
        git -C "$dir" reset -q --hard "$base" || die "Falha no reset de $proj"
        for p in "${files[@]}"; do
            if ! git -C "$dir" am -q --3way "$p"; then
                git -C "$dir" am --abort || true
                die "O patch ${p#"$PORT/"} não encaixa mais em $proj. Me mande o erro acima."
            fi
        done
    done < <(for d in "$PORT"/variants/*/patches; do patch_projects "$d"; done | sort -u)
}

confirm() {
    local r
    read -r -p "$1 [s/N] " r
    [[ "$r" == [sSyY] ]]
}

# O repo baixa com --depth=1 (só o último commit). Comparar com o upstream ou
# fazer rebase precisa do histórico completo da árvore: baixa se faltar.
ensure_full_history() {   # $1 = diretório do projeto, $2 = URL, $3 = branch
    if [ "$(git -C "$1" rev-parse --is-shallow-repository)" = true ]; then
        info "Baixando o histórico completo de ${1#"$SRC/"}"
        git -C "$1" fetch -q --unshallow "$2" "$3"
    fi
}
