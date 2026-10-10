#!/bin/sh
# runs inside alpine: musl lets ghc's prebuilt bindist link fully static, so
# nothing has to build ghc. usage: docker run -v "$PWD:/src" -w /src alpine sh ci/build-static.sh
set -eu

apk add --no-cache \
  curl file gcc g++ make musl-dev perl tar xz \
  gmp-dev gmp-static libffi-dev ncurses-dev ncurses-static zlib-dev zlib-static

arch=$(uname -m)

# inside the workspace so the host's actions/cache can keep them
export GHCUP_INSTALL_BASE_PREFIX="$PWD/.ci-cache"
export CABAL_DIR="$PWD/.ci-cache/cabal"
export PATH="$GHCUP_INSTALL_BASE_PREFIX/.ghcup/bin:$PATH"

if ! command -v ghcup >/dev/null; then
  mkdir -p "$GHCUP_INSTALL_BASE_PREFIX/.ghcup/bin"
  curl -fsSL "https://downloads.haskell.org/ghcup/$arch-linux-ghcup" -o "$GHCUP_INSTALL_BASE_PREFIX/.ghcup/bin/ghcup"
  chmod +x "$GHCUP_INSTALL_BASE_PREFIX/.ghcup/bin/ghcup"
fi
ghcup install ghc 9.10.3
ghcup install cabal 3.18.1.0 --set

cabal update
cabal build exe:bad-player --enable-executable-static

out="dist/bad-player-$arch-linux"
mkdir -p dist
cp "$(cabal list-bin exe:bad-player --enable-executable-static)" "$out"
strip "$out"
if ! file "$out" | grep -qE 'statically linked|static-pie linked'; then
  file "$out"
  echo "$out is not statically linked" >&2
  exit 1
fi

# written as root; the host-side cache save and upload run as the runner user
chmod -R a+rX .ci-cache dist
