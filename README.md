# sbx-config

Configuration for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)
(`sbx`), which run coding agents in an isolated microVM: a hardened
baseline for sbx settings and network policy, and templates.

## Hardened baseline

[`policy/`](policy/) locks down sbx defaults that open paths back to the
host (SSH agent forwarding, the shared skills store, unsigned kits) and
replaces the broad `balanced` network policy with per-template
allowlists. Run `policy/apply.sh --dry-run` to see what it would change.

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
