# PSTA-env-wrapper

A self-contained bootstrap that takes a machine from **nothing** to a working
**PSTA** path-sensitive typestate analyzer (built on a customized **SVF**) and
runs it on **mp4v2** to look for memory-safety bugs (leak / use-after-free /
double-free).

It clones the three repos, downloads its own toolchain (cmake + LLVM + Z3) into a
local folder, builds everything, validates the tool on known bugs, and — on
request — analyzes mp4v2. **No system packages are installed**; everything lands
under `./work/` (git-ignored). Designed to run on a server where you can't run
Claude Code.

## TL;DR

```bash
git clone git@github.com:1phan/PSTA-env-wrapper.git
cd PSTA-env-wrapper
./bootstrap.sh              # clone + toolchain + build + smoke test  (~25–35 min, ~25 GB)
source env.sh              # put psta + toolchain on PATH
./analyze-mp4v2.sh         # compile mp4v2 -> bitcode and run the detectors
```

## Requirements

- **Linux x86-64**, bash, and these tools on PATH: `git`, `curl` or `wget`, `tar`,
  `xz`, `unzip`, `make`, and a C++ compiler — **gcc/g++ ≥ 8** (for C++17 and the
  matching `std::optional` ABI; see "Why this LLVM" below).
- **git access to the two private source repos** `Mem2019/SemSVF` and
  `Mem2019/PSTA-16-SemSVF` (SSH key or a PAT on the box). `TechSmith/mp4v2` is public.
- **~25–30 GB** free disk and a few GB RAM to build. The whole-program **mp4v2**
  analysis is **memory-hungry** — see "Analyzing mp4v2".
- **`-dev` packages for ncurses, zstd and zlib.** The prebuilt LLVM's CMake
  package (`LLVMConfig.cmake`) runs `find_package(Terminfo)` / `find_package(zstd)`
  / `find_package(ZLIB)`, which need the development files (`libtinfo.so`,
  `libzstd.so`, `zstd.h`, …) — i.e. the `-dev` packages, not just the runtime libs.
  The preflight checks for them (by trying to link, exactly like `find_package`)
  and, if any are missing, stops and prints the install command for your distro:
  ```
  sudo apt-get install -y libtinfo-dev libzstd-dev zlib1g-dev   # Debian/Ubuntu
  sudo dnf install -y ncurses-devel libzstd-devel zlib-devel    # Fedora/RHEL
  ```
  The wrapper installs/ships/fakes **nothing** — it just tells you what to install.

## What you get

```
PSTA-env-wrapper/
├── bootstrap.sh         # preflight → clone → toolchain → build SVF → build PSTA → smoke
├── analyze-mp4v2.sh     # gen mp4v2 bitcode → run detectors
├── env.sh               # config + environment (source to use psta); override vars here
├── scripts/             # the individual, idempotent steps (10..70)
└── work/                # (git-ignored) clones, toolchain, builds, bitcode, reports
```

After `bootstrap.sh`, `psta` lives at `work/PSTA-16-SemSVF/Release-build/bin/psta`
and is on PATH once you `source env.sh`.

## Using psta

`psta` takes **one** LLVM bitcode file plus a detector flag:

```bash
psta -leak  -report=true file.bc      # NeverFree / PartialLeak
psta -df    -report=true file.bc      # DOUBLE_FREE
psta -uaf   -add-uses -report=true file.bc   # USE_AFTER_FREE (needs -add-uses)
```

Bugs print with `{ln,cl,fl}` locations; the stats block ends with `Bug Num <N>`.
The bundled smoke test (`scripts/50-smoke.sh`) asserts one bug of each kind on tiny
programs — it's how you know the build is good.

## Analyzing mp4v2

```bash
./analyze-mp4v2.sh
```
This compiles all ~102 mp4v2 TUs to bitcode, `llvm-link`s them into one
whole-program module (`work/mp4v2/bc-build/mp4v2_mp4info.bc`), and runs the three
detectors. Reports land in `work/reports/`.

**⚠ Memory is the bottleneck.** The path-sensitive solve builds a ~550k-node
value-flow graph; on a 22 GB machine it **OOM-killed at ~10 min**. This is the
main reason to run on a server. Tunables (env vars for `scripts/70-run-mp4v2.sh`):

