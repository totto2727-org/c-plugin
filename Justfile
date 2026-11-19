default:
    @just --list

# Compile the Haskell library and CLI.
build: generate
    cabal build --offline all

# Cabal manifest and compiler checks.
check: generate
    cabal check
    fourmolu --mode check lib app test e2e/CPlugin e2e/Spec.hs
    hlint lib app test e2e/CPlugin e2e/Spec.hs
    cabal build --offline all

# Apply the standard Haskell formatter, then check lint suggestions.
fix:
    fourmolu --mode inplace lib app test e2e/CPlugin e2e/Spec.hs
    hlint lib app test e2e/CPlugin e2e/Spec.hs

# Run native product tests, without Docker.
test: generate
    cabal test --offline all --test-show-details=direct

# Build the caller-owned image used by the isolated CLI scenarios.
c-plugin-e2e-image:
    docker build --file e2e/Dockerfile --tag c-plugin-e2e:local .

# Compile host-side acceptance tests without starting Docker containers.
e2e-check: generate
    cd e2e && cabal build test:acceptance

# Build trusted terminal/snapshot drivers from the same revision as the SDK.
e2e-driver:
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

e2e: c-plugin-e2e-image e2e-driver
    #!/usr/bin/env bash
    set -euo pipefail
    arch=$(docker image inspect c-plugin-e2e:local --format '{{"{{"}}.Architecture}}')
    export C_PLUGIN_E2E_DRIVER="$PWD/tmp/caseyard-driver/driver-linux-$arch"
    cd e2e
    cabal test acceptance --test-show-details=direct --test-options='--jobs=2 --randomize'

# Build the independent Nix package, including its product tests.
build-nix:
    nix build .#c-plugin

# Standard CI validation. Docker E2E remains an explicit local task.
ci: check test

# Generate Cabal manifests from the maintained package definitions.
generate:
    hpack
    hpack e2e
