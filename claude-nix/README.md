# claude-nix sbx template

Claude Code in Docker Sandboxes with single-user Nix (flakes enabled),
direnv and nix-direnv. If a project has `.envrc` containing `use flake`,
its dev shell is loaded before every command Claude runs.

## Build

    ./build.sh                     # docker or podman → sbx template load
    ./build.sh --build-arg BASE_IMAGE=docker.io/docker/sandbox-templates:claude-code@sha256:<digest>
    ./build.sh --build-arg NIXPKGS_REV=$(curl -fsSL https://channels.nixos.org/nixpkgs-unstable/git-revision)

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
Keep such sandboxes short-lived, and don't use this for work.

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

## Verify inside the sandbox

Ask Claude to run `nix --version` and `direnv status`, then
`which <tool>` for a tool that only exists in the project's dev shell.
