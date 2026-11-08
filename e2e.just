mod c-plugin 'e2e-c-plugin.just'

# Run the isolated CLI scenarios with the caller-owned image and drivers.
[default]
all: c-plugin::image driver
    #!/usr/bin/env bash
    set -euo pipefail
    arch=$(docker image inspect c-plugin-e2e:local --format '{{ "{{" }}.Architecture}}')
    export C_PLUGIN_E2E_DRIVER="$PWD/tmp/caseyard-driver/driver-linux-$arch"
    cd e2e
    cabal test acceptance --test-show-details=direct --test-options='--jobs=2 --randomize'

# Generate Cabal manifests from the maintained package definitions.
_generate:
    hpack
    hpack e2e

# Compile host-side acceptance tests without starting Docker containers.
check: _generate
    cd e2e && cabal build test:acceptance

# Build trusted terminal/snapshot drivers from the same revision as the SDK.
driver:
    #!/usr/bin/env bash
    set -euo pipefail
    revision=$(awk '$1 == "tag:" { print $2 }' e2e/cabal.project)
    source_dir="$PWD/tmp/caseyard-driver/source"
    output_dir="$PWD/tmp/caseyard-driver"
    if [[ ! -d "$source_dir/.git" ]]; then
        git clone --depth 1 https://github.com/totto2727-org/e2e.git "$source_dir"
    fi
    if [[ -n "$(git -C "$source_dir" status --porcelain)" ]]; then
        echo "Caseyard driver checkout has local changes: $source_dir" >&2
        exit 1
    fi
    if [[ "$(git -C "$source_dir" rev-parse HEAD)" != "$revision" ]]; then
        git -C "$source_dir" fetch --depth 1 origin "$revision"
    fi
    git -C "$source_dir" checkout --detach "$revision"
    cd "$source_dir/go"
    for arch in amd64 arm64; do
        CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -trimpath -ldflags='-s -w' -o "$output_dir/driver-linux-$arch" ./cmd/caseyard-driver
    done