| Var | Default | Meaning |
|-----|---------|---------|
| `TIMEOUT` | `3600` | per-detector wall-clock cap (seconds) |
| `RSS_CEIL_GB` | `0` (off) | kill psta if its RSS exceeds this (protect the box) |
| `BOUND` | `0` | `1` adds `-layer=2 -src-limit=3 -snk-limit=3` to shrink the solve |
| `DETECTORS` | `leak df uaf` | which detectors to run |

Example for a big-RAM server, capped so it can't take the machine down:
```bash
RSS_CEIL_GB=200 TIMEOUT=7200 ./analyze-mp4v2.sh
```
If it still won't finish, **scope down**: edit the TU list in
`scripts/60-gen-mp4v2-bc.sh` to a cluster of related files — **but keep
`src/mp4util.cpp`** (it holds the `MP4Malloc`/`MP4Free` wrappers); excluding it
severs alloc↔free chains and produces false "never-freed" reports.

## Why this LLVM (the non-obvious part)

The wrapper pins **LLVM 16.0.4, ubuntu-22.04** build. LLVM only ships an
**ubuntu-18.04** build for 16.0.0, compiled with **gcc-7.5 / libstdc++-7**, where
`std::optional<unsigned>` is *not* trivially-copyable and is passed **by memory**.
On a modern host (libstdc++ ≥ 8) your SVF passes it **by value** — that ABI
mismatch makes SVF **segfault inside `llvm::GlobalVariable`'s constructor on every
run**, before any analysis. The ubuntu-22.04 build (gcc-11) passes it by value and
matches. So: any gcc ≥ 8 LLVM-16 works; the stock 16.0.0/18.04 one does not.

Two host-specific gotchas, handled the honest way (**no CMake injection, no fake
libraries**):
- **ncurses/zstd `-dev` packages.** LLVM's `LLVMConfig.cmake` runs
  `find_package(Terminfo)`/`find_package(zstd)` to recreate the `Terminfo::terminfo`
  / `zstd::libzstd_shared` imported targets its `LLVMSupport` export references.
  Those succeed only when the `-dev` packages are installed — so we **require** them
  (see Requirements) and CMake creates the targets itself.
- **`uint64_t` errors building PSTA** are an **upstream bug in `PSTA-16-SemSVF`**:
  a couple of TUs include `<llvm/ADT/SmallVector.h>` before any `<cstdint>`, and
  libstdc++ ≥ 14 no longer provides `uint64_t` transitively. The fix is a one-line
  `#include <cstdint>` in those sources (upstream). It only bites on very new
  toolchains; on libstdc++ < 14 the build is clean.

Build with **gcc** (ABI-matched to the prebuilt LLVM); **clang** from the toolchain
is used only to emit bitcode.

## Customizing

All knobs are at the top of `env.sh` and overridable from the environment, e.g.:
```bash
WORK=/scratch/psta ./bootstrap.sh                 # put everything on a big disk
JOBS=32 ./bootstrap.sh                             # build parallelism
SEMSVF_REF=<sha> PSTA_REF=<sha> ./bootstrap.sh     # different pinned commits
LLVM_PLATFORM=aarch64-linux-gnu ...                # (would need an arm LLVM-16 url)
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| CMake: `target Terminfo::terminfo / zstd::libzstd_shared not found`, or `clang … libtinfo.so.X` | the `-dev` packages aren't installed — `find_package(Terminfo/zstd)` can't find them. Install `libtinfo-dev libzstd-dev zlib1g-dev` (or your distro's equivalents); the preflight checks this up front. |
| SIGSEGV in `removeUnusedExtAPIs` / `GlobalVariable`, no output | wrong LLVM (gcc-7 ABI). Keep `LLVM_PLATFORM=...ubuntu-22.04`. |
| `uint64_t` / `SmallVectorSizeType` errors building PSTA | upstream bug in `PSTA-16-SemSVF` (missing `#include <cstdint>`); only on libstdc++ ≥ 14. Add the include to the failing `.cpp` upstream and re-pin `PSTA_REF`. |
| mp4v2 run prints SVF stats then dies / KILLED | out of memory — more RAM, `BOUND=1`, or scope down (keep `mp4util.cpp`). |
| Private-repo clone fails | the box needs SSH-key/PAT access to the `Mem2019` repos. |

Clean rebuild: `rm -rf work/SemSVF/Release-build work/PSTA-16-SemSVF/Release-build`.
Start fully over: `rm -rf work`.
