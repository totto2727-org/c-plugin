default:
    @just --list e2e c-plugin

# Build the caller-owned image used by the isolated CLI scenarios.
image:
    docker build --file e2e/Dockerfile --tag c-plugin-e2e:local .
