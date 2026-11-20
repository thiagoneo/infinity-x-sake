# Configuração do port Infinity X para o Zenfone 8 (sake).
# Lido por todos os scripts em scripts/. Só variáveis, sem lógica.
# Ajustes pessoais (que não vão para o git) podem ficar em config.local.sh,
# lido logo depois deste arquivo.

# Raiz do source (onde está .repo/)
SRC="$HOME/android/infinity"

# Seu usuário no GitHub (dono do fork da árvore do sake)
GITHUB_USER="thiagoneo"

# Branch do fork com os commits do Infinity
TREE_BRANCH="17"

# Branch do manifest do Infinity (o repo marca a revisão de cada projeto em m/<branch>)
MANIFEST_BRANCH="17"

# Upstream da árvore (para checar se o LineageOS atualizou o sake)
UPSTREAM_URL="https://github.com/LineageOS/android_device_asus_sake"
UPSTREAM_BRANCH="lineage-24.0"

# Build
JOBS=4               # -j da compilação (14 GB de RAM: 4 é seguro)
SYNC_JOBS=6          # -j do repo sync
LOWMEM=true          # ativa lowmem.mk + GOGC=30 + ALLOW_MISSING_DEPENDENCIES
DEFAULT_VARIANT="vanilla"  # vanilla | gapps (build.sh sem argumento)

# ccache
CCACHE_DIR="$HOME/android/ccache"
CCACHE_SIZE="20G"

# Verificações antes da build
MIN_FREE_GB=40       # espaço livre mínimo em $SRC (build incremental)
MIN_MEM_GB=45        # RAM + swap (inclui zram) mínimo com LOWMEM=true

# Limpeza (scripts/cleanup.sh)
KEEP_BUILDS=3        # pastas mantidas em builds/ (as mais recentes)
KEEP_LOG_DAYS=30     # logs/ mais antigos que isso são apagados
KEEP_SNAPSHOTS=2     # snapshots mantidos por config do snapper (os mais recentes)
