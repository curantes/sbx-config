# Hardened sbx baseline

Docker Sandboxes isolate an agent in a microVM, but several defaults
open paths back to the host, and the `balanced` network policy allows
about 200 hosts, including broad wildcards such as `**.googleapis.com`
and `**.amazonaws.com`. This directory locks those down.

    policy/apply.sh --dry-run     # show what would change
    policy/apply.sh               # apply settings + template allowlists

The script is idempotent: it compares each setting and host with the
current state and changes only what differs. Written for sbx v0.50.

## Settings

| Setting | Baseline | Default | Why |
|---|---|---|---|
| `ssh.agentForwardingEnabled` | `false` | `true` | Otherwise any code in a sandbox can sign with your host SSH keys, i.e. authenticate as you wherever they work. Use `sbx secret set github` for git over HTTPS instead. |
| `skills.defaultMode` | `off` | `readonly` | Don't mount the host's shared agent skills store into sandboxes. Pass `--skills readonly` to a sandbox that needs it. |
| `kit.requireSignature` | `true` | `false` | Kits run install steps as root in the sandbox; require a trusted signature. Docker's pinned agent kits stay exempt (`kit.allowExtractedAgents`). |
| `kit.allowLocalKits` | `false` | `true` | Only install kits from allowed remote sources. `--allow-local-kits` keeps this on while you develop a kit. |
| `clipboard.imagePaste` | `false` | `false` | Sandboxes can't read the host clipboard. |
| `claude.remoteControl` | `false` | `false` | No separate session token for Claude Code's `/remote-control`. |
| `diagnostics.autoUpload` | `no` | unset | Never upload diagnostics bundles automatically. |
| `browser.enabled` | `true` | `true` | Sandboxed code can open URLs in the host browser, but `/login` with a Pro/Max account needs it. With an API key stored as an sbx secret, pass `--no-browser`. |

Settings apply to sandboxes created afterwards; recreate existing ones.

## Network policy

Each file in [`allow/`](allow/) lists the hosts a template needs inside
the sandbox. `apply.sh` adds the ones the current policy doesn't
already allow, as global rules. The Claude agent kit allows its own
Anthropic hosts per sandbox, so they aren't listed.

The script works with any global policy, but the real gain is switching
from `balanced` to `deny-all`. That requires resetting the policy, which
**removes all local rules**, including ones you added yourself or by
approving a prompt, so it's a manual step:

    sbx policy ls --wide --source local   # note any rules you added and want to keep
    sbx policy reset
    sbx policy init deny-all
    policy/apply.sh                       # template allowlists
    sbx policy allow network <host>       # your own additions

Then find what's still missing from what the sandbox actually tried to
reach, and allow only what you trust:

    sbx policy log <sandbox> --limit 50

Building packages that aren't in the Nix binary cache fetches sources
from their upstream hosts, which shows up here as blocked requests.

## Per-sandbox options

These can't be set globally; use them when creating a sandbox:

- `--clone`: the repository is mounted read-only and the agent works on
  a private clone in the VM. Without it, the agent edits your working
  tree in place, including Git hooks, CI config and build scripts that
  later run on your host.
- `--cpus N --memory 8g`: cap resources (default: all CPUs, half the RAM).
- `--rm`: remove the sandbox when the session ends.
- `--deny-network HOST`: extra deny rules for this sandbox only.

## Secrets

Prefer secrets the proxy injects on the host side over credentials
inside the sandbox, and fetch them at use time instead of storing them:

    sbx secret set anthropic --ref 'op://Private/Anthropic/api-key'
    sbx secret set github --command 'gh auth token'

A `/login` token (Pro/Max) lives inside the sandbox instead; see the
[claude-nix README](../claude-nix/README.md#authenticate-claude).

## Applying it from home-manager

Keep machine-specific choices (secrets, extra hosts, `--no-browser`)
out of this repository. For example, run the script from a
home-manager activation step with this repository as a flake input,
and add your own `sbx secret set` and `sbx policy allow` commands next
to it.
