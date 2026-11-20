# Shared functions for the scripts. Loaded with: source "$(dirname "$0")/lib.sh"

PORT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PORT/config.sh"
if [ -f "$PORT/config.local.sh" ]; then
    source "$PORT/config.local.sh"
fi

die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }
warn() { printf '[WARN]  %s\n' "$*" >&2; }
info() { printf '==> %s\n' "$*"; }

# Subject ("Subject:" line) of a .patch file. git wraps long subjects over
# several lines (continuation lines start with a space).
patch_subject() {
    awk '/^Subject: / {
             s = $0
             while ((getline l) > 0 && l ~ /^ /) s = s l
             sub(/^Subject: \[PATCH[^]]*\] /, "", s)
             print s
             exit
         }' "$1"
}

# Is the patch's commit already in the project? (looks for the subject in the last 50 commits)
patch_applied() {   # $1 = project directory, $2 = .patch file
    local subject
    subject="$(patch_subject "$2")"
    git -C "$1" log -n 50 --format=%s | grep -qxF "$subject"
}

# Walks patches/<project path>/*.patch and calls $1 for each one
# with: <project directory> <.patch file>
for_each_patch() {
    local p dir
    while IFS= read -r p; do
        dir="${p#"$PORT/patches/"}"
        dir="$SRC/$(dirname "$dir")"
        "$1" "$dir" "$p"
    done < <(find "$PORT/patches" -name '*.patch' | sort)
}

# ---------- Per-variant patches ----------
# variants/<variant>/patches/<project path>/*.patch only go into that
# variant's build. In the others, the project goes back to the manifest state
# (m/$MANIFEST_BRANCH) + the global patches from patches/, if any.

# Projects (path relative to the source) with patches under $1
patch_projects() {
    local p
    [ -d "$1" ] || return 0
    while IFS= read -r p; do
        p="${p#"$1/"}"
        dirname "$p"
    done < <(find "$1" -name '*.patch') | sort -u
}

# A project's patches under a patch root, in order
patch_files() {   # $1 = root (patches/ or variants/<v>/patches), $2 = project
    [ -d "$1/$2" ] || return 0
    find "$1/$2" -maxdepth 1 -name '*.patch' | sort
}

# Leaves every project that has patches in some variant at exactly:
# manifest commit + global patches + patches of variant $1.
# A project is only touched if its current commits differ from the expected
# ones. The comparison is by content (git patch-id), not by subject: a fixed
# patch with the same subject is reapplied too.
sync_variant_patches() {   # $1 = variant
    local proj dir base want have p
    local -a files
    while IFS= read -r proj; do
        dir="$SRC/$proj"
        base="m/$MANIFEST_BRANCH"
        [ -d "$dir" ] || die "Project $proj (from variants/) does not exist in the source"
        git -C "$dir" rev-parse -q --verify "$base" >/dev/null \
            || die "$proj has no $base ref (check MANIFEST_BRANCH in config.sh)"

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
            info "$proj: already as variant $1 needs"
            continue
        fi
        [ -z "$(git -C "$dir" status --porcelain --untracked-files=no)" ] \
            || die "$proj has uncommitted changes. Sort them out first (git -C $dir status)"
        info "$proj: switching to variant $1 (${#files[@]} patch(es))"
        git -C "$dir" reset -q --hard "$base" || die "Reset of $proj failed"
        for p in "${files[@]}"; do
            if ! git -C "$dir" am -q --3way "$p"; then
                git -C "$dir" am --abort || true
                die "Patch ${p#"$PORT/"} no longer applies to $proj. See the error above."
            fi
        done
    done < <(for d in "$PORT"/variants/*/patches; do patch_projects "$d"; done | sort -u)
}

confirm() {
    local r
    read -r -p "$1 [y/N] " r
    [[ "$r" == [yY] ]]
}

# repo syncs with --depth=1 (last commit only). Comparing with upstream or
# rebasing needs the device tree's full history: fetch it if missing.
ensure_full_history() {   # $1 = project directory, $2 = URL, $3 = branch
    if [ "$(git -C "$1" rev-parse --is-shallow-repository)" = true ]; then
        info "Fetching the full history of ${1#"$SRC/"}"
        git -C "$1" fetch -q --unshallow "$2" "$3"
    fi
}
