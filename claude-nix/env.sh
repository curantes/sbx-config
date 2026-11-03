# Sourced before every shell command Claude runs (CLAUDE_ENV_FILE /
# BASH_ENV). Loads the current directory's .envrc, e.g. `use flake`, so
# the project's dev shell tools are on PATH. nix-direnv caches the
# shell, so only the first command after a flake change is slow.
#
# direnv itself spawns bash, which would source this file again; the
# guard variable prevents recursion.
if [ -z "${CLAUDE_NIX_ENV_LOADING:-}" ] && command -v direnv >/dev/null 2>&1; then
  export CLAUDE_NIX_ENV_LOADING=1
  # Claude Code sources this file several times per command, and the
  # last time is after it restores a shell snapshot taken at session
  # start, which puts back that session's PATH. direnv's state variables
  # survive the restore and claim the current dev shell is loaded, so a
  # plain `direnv export` would be a no-op and tools added to the flake
  # mid-session would stay missing. Drop the state so direnv reapplies
  # the (cached) environment every time.
  unset DIRENV_DIR DIRENV_FILE DIRENV_DIFF DIRENV_WATCHES NIX_DIRENV_DID_FALLBACK
  _claude_nix_err=$(mktemp 2>/dev/null) || _claude_nix_err=/dev/null
  eval "$(direnv export bash 2>"$_claude_nix_err")"
  # `direnv export` exits 0 even when the flake fails to evaluate:
  # nix-direnv falls back to the last good shell (or none) and only sets
  # NIX_DIRENV_DID_FALLBACK. Surface the error so a broken flake doesn't
  # look like "command not found". Shown once per command; the variable
  # is inherited by nested shells.
  if [ -z "${CLAUDE_NIX_ENV_WARNED:-}" ] && [ "$_claude_nix_err" != /dev/null ] &&
     { [ -n "${NIX_DIRENV_DID_FALLBACK:-}" ] || grep -q 'direnv: error' "$_claude_nix_err"; }; then
    export CLAUDE_NIX_ENV_WARNED=1
    {
      echo "claude-nix: loading the dev shell from ${DIRENV_FILE:-.envrc} failed;"
      echo "claude-nix: this command runs with the previous dev shell or none. direnv output:"
      sed -e 's/\x1b\[[0-9;]*m//g' -e '/^direnv: \(loading\|using\) /d' "$_claude_nix_err" | tail -n 40
    } >&2
  fi
  [ "$_claude_nix_err" = /dev/null ] || rm -f "$_claude_nix_err"
  unset CLAUDE_NIX_ENV_LOADING _claude_nix_err
fi
