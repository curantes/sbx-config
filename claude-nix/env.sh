# Sourced before every shell command Claude runs (CLAUDE_ENV_FILE /
# BASH_ENV), and by every non-interactive bash those commands start.
# Loads the current directory's .envrc, e.g. `use flake`, so the
# project's dev shell tools are on PATH.
#
# direnv itself spawns bash, which would source this file again; the
# guard variable prevents recursion.
if [ -z "${CLAUDE_NIX_ENV_LOADING:-}" ] && command -v direnv >/dev/null 2>&1; then
  export CLAUDE_NIX_ENV_LOADING=1

  # Claude Code sources this file several times per command. The first
  # time starts without direnv state, so `direnv export` evaluates the
  # .envrc (nix-direnv's cache makes that ~0.2 s). The last time comes
  # after Claude Code restores a shell snapshot from session start,
  # which puts back that session's PATH while direnv's state variables
  # survive, so direnv would think the current dev shell is still
  # loaded. Instead of dropping that state and evaluating again, put
  # back the dev shell's PATH prefix we saved after loading it. The
  # `direnv export` below then only checks that the watched files are
  # unchanged, which is fast, and nested shells inherit the loaded env.
  if [ -n "${DIRENV_DIR:-}" ] && [ -n "${CLAUDE_NIX_PATH_PREFIX:-}" ]; then
    case ":$PATH:" in
      *":$CLAUDE_NIX_PATH_PREFIX:"*) ;;
      *) PATH="$CLAUDE_NIX_PATH_PREFIX${PATH:+:$PATH}" ;;
    esac
  fi

  _claude_nix_before=$PATH
  _claude_nix_err=$(mktemp 2>/dev/null) || _claude_nix_err=/dev/null
  _claude_nix_out=$(direnv export bash 2>"$_claude_nix_err")

  if [ -n "$_claude_nix_out" ]; then
    eval "$_claude_nix_out"
    # Save the entries direnv put in front of PATH: everything before
    # the longest tail it shares with the PATH we started from.
    unset CLAUDE_NIX_PATH_PREFIX
    if [ -n "${DIRENV_DIR:-}" ] && [ "$PATH" != "$_claude_nix_before" ]; then
      _claude_nix_rest=$PATH _claude_nix_pre=
      while [ -n "$_claude_nix_rest" ]; do
        case ":$_claude_nix_before" in *":$_claude_nix_rest") break ;; esac
        case $_claude_nix_rest in
          *:*) _claude_nix_pre=${_claude_nix_pre:+$_claude_nix_pre:}${_claude_nix_rest%%:*}
               _claude_nix_rest=${_claude_nix_rest#*:} ;;
          *)   _claude_nix_pre=${_claude_nix_pre:+$_claude_nix_pre:}$_claude_nix_rest
               _claude_nix_rest= ;;
        esac
      done
      [ -n "$_claude_nix_rest" ] && [ -n "$_claude_nix_pre" ] &&
        export CLAUDE_NIX_PATH_PREFIX=$_claude_nix_pre
    fi

    # `direnv export` exits 0 even when the flake fails to evaluate:
    # nix-direnv falls back to the last good shell (or none) and only
    # sets NIX_DIRENV_DID_FALLBACK. Surface the error so a broken flake
    # doesn't look like "command not found". Shown once per command;
    # the variable is inherited by nested shells.
    if [ -z "${CLAUDE_NIX_ENV_WARNED:-}" ] && [ "$_claude_nix_err" != /dev/null ] &&
       { [ -n "${NIX_DIRENV_DID_FALLBACK:-}" ] || grep -q 'direnv: error' "$_claude_nix_err"; }; then
      export CLAUDE_NIX_ENV_WARNED=1
      {
        echo "claude-nix: loading the dev shell from ${DIRENV_FILE:-.envrc} failed;"
        echo "claude-nix: this command runs with the previous dev shell or none. direnv output:"
        sed -e 's/\x1b\[[0-9;]*m//g' -e '/^direnv: \(loading\|using\) /d' "$_claude_nix_err" | tail -n 40
      } >&2
    fi
  fi

  [ "$_claude_nix_err" = /dev/null ] || rm -f "$_claude_nix_err"
  unset CLAUDE_NIX_ENV_LOADING _claude_nix_before _claude_nix_err _claude_nix_out \
        _claude_nix_rest _claude_nix_pre
fi
