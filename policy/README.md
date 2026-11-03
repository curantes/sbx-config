# Hardened sbx baseline

    policy/apply.sh --dry-run     # show what would change
    policy/apply.sh               # apply settings + template allowlists

The script is idempotent: it compares each setting and host with the
current state, changes only what differs, and ends with the next steps
(daemon restart, recreating sandboxes). Written for sbx v0.50.

## Threat model

Agents in these sandboxes run without permission prompts (Claude Code's
"bypass permissions" mode), so the sandbox is the only boundary. Assume
that anything a sandbox can reach, a prompt-injected agent will use:
instructions can hide in a README, an issue, a dependency or a web page.

What still crosses the microVM boundary, and how this setup limits it:

| Path | Risk | Control | Friction |
|---|---|---|---|
| Host workspace, mounted read-write by default | Files that later **run on your host**: `.git/hooks/*` (invisible in `git diff`), `.claude/settings.json` hooks, `.envrc`, `Makefile`, `.vscode/tasks.json`, `package.json` scripts | [Clone mode](#work-in-clone-mode) | Low: review and merge through `git fetch` |
| Credentials the proxy injects | A broad GitHub token lets the agent push to all your repos, including workflow files | [No GitHub token in the sandbox](#secrets), or a narrow one per sandbox | None to low |
| Network egress | Exfiltration and downloads; `balanced` allows ~200 hosts incl. `**.amazonaws.com`, `**.googleapis.com` | [`deny-all` + allowlists](#network-policy) | Medium: add hosts as `sbx policy log` shows them |
| Host browser | Opens any URL in your logged-in browser | `browser.enabled=false` | One toggle per `/login` |
| Host SSH agent | Signs as you wherever your keys work | `ssh.agentForwardingEnabled=false` | Push from the host instead |
| Shared skills store, kits | Instructions or root install steps shared across sandboxes | `skills.defaultMode=off`, signed remote kits only | None |
| Local MCP servers | Run on the host with your permissions | Register none (`sbx mcp ls`) | None |
| A `/login` token (Pro/Max) | Stored inside the sandbox, so code there can read it | `deny-all` limits where it can go; recreate sandboxes regularly | Re-login per sandbox |

Inside the VM the agent has sudo and its changes persist across
restarts. Prefer short-lived sandboxes (`--rm` for one-off tasks) and
recreate long-lived ones regularly.

## Settings

| Setting | Baseline | Default | Why |
|---|---|---|---|
| `ssh.agentForwardingEnabled` | `false` | `true` | Code in a sandbox could otherwise sign with your host SSH keys. Needs `sbx daemon restart`. |
| `browser.enabled` | `false` | `true` | Code in a sandbox could otherwise open URLs in your host browser. `--browser` keeps it on; see [Pro/Max login](#promax-login). |
| `skills.defaultMode` | `off` | `readonly` | Don't mount the host's shared agent skills store. Pass `--skills readonly` to a sandbox that needs it. |
| `kit.requireSignature` | `true` | `false` | Kits run install steps as root; require a trusted signature. Docker's pinned agent kits stay exempt (`kit.allowExtractedAgents`). |
| `kit.allowLocalKits` | `false` | `true` | Only kits from allowed remote sources. `--allow-local-kits` keeps local kits while you develop one. |
| `clipboard.imagePaste` | `false` | `false` | Sandboxes can't read the host clipboard. |
| `claude.remoteControl` | `false` | `false` | No separate session token for Claude Code's `/remote-control`. |
| `diagnostics.autoUpload` | `no` | unset | Never upload diagnostics bundles automatically. |

Settings apply to sandboxes created afterwards; recreate existing ones.

## Work in clone mode

Create sandboxes with `--clone`. Your repository is mounted read-only,
and the agent commits to a private clone inside the VM. sbx adds a
`sandbox-<name>` remote to your host repository, so you review the work
before any of it reaches your checkout:

    sbx run --clone --name myproj claude .
    # ask the agent to work on a branch and commit, then on the host:
    git fetch sandbox-myproj
    git diff main...sandbox-myproj/<branch>
    git merge sandbox-myproj/<branch>     # or check it out, push, open a PR

Fetching transfers commits only, never hooks or other `.git` contents.
Still review the diff: merged code runs on your host when you build or
test it. The remote only works while the sandbox runs, and `sbx rm`
drops unfetched work.

Clone mode needs a Git repository (the main checkout, not a linked
worktree). Use direct mode, without `--clone`, only when you need edits
live in your working tree. Afterwards check what the agent could have
planted: `git status`, `ls .git/hooks`, and changes under `.claude/`.

## Network policy

Each file in [`allow/`](allow/) lists the hosts a template needs inside
the sandbox; `apply.sh` adds the ones the current policy doesn't
already allow. The Claude agent kit allows its own Anthropic hosts per
sandbox, so they aren't listed.

Under `balanced`, these rules add nothing; the gain comes from
switching to `deny-all`. That requires resetting the policy, which
**removes all local rules**, including ones you added yourself, so it's
a manual step:

    sbx policy ls --wide --source local   # note rules you added and want to keep
    sbx policy reset
    sbx policy init deny-all
    policy/apply.sh                       # template allowlists
    sbx policy allow network <host>       # your own additions

When something fails because a host is blocked, find it and allow only
what you trust (`--sandbox <name>` keeps a rule to one sandbox):

    sbx policy log <sandbox> --limit 50

With Nix most packages come from `cache.nixos.org`. Building one that
isn't cached fetches its sources from upstream hosts, and language
package managers (npm, PyPI, crates.io) need their registries added.

## Secrets

In clone mode the sandbox needs no GitHub credentials: you fetch its
commits and push from the host. If the agent must push branches or open
pull requests itself, give that one sandbox a
[fine-grained token](https://github.com/settings/personal-access-tokens)
limited to the repositories involved, with *Contents* and *Pull
requests* read/write and no *Workflows* permission:

    sbx secret set github --sandbox myproj      # paste the token

Don't use `gh auth token`: it carries your full `repo`, `workflow` and
`gist` scopes for every repository you can access.

For API keys, prefer secrets the proxy injects and fetch them on the
host when needed:

    sbx secret set anthropic --ref 'op://Private/Anthropic/api-key'

### Pro/Max login

`/login` stores its token inside the sandbox (see above) and needs the
host browser for the OAuth redirect. Turn it on just for the login:

    sbx settings set browser.enabled true
    # run /login in the new sandbox and finish it in the browser
    sbx settings set browser.enabled false

## Applying it from home-manager

Keep machine-specific choices (secrets, extra hosts, `--browser`) out
of this repository. For example, run the script from a home-manager
activation step with this repository as a flake input, and add your own
`sbx secret set` and `sbx policy allow` commands next to it.
