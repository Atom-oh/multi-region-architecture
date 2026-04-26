FROM ghcr.io/actions/actions-runner:latest

USER root

ARG GH_CLI_VERSION=2.74.0
ARG TARGETARCH

# gh CLI
RUN curl -sL "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_${TARGETARCH}.tar.gz" -o /tmp/gh.tar.gz \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && cp /tmp/gh_*/bin/gh /usr/local/bin/gh \
    && rm -rf /tmp/gh* \
    && gh --version

# Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && cp /root/.local/bin/claude /usr/local/bin/claude \
    && rm -rf /root/.claude /root/.local

# python3 (used by PR review scripts)
RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

USER runner
