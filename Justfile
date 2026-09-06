default:
    @just --list

c-plugin-e2e-image:
    docker build --file go/e2e/c-plugin/Dockerfile --tag c-plugin-e2e:local .
