# claude-nix sbx template

Claude Code in Docker Sandboxes with single-user Nix (flakes enabled),
direnv and nix-direnv. If a project has `.envrc` containing `use flake`,
its dev shell is loaded before every command Claude runs.

## Build

    ./build.sh                     # docker or podman → sbx template load

Requires [`sbx`](https://docs.docker.com/ai/sandboxes/) and docker or
podman (`ENGINE=docker|podman` to choose). `build.sh` loads only the
image it just built into sbx and stops if the tag points elsewhere.

The base image (by digest), the Nix release and the nixpkgs revision
are pinned in the Dockerfile and kept current by Renovate (see the
[repository README](../README.md#maintenance)), so a plain `./build.sh`
is reproducible. To try other versions locally, override them:

    ./build.sh --build-arg BASE_IMAGE=docker.io/docker/sandbox-templates:claude-code@sha256:<digest>
    ./build.sh --build-arg NIXPKGS_REV=$(curl -fsSL https://channels.nixos.org/nixpkgs-unstable/git-revision)
    ./build.sh --build-arg NIX_VERSION=<version>

## Test

CI runs [`test/smoke.sh`](test/smoke.sh) in the built image: it checks
the Claude instructions file, builds a flake dev shell and runs a tool
from it in a nested bash, then breaks the flake and expects the
`claude-nix:` warning. To run it locally after `./build.sh` (docker or
podman, same arguments):

    docker run --rm --entrypoint bash -v "$PWD/test:/test:ro" \
      -e BASH_ENV=/etc/sandbox-persistent.sh \
      localhost/claude-nix:latest /test/smoke.sh

## Allow Nix network access (once)

The hosts Nix needs inside the sandbox are listed in
[`policy/allow/claude-nix.txt`](../policy/allow/claude-nix.txt). Add
them, together with the hardened sbx settings, with:

    ../policy/apply.sh

If the global network policy isn't initialized yet, the script tells
you so; start with `sbx policy init deny-all` (or `balanced`). See the
[policy README](../policy/README.md) for what the baseline changes and
why.

## Authenticate Claude

**Work: use an API key stored as an sbx secret.** The sbx proxy adds
the key to API requests on the host side, so it never enters the
sandbox, where any code Claude runs (a flake, a build script) could
read it. It applies to all sandboxes and survives `sbx rm`:

    sbx secret set anthropic                          # prompts for the key
    sbx secret set anthropic --command '<fetch-key>'  # or fetch it on the host

Set it before `sbx run`; restart an already running sandbox
(`sbx stop <name>`, then `sbx run …`) so the proxy picks it up.

**Personal Pro/Max account: run `/login` inside the session.** Usage
counts against your plan instead of per-token billing, but the login
token is stored inside the sandbox (readable by code running there)
and is lost on `sbx rm`, so you log in again for each new sandbox.
The login needs the host browser, which the hardened baseline turns
off; enable it just for the login:

    sbx settings set browser.enabled true    # then /login in the sandbox
    sbx settings set browser.enabled false

Keep such sandboxes short-lived, and prefer an API key for work or
shared accounts.

## Run

Claude runs without permission prompts in the sandbox, so use clone
mode: your repository is mounted read-only, Claude commits to a clone
inside the sandbox, and you fetch and review its work before it reaches
your checkout (see [Work in clone mode](../policy/README.md#work-in-clone-mode)):

    cd ~/src/project
    sbx run --clone --name project --pull never --template localhost/claude-nix:latest claude .
    git fetch sandbox-project                # on the host, when Claude has committed

Drop `--clone` only when you need Claude's edits live in your working
tree; then check `.git/hooks` and `.claude/` afterwards.

`--template` only applies when creating a sandbox. Resume an existing
one (keeping its `/login` and dev-shell cache) by name:

    sbx run --name <name>

A sandbox keeps the image it was created from; after a rebuild,
`sbx rm <name>` and create it again to pick up the new template.

## In the sandbox

- `sandbox-CLAUDE.md` is installed as `/etc/claude-code/CLAUDE.md`, so
  Claude knows the dev shell loads automatically and doesn't reach for
  `nix develop`. (It isn't named `CLAUDE.md` here so it doesn't apply to
  sessions editing this template on the host.)
- Changes to the flake take effect on Claude's next command; no
  restart or `direnv reload` needed. The dev shell is evaluated once per
  command (nix-direnv's cache keeps that to a fraction of a second, and
  the first command after a change may build), and nested shells reuse
  it.
- If the flake fails to evaluate, nix-direnv silently falls back to the
  previous dev shell. `env.sh` detects that and prints a `claude-nix:`
  warning with the Nix error before the command's output, once per
  command, so a broken flake doesn't look like "command not found".

## Security model

The Docker Sandboxes microVM is the isolation boundary. Inside it the
template deliberately trades safety checks for convenience, so the
following settings are **only** reasonable there; don't copy them to
your own machine:

- `direnv.toml` whitelists `/`: every `.envrc` runs automatically,
  without `direnv allow`. Opening an untrusted project runs its
  `.envrc` and flake in the sandbox.
- `nix.conf` sets `sandbox = false`, since Nix's build sandbox needs
  user namespaces the microVM may not provide. Builds can see the rest
  of the sandbox filesystem and its network.
- `accept-flake-config = false` stays on, so a flake can't add its own
  substituters or Nix settings.

Anything Claude or a project's code can read inside the sandbox
(including a `/login` token) should be treated as exposed to that
code. Network access is limited by the sbx policy; see the
[hardened baseline](../policy/README.md).

## Verify inside the sandbox

Ask Claude to run `nix --version` and `direnv status`, then
`which <tool>` for a tool that only exists in the project's dev shell.
