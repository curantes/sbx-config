# Nix sandbox (claude-nix)

You are in a throwaway Docker sandbox with single-user Nix (flakes
enabled), direnv and nix-direnv.

- If the project has an `.envrc` (usually `use flake`), its dev shell is
  loaded automatically before every shell command. Run tools directly;
  don't wrap commands in `nix develop`, `nix-shell` or `direnv exec`.
- To give the project a tool, add it to the dev shell in `flake.nix`
  (e.g. `packages = [ pkgs.foo ];`). The next command picks it up; the
  first one after a change may take a while to build.
- If the dev shell fails to load, commands print a `claude-nix:` warning
  with the Nix error and run with the previous environment. Fix the
  flake before relying on newly added tools.
- For a one-off tool the project doesn't need, use
  `nix run nixpkgs#foo -- args` or `nix shell nixpkgs#foo -c foo args`.
  `nixpkgs` is pinned to a fixed revision. Prefer Nix over apt-get.
- Network access is limited by the sandbox policy. A download failing
  with a connection or proxy error is most likely blocked by it: report
  the host to the user instead of working around it.
