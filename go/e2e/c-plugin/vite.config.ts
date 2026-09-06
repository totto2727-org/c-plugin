import { defineConfig } from 'vite-plus'

export default defineConfig({
  run: {
    tasks: {
      build: {
        command: 'go build ./...',
      },
      check: {
        command: 'golangci-lint fmt --diff && golangci-lint run ./...',
      },
      fix: {
        command: 'golangci-lint fmt && golangci-lint run --fix ./...',
      },
      'setup:image': {
        cache: false,
        command: 'just --justfile ../../../Justfile c-plugin-e2e-image',
      },
      test: {
        cache: false,
        command: 'go test -v -race -shuffle=on -count=1 ./...',
        dependsOn: ['setup:image'],
      },
    },
  },
})
