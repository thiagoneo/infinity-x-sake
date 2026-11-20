# Infinity X port settings for the Zenfone 8 (sake).
# Read by every script in scripts/. Variables only, no logic.
# Personal overrides (kept out of git) can go in config.local.sh, which is
# read right after this file.

# Source root (where .repo/ is)
SRC="$HOME/android/infinity"

# Your GitHub user (owner of the sake device tree fork)
GITHUB_USER="thiagoneo"

# Fork branch with the Infinity commits
TREE_BRANCH="17"

# Infinity manifest branch (repo tags each project's revision as m/<branch>)
MANIFEST_BRANCH="17"

# Device tree upstream (to check whether LineageOS updated sake)
UPSTREAM_URL="https://github.com/LineageOS/android_device_asus_sake"
UPSTREAM_BRANCH="lineage-24.0"

# Build
JOBS=4               # build -j (4 is safe with 14 GB of RAM)
SYNC_JOBS=6          # repo sync -j
LOWMEM=true          # enables lowmem.mk + GOGC=30 + ALLOW_MISSING_DEPENDENCIES
DEFAULT_VARIANT="vanilla"  # vanilla | gapps (build.sh with no argument)

# ccache
CCACHE_DIR="$HOME/android/ccache"
CCACHE_SIZE="20G"

# Pre-build checks
MIN_FREE_GB=40       # minimum free space in $SRC (incremental build)
MIN_MEM_GB=45        # minimum RAM + swap (zram included) with LOWMEM=true

# Cleanup (scripts/cleanup.sh)
KEEP_BUILDS=3        # folders kept in builds/ (the newest)
KEEP_LOG_DAYS=30     # logs/ older than this are deleted
KEEP_SNAPSHOTS=2     # snapshots kept per snapper config (the newest)
