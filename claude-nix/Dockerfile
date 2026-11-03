# syntax=docker/dockerfile:1
#
# Docker Sandboxes (sbx) template: Claude Code + single-user Nix with
# flakes, direnv and nix-direnv. A project's `.envrc` (`use flake`) is
# loaded automatically before every shell command Claude runs.
#
# Build and load with ./build.sh, then:
#   sbx run --pull never --template localhost/claude-nix:latest claude ~/src/project

# Pin by digest for reproducible builds, e.g.
#   --build-arg BASE_IMAGE=docker.io/docker/sandbox-templates:claude-code@sha256:...
ARG BASE_IMAGE=docker.io/docker/sandbox-templates:claude-code
FROM ${BASE_IMAGE}

# --- system layer (root) ----------------------------------------------
USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git xz-utils \
 && rm -rf /var/lib/apt/lists/* \
 # Single-user Nix: the store is owned by the agent user, no daemon.
 && install -d -m 0755 -o agent -g agent /nix \
 && install -d -m 0755 /etc/nix /usr/local/share/claude-nix

COPY nix.conf /etc/nix/nix.conf
COPY env.sh /usr/local/share/claude-nix/env.sh
COPY sandbox-CLAUDE.md /usr/local/share/claude-nix/CLAUDE.md

# Managed memory: Claude Code loads /etc/claude-code/CLAUDE.md in every
# session. Living outside ~/.claude, it can't be hidden by a volume
# mounted there. Appended in case the base image ships one.
RUN install -d -m 0755 /etc/claude-code \
 && cat /usr/local/share/claude-nix/CLAUDE.md >> /etc/claude-code/CLAUDE.md

# The base image points CLAUDE_ENV_FILE and BASH_ENV at this file, so
# it runs before every Bash command Claude executes.
RUN touch /etc/sandbox-persistent.sh \
 && echo '. /usr/local/share/claude-nix/env.sh' >> /etc/sandbox-persistent.sh

# --- user layer (agent, uid 1000) -------------------------------------
USER agent

ARG NIX_INSTALL_URL=https://nixos.org/nix/install
RUN curl -fsSL "$NIX_INSTALL_URL" -o /tmp/install-nix \
 && sh /tmp/install-nix --no-daemon --no-channel-add --no-modify-profile \
 && rm /tmp/install-nix

ENV PATH=/home/agent/.nix-profile/bin:$PATH \
    # Use the system CA bundle so a CA injected by the sbx proxy is trusted.
    NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

COPY --chown=agent:agent direnv.toml /home/agent/.config/direnv/direnv.toml

# nixpkgs revision that `nixpkgs` resolves to in the sandbox: for
# direnv/nix-direnv, `nixpkgs#...`, and flake inputs `url = "nixpkgs"`
# when a project has no flake.lock yet (existing locks are unaffected).
# It replaces the global registry (see flake-registry in nix.conf); a
# user registry pin would be ignored when locking flake inputs. Bump with
#   curl -fsSL https://channels.nixos.org/nixpkgs-unstable/git-revision
ARG NIXPKGS_REV=d357a2b54f0b6dc4aeb4e993190a52cf151b6f24
USER root
RUN printf '%s\n' \
      '{"version":2,"flakes":[{"from":{"type":"indirect","id":"nixpkgs"},' \
      "\"to\":{\"type\":\"github\",\"owner\":\"NixOS\",\"repo\":\"nixpkgs\",\"rev\":\"${NIXPKGS_REV}\"}}]}" \
      > /etc/nix/flake-registry.json
USER agent
RUN nix registry list \
 && nix registry list | grep -qxF "global flake:nixpkgs github:NixOS/nixpkgs/${NIXPKGS_REV}" \
 && nix profile add nixpkgs#direnv nixpkgs#nix-direnv \
 && echo 'source $HOME/.nix-profile/share/nix-direnv/direnvrc' \
      > /home/agent/.config/direnv/direnvrc \
 && echo 'eval "$(direnv hook bash)"' >> /home/agent/.bashrc \
 && nix store gc \
 && nix --version && direnv version
