#!/usr/bin/env bash
# Installs the Roblox toolchain on a Linux cloud container whose network allows package
# registries (crates.io, PyPI, apt) and git clones but blocks GitHub release downloads.
# Safe to re-run: tools that are already installed are skipped.
#
#   bash tools/setup-cloud-toolchain.sh            # everything
#   SKIP_BLENDER=1 SKIP_LUAU_LSP=1 bash tools/...  # faster: code tools only
#
# On a local machine use Rokit instead:  rokit install   (reads rokit.toml)
set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"
SELENE_VERSION=0.31.0
LUAU_LSP_REF=${LUAU_LSP_REF:-main}
WORK=${TMPDIR:-/tmp}/roblox-toolchain-build
mkdir -p "$WORK"
have() { command -v "$1" >/dev/null 2>&1; }
log() { printf '\n==> %s\n' "$*"; }

# 1. Rust tools from crates.io (GitHub release binaries are blocked, so build from source).
log "Rust tools (rojo, darklua, lune, wally, stylua)"
for t in rojo darklua lune wally; do have "$t" || cargo install --locked "$t"; done
have stylua || cargo install --locked stylua --features luau

# 2. Selene, patched to trust the system CA store. Stock selene uses ureq with bundled
#    webpki roots, so behind a TLS-inspecting proxy it cannot download the Roblox API dump
#    that `std = "roblox"` needs ("invalid peer certificate: UnknownIssuer").
if ! have selene || ! selene generate-roblox-std >/dev/null 2>&1; then
  log "selene $SELENE_VERSION (ureq native-certs)"
  rm -rf "$WORK/selene-$SELENE_VERSION"
  curl -fsSL "https://static.crates.io/crates/selene/selene-$SELENE_VERSION.crate" | tar -xz -C "$WORK"
  python3 -I - "$WORK/selene-$SELENE_VERSION/Cargo.toml" <<'EOF'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.sub(r'(\[dependencies\.ureq\]\nversion = "[^"]+"\nfeatures = \[)"json"\]',
           r'\1"json", "native-certs"]', t)
if n == t: sys.exit("selene Cargo.toml layout changed; patch not applied")
open(p, "w").write(n)
EOF
  (cd "$WORK/selene-$SELENE_VERSION" && cargo build --release -q)
  install -m 755 "$WORK/selene-$SELENE_VERSION/target/release/selene" "$HOME/.cargo/bin/selene"
fi
# Cache the Roblox standard library (~/.cache/selene/roblox.yml); selene falls back to it offline.
(cd "$WORK" && selene generate-roblox-std >/dev/null && rm -f roblox.yml)

# 3. luau-lsp (type-checks Luau against the Roblox API). Not on crates.io; build with clang,
#    because GCC 13 stops on a -Werror maybe-uninitialized false positive.
if [[ -z ${SKIP_LUAU_LSP:-} ]] && ! have luau-lsp; then
  log "luau-lsp ($LUAU_LSP_REF)"
  rm -rf "$WORK/luau-lsp"
  git clone -q --depth 1 --branch "$LUAU_LSP_REF" --recurse-submodules --shallow-submodules \
    https://github.com/JohnnyMorganz/luau-lsp "$WORK/luau-lsp"
  cmake -S "$WORK/luau-lsp" -B "$WORK/luau-lsp/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ >/dev/null
  cmake --build "$WORK/luau-lsp/build" --target Luau.LanguageServer.CLI -j "$(nproc)" >/dev/null
  install -m 755 "$WORK/luau-lsp/build/luau-lsp" /usr/local/bin/luau-lsp
fi
# Roblox type definitions for `luau-lsp analyze`, at game-script security level ("None"),
# so plugin-only APIs are flagged.
mkdir -p "$HOME/.cache/luau-lsp"
curl -fsSL -o "$HOME/.cache/luau-lsp/globalTypes.d.luau" \
  https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau

# 4. Blender (headless) for the 3D model, animation and Blender skills.
if [[ -z ${SKIP_BLENDER:-} ]] && ! have blender; then
  log "Blender (apt)"
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends blender
fi

# 5. Python packages used by the skill scripts (torch/diffusers are optional and not installed).
log "Python packages"
python3 -m pip install -q --root-user-action=ignore \
  pillow numpy scipy requests opencv-python-headless gradio_client huggingface_hub

log "Versions"
for t in rojo selene stylua darklua lune wally luau-lsp blender; do
  printf '%-9s %s\n' "$t" "$( (have "$t" && "$t" --version 2>/dev/null | head -1) || echo 'not installed')"
done
