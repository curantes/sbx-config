# claude-nix sbx template

Claude Code in Docker Sandboxes with single-user Nix (flakes enabled),
direnv and nix-direnv. If a project has `.envrc` containing `use flake`,
its dev shell is loaded before every command Claude runs.

## Build

    ./build.sh                     # docker or podman → sbx template load
    ./build.sh --build-arg BASE_IMAGE=docker.io/docker/sandbox-templates:claude-code@sha256:<digest>
    ./build.sh --build-arg NIXPKGS_REV=$(curl -fsSL https://channels.nixos.org/nixpkgs-unstable/git-revision)
    ./build.sh --build-arg NIX_VERSION=2.35.4

Requires [`sbx`](https://docs.docker.com/ai/sandboxes/) and docker or
podman (`ENGINE=docker|podman` to choose). `build.sh` loads only the
image it just built into sbx and stops if the tag points elsewhere.

## Allow Nix network access (once)

Initialize the global network policy first (one-time; `sbx policy reset`
starts over), otherwise adding rules fails with `412 Precondition Failed`:

    sbx policy init balanced

Then allow the hosts Nix needs:

    sbx policy allow network "cache.nixos.org:443,channels.nixos.org:443,releases.nixos.org:443,tarballs.nixos.org:443,github.com:443,api.github.com:443,codeload.github.com:443,objects.githubusercontent.com:443"

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
Keep such sandboxes short-lived, and prefer an API key for work or
shared accounts.

## Run

    sbx run --pull never --template localhost/claude-nix:latest claude ~/src/project

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
code. Network access is limited by the sbx policy above.

## Verify inside the sandbox

Ask Claude to run `nix --version` and `direnv status`, then
`which <tool>` for a tool that only exists in the project's dev shell.
