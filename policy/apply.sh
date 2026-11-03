#!/usr/bin/env bash
# Apply the hardened sbx baseline: settings, plus the network allowlist of
# each template. Idempotent: only changes what differs, and prints it.
#
#   policy/apply.sh [--dry-run] [--no-browser] [--allow-local-kits] [TEMPLATE...]
#
# TEMPLATE names a file in policy/allow/ (default: all of them). Switching
# the global policy from `balanced` to `deny-all` is a separate, manual
# step because it needs `sbx policy reset`; see policy/README.md.
set -euo pipefail
cd "$(dirname "$0")"

dry=0 browser=true local_kits=false templates=()
for arg in "$@"; do
  case $arg in
    --dry-run) dry=1 ;;
    --no-browser) browser=false ;;
    --allow-local-kits) local_kits=true ;;
    -h|--help) sed -n '2,10s/^# \{0,1\}//p' "$0"; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) templates+=("$arg") ;;
  esac
done
if [[ ${#templates[@]} -eq 0 ]]; then
  for f in allow/*.txt; do templates+=("$(basename "$f" .txt)"); done
fi

run() {
  if (( dry )); then echo "  would run: $*"; else "$@" >/dev/null; echo "  ran: $*"; fi
}

setting() {
  local key=$1 want=$2 cur
  cur=$(sbx settings get "$key")
  if [[ $cur == "$want" ]]; then
    echo "ok      $key = $want"
  else
    echo "change  $key: ${cur:-<unset>} -> $want"
    run sbx settings set "$key" "$want"
  fi
}

echo "== settings"
# Sandboxes must not sign with the host's SSH keys. Use
# `sbx secret set github` for git over HTTPS instead.
setting ssh.agentForwardingEnabled false
# Don't mount the host's shared agent skills store into sandboxes.
setting skills.defaultMode off
# Kits run their install steps as root: only signed kits from allowed
# remote sources (Docker's own agent kits stay exempt and pinned).
setting kit.requireSignature true
setting kit.allowLocalKits "$local_kits"
# Keep host clipboard and Claude remote control out of reach, and never
# upload diagnostics bundles automatically.
setting clipboard.imagePaste false
setting claude.remoteControl false
setting diagnostics.autoUpload no
# Needed for `/login` (Pro/Max) inside a sandbox; --no-browser turns it
# off when the Anthropic API key is an sbx secret.
setting browser.enabled "$browser"

echo "== network policy"
if [[ -z $(sbx policy ls --source local -q 2>/dev/null) ]]; then
  echo "The global network policy isn't initialized. Run one of:" >&2
  echo "  sbx policy init deny-all   # recommended, see policy/README.md" >&2
  echo "  sbx policy init balanced" >&2
  exit 1
fi
if [[ -n $(sbx policy ls --source local --created-via default -q 2>/dev/null) ]]; then
  echo "note    global policy is 'balanced' (broad default allow rules);"
  echo "        see policy/README.md to switch to deny-all"
else
  echo "ok      global policy has no default allow rules (deny-all)"
fi

for t in "${templates[@]}"; do
  file=allow/$t.txt
  [[ -f $file ]] || { echo "no allowlist for template '$t' ($file)" >&2; exit 2; }
  echo "-- $t"
  missing=()
  while read -r host _; do
    [[ -z $host || $host == \#* ]] && continue
    [[ $host == *:* ]] || host=$host:443
    if sbx policy check network "$host" --json | grep -q '"allowed": *true'; then
      echo "ok      $host"
    else
      echo "allow   $host"
      missing+=("$host")
    fi
  done < "$file"
  if (( ${#missing[@]} )); then
    run sbx policy allow network "$(IFS=,; echo "${missing[*]}")"
  fi
done

(( dry )) && echo "(dry run: nothing changed)"
exit 0
