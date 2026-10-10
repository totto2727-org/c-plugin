default:
    @just --list

# Compile the Haskell library and CLI.
build:
    cabal build --offline all

# Cabal manifest and compiler checks.
check:
    cabal check
    fourmolu --mode check hs-src app test
    hlint hs-src app test
    cabal build --offline all
    cd go/e2e/c-plugin && golangci-lint fmt --diff && golangci-lint run ./...

# Apply the standard Haskell formatter, then check lint suggestions.
fix:
    fourmolu --mode inplace hs-src app test
    hlint hs-src app test

# Run native product tests, without Docker.
test:
    cabal test --offline all --test-show-details=direct

# Build the caller-owned image used by the isolated CLI scenarios.
c-plugin-e2e-image:
    docker build --file go/e2e/c-plugin/Dockerfile --tag c-plugin-e2e:local .

e2e: c-plugin-e2e-image
    cd go/e2e/c-plugin && go test -v -race -shuffle=on -count=1 ./...

# Build the independent Nix package, including its product tests.
build-nix:
    nix build .#c-plugin

# Standard CI validation. Docker E2E remains an explicit local task.
ci: check test build-nix
