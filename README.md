# sbx-templates

Templates for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)
(`sbx`), which run coding agents in an isolated microVM.

| Template | What it adds |
|---|---|
| [`claude-nix`](claude-nix/) | Claude Code with single-user Nix (flakes), direnv and nix-direnv: a project's `use flake` dev shell is on `PATH` for every command Claude runs. |

## Maintenance

[Renovate](https://docs.renovatebot.com/) bumps the pinned base image
digest, Nix release and nixpkgs revision (see the `# renovate:`
comments in the Dockerfiles). Every PR builds the images and runs a
smoke test in [CI](.github/workflows/build.yml); no images are
published.

## License

[Apache-2.0](LICENSE)
