# Infinity X for the Zenfone 8 (sake)

Scripts and patches to build [Project Infinity X](https://github.com/ProjectInfinity-X)
(Android 17) for the ASUS Zenfone 8 (`sake`, `ASUS_I006D`), based on the
LineageOS 24.0 device tree. Unofficial build.

Two variants, both with Infinity X left as is (only what the device needs):

| Variant | What it is |
|---|---|
| `vanilla` | Infinity X without Google (`WITH_GAPPS=false`) |
| `gapps` | Infinity X with the Google apps (`WITH_GAPPS=true`, `vendor/pixel/gms`) |

## Changes from LineageOS

The device tree is a fork of
[LineageOS/android_device_asus_sake](https://github.com/LineageOS/android_device_asus_sake)
with 4 commits, on the `17` branch of
[thiagoneo/android_device_asus_sake](https://github.com/thiagoneo/android_device_asus_sake)
(the same commits are in `device-tree/`):

1. Infinity X bring-up (`infinity_sake.mk`, "About phone" info);
2. `armv8-2a` for the second arch (required by the Infinity build);
3. optional configuration to build with little RAM (`lowmem.mk`);
4. the variant (with or without Google) is chosen at build time.

Kernel and proprietary files are the LineageOS ones
(`LineageOS/android_kernel_asus_sm8350` and `TheMuppets/proprietary_vendor_asus_sake`),
including the firmware (33.0210.0210.296), which is flashed on every install,
as on LineageOS.

## Layout

```
.
├── config.sh                 # paths, GitHub user, -j, limits
├── local_manifests/
│   └── sake.xml.in           # local manifest template (tree + kernel + blobs)
├── patches/                  # patches to source projects (reapplied after sync)
│   └── build/soong/          # passes GOGC on to soong_build (less RAM)
├── device-tree/              # the device tree fork commits
├── scripts/
│   ├── check-build-reqs.sh   # initial machine check
│   ├── sync.sh               # repo sync + reapply patches + checks
│   ├── build.sh              # checks + build + copy artifacts / summarize errors
│   ├── update-tree.sh        # brings LineageOS updates into the fork
│   ├── cleanup.sh            # cleanup: zips, builds/, logs/, ccache, git gc, snapshots
│   └── lowmem.sh             # zram + earlyoom off (on/off, with sudo)
├── builds/YYYY-MM-DD-<variant>/   # zip, boot.img, vendor_boot.img, SHA256SUMS
└── logs/                     # build-*.log and errors-*.txt
```

`patches/<path>/*.patch` is applied to the `<path>` project of the source.
`variants/<variant>/patches/<path>/` (not used in this repository) works the
same way, but only goes into that variant's build.

Personal overrides can go in a `config.local.sh` (not in git), read after
`config.sh`.

## First time

1. Infinity X source (see the project's instructions), in `SRC` from
   `config.sh` (default: `~/android/infinity`):

   ```
   repo init -u https://github.com/ProjectInfinity-X/manifest -b 17 --git-lfs --depth=1
   ```

2. `bash scripts/check-build-reqs.sh` to check the machine.
3. `bash scripts/sync.sh` (generates the local manifest, syncs and applies the patches).

To use your own fork of the tree: fork the LineageOS one, apply the commits
from `device-tree/` on a `17` branch and change `GITHUB_USER` in `config.sh`.

## Build routine

With ~16 GB of RAM, build outside the graphical session (TTY, Ctrl+Alt+F3), in bash:

```
sudo systemctl isolate multi-user.target
sudo ZRAM_SIZE=24G bash scripts/lowmem.sh on
tmux new -s build
bash scripts/sync.sh
bash scripts/build.sh vanilla     # or: gapps
```

Afterwards:

```
sudo bash scripts/lowmem.sh off
sudo systemctl isolate graphical.target
```

If the build fails, the summary is in `logs/errors-*.txt`. Just run
`bash scripts/build.sh` again (no sync): whatever was already built is reused.

- After `lunch`, `build.sh` checks the variant's packages (no Google on
  vanilla, Play Store on gapps).
- The variants share the same `out/`. When switching variants, `build.sh` runs
  `m installclean` and Soong redoes its analysis: expect ~1–1.5 h more.
- `LOWMEM=true` (`config.sh`) enables `lowmem.mk`, `GOGC=30` and
  `ALLOW_MISSING_DEPENDENCIES`. With 32 GB of RAM or more, use `LOWMEM=false`.

## Installation

First time (or when switching variants, which needs a data format):

1. `fastboot flash vendor_boot vendor_boot.img` and `fastboot flash boot boot.img`
   (the recovery is in `boot.img`);
2. in recovery: *Apply update* → *Apply from ADB*, `adb sideload <zip>`;
3. *Format data / factory reset*.

Updates within the same variant: Updater app → ⋮ → *Local update*, picking the
zip (keeps your data).

Switching between vanilla and gapps requires formatting data.

## When LineageOS updates the sake tree

`sync.sh` warns about it. Then run `bash scripts/update-tree.sh`: it rebases
the commits onto upstream and pushes to the fork. On a conflict, it undoes
everything.

## Cleanup

```
bash scripts/cleanup.sh                 # old zips, old builds/ and logs/, ccache
bash scripts/cleanup.sh --gc            # + git gc on the source (slow)
bash scripts/cleanup.sh --snapshots     # + snapper snapshots that contain the port folders
```

Each step shows what it will delete and asks for confirmation. Amounts are set
in `config.sh` (`KEEP_BUILDS`, `KEEP_LOG_DAYS`, `KEEP_SNAPSHOTS`).

### Keeping builds/ out of snapshots

On btrfs, snapshots of a subvolume do not include nested subvolumes. Turning
`builds/` into its own subvolume keeps the zips out of the snapshots:

```
mv builds builds.old
btrfs subvolume create builds
mv builds.old/* builds/ && rmdir builds.old
```

## Notes

- If a patch no longer applies after a sync, the script stops with an error and
  leaves nothing half-done.
- Builds are signed with the AOSP test-keys.
