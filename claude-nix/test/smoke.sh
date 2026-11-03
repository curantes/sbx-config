#!/usr/bin/env bash
# Smoke test run inside the built image by CI:
#   docker run --rm -v "$PWD/claude-nix/test:/test:ro" --entrypoint bash \
#     -e BASH_ENV=/etc/sandbox-persistent.sh claude-nix:ci /test/smoke.sh
set -euo pipefail

grep -q "claude-nix" /etc/claude-code/CLAUDE.md

cd "$(mktemp -d)"
echo "use flake" > .envrc
cat > flake.nix <<'NIX'
{
  inputs.nixpkgs.url = "nixpkgs";
  outputs = { nixpkgs, ... }:
    let pkgs = nixpkgs.legacyPackages.x86_64-linux; in {
      devShells.x86_64-linux.default = pkgs.mkShell { packages = [ pkgs.hello ]; };
    };
}
NIX

# A non-interactive bash gets the dev shell through BASH_ENV.
bash -c 'hello --version' | head -1

# A broken flake must warn, not fail silently. Sleep so the edit is
# newer than the nix-direnv cache.
sleep 1
sed -i 's/pkgs.hello/pkgs.doesNotExist/' flake.nix
bash -c true 2>&1 | tee err.txt | tail -n 3
grep -q '^claude-nix: loading the dev shell' err.txt
grep -q 'doesNotExist' err.txt
echo "smoke test passed"
