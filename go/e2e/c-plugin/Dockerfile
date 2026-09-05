ARG SANDBOX_IMAGE=ghcr.io/totto2727-org/monorepo/sandbox-base@sha256:df12730051f9c1c920c250be35e04a56332dd9d31f2a2dc839042f74c90fe1c0

FROM ${SANDBOX_IMAGE} AS builder

USER sandbox
WORKDIR /sandbox

ARG MOONBIT_VERSION=0.10.7%2Bbc794d341
ARG MOONBIT_CORE_SHA256=06922d35dd94dc0baea7682295fe6084f0d854eed3b497cd6b527f77d899a7f5

RUN architecture=$(uname -m) && \
    case "$architecture" in \
      amd64|x86_64) moon_arch=x86_64 ;; \
      arm64|aarch64) moon_arch=aarch64 ;; \
      *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 1 ;; \
    esac && \
    cd /tmp && \
    moon_archive="moonbit-linux-$moon_arch.tar.gz" && \
    core_archive="core-$MOONBIT_VERSION.tar.gz" && \
    curl -fsSLo "$moon_archive" \
      "https://cli.moonbitlang.com/binaries/$MOONBIT_VERSION/$moon_archive" && \
    curl -fsSLo "$moon_archive.sha256" \
      "https://cli.moonbitlang.com/binaries/$MOONBIT_VERSION/$moon_archive.sha256" && \
    curl -fsSLo "$core_archive" \
      "https://cli.moonbitlang.com/cores/$core_archive" && \
    sha256sum -c "$moon_archive.sha256" && \
    printf '%s  %s\n' "$MOONBIT_CORE_SHA256" "$core_archive" | sha256sum -c - && \
    rm -rf /sandbox/.moon/lib /sandbox/.moon/include && \
    tar -xzf "$moon_archive" -C /sandbox/.moon && \
    tar -xzf "$core_archive" -C /sandbox/.moon/lib && \
    chmod +x /sandbox/.moon/bin/* /sandbox/.moon/bin/internal/tcc && \
    moon -C /sandbox/.moon/lib/core bundle --warn-list -a --all && \
    rm "$moon_archive" "$moon_archive.sha256" "$core_archive"

COPY --chown=sandbox:sandbox moon.mod /tmp/c-plugin/moon.mod
COPY --chown=sandbox:sandbox src /tmp/c-plugin/src

RUN cd /tmp/c-plugin && \
    moon update && \
    moon install /tmp/c-plugin/src \
      --bin /sandbox/.local/bin \
      --target-dir /sandbox/.cache/c-plugin-build && \
    test -x /sandbox/.local/bin/c-plugin && \
    rm -rf /tmp/c-plugin /sandbox/.cache/c-plugin-build

FROM ${SANDBOX_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/totto2727-org/c-plugin"

USER sandbox
WORKDIR /sandbox

COPY --from=builder --chown=sandbox:sandbox /sandbox/.local/bin/c-plugin /sandbox/.local/bin/c-plugin
RUN chmod +x /sandbox/.local/bin/c-plugin

ENTRYPOINT ["sleep", "infinity"]
