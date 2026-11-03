# sbx-config

Configuration for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)
(`sbx`), which run coding agents in an isolated microVM: a hardened
baseline for sbx settings and network policy, and templates.

## Hardened baseline

Agents in these sandboxes run without permission prompts, so the
sandbox is the only boundary. [`policy/`](policy/) describes what still
crosses it and locks it down: sbx defaults that reach back to the host
(SSH agent, host browser, shared skills store, unsigned kits), a
`deny-all` network policy with per-template allowlists, clone mode so
agents never write to your checkout, and narrow credentials. Run
`policy/apply.sh --dry-run` to see what it would change.

## Usage

[`bin/sbx-claude`](bin/sbx-claude) starts Claude for the repository
you're in, following the baseline:

    cd ~/src/project
    sbx-claude                       # create or resume the sandbox for this repo
    sbx-claude ~/src/other           # same for another directory
    sbx-claude -- --cpus 4 --memory 8g   # extra `sbx run` flags on creation
    sbx-claude --direct              # mount read-write instead of cloning
    sbx-claude --dry-run             # print the sbx command instead

The workspace is the Git repository root. If a sandbox already uses it,
it's resumed whatever its name; otherwise a new one named
`claude-<repo>` is created in clone mode from the `claude-nix` template
(`SBX_CLAUDE_TEMPLATE` picks another). Outside a Git repository it
refuses unless you pass `--direct`. It needs `jq`.

Put it on your `PATH`, optionally with a short alias:

    ln -s ~/git/sbx-config/bin/sbx-claude ~/.local/bin/
    alias sc=sbx-claude              # in ~/.bashrc

With home-manager, package it instead, which also runs shellcheck at
build time:

```nix
# sbx-config: this repository as a flake input (flake = false)
home.packages = [
  (pkgs.writeShellApplication {
    name = "sbx-claude";
    runtimeInputs = [ pkgs.jq pkgs.git ];   # sbx comes from your PATH
    text = builtins.readFile "${sbx-config}/bin/sbx-claude";
  })
];
home.shellAliases.sc = "sbx-claude";
```

## Templates

| Template | What it adds |
|---|---|
| [`claude-nix`](claude-nix/) | Claude Code with single-user Nix (flakes), direnv and nix-direnv: a project's `use flake` dev shell is on `PATH` for every command Claude runs. |

## Maintenance

Everything a build pulls in is pinned, and
[Renovate](https://docs.renovatebot.com/) (the hosted Mend app,
configured in [`.github/renovate.json5`](.github/renovate.json5))
keeps the pins current:

| Pin | Where | Tracked as | PRs | Automerge |
|---|---|---|---|---|
| Base image digest | `ARG BASE_IMAGE` | Docker digest (custom regex manager) | Mondays | yes |
| nixpkgs revision | `ARG NIXPKGS_REV` | head of `nixpkgs-unstable` (custom regex manager) | Mondays | yes |
| Nix release | `ARG NIX_VERSION` | `NixOS/nix` tags (`customManagers:dockerfileVersions`) | 3 days after release | patch only |
| Dockerfile frontend | `# syntax=` line | Docker digest | any time | yes |
| GitHub Actions | workflows | commit SHA + version comment | Mondays, grouped | digest/patch |
| Renovate (config validator) | `RENOVATE_VERSION` in the validator workflow | npm (`customManagers:githubActionsVersions`) | 3 days after release | minor/patch |

The config extends `config:best-practices`. Release-based updates wait
3 days (`minimumReleaseAge`) so a bad release can be yanked first;
digests and nixpkgs commits have no release dates, so they don't wait.
Pending updates are listed in the Dependency Dashboard issue.

To track a new pin, put a `# renovate:` comment directly above its
`ARG`, in one of the forms the Dockerfile already uses:

    # renovate: datasource=github-tags depName=owner/repo
    ARG FOO_VERSION=1.2.3

    # renovate: datasource=docker
    ARG FOO_IMAGE=registry/image:tag@sha256:...

    # renovate: datasource=git-refs depName=name packageName=https://github.com/owner/repo branch=main
    ARG FOO_REV=<40-char commit>

Version ARGs must end in `_VERSION` to match the preset.

### Checks

A ruleset on `main` requires two checks before anything merges, which
is what makes automerge safe:

- **`claude-nix`** ([build.yml](.github/workflows/build.yml)): builds
  the image and runs [`claude-nix/test/smoke.sh`](claude-nix/test/smoke.sh)
  in it. The image is never pushed.
- **`Renovate Config`**
  ([renovate-config.yml](.github/workflows/renovate-config.yml)):
  `renovate-config-validator --strict`.

Repository admins can bypass the ruleset and push to `main` directly.
Renovate merges through GitHub auto-merge, which must stay enabled in
the repository settings.

## License

[Apache-2.0](LICENSE)
