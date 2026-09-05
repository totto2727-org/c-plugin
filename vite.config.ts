import { defineConfig } from 'vite-plus'

export default defineConfig({
  run: {
    tasks: {
      build: {
        command: '',
        dependsOn: ['mbt:build', '@go/c-plugin-e2e#build'],
      },
      check: {
        command: '',
        dependsOn: ['mbt:check', '@go/c-plugin-e2e#check'],
      },
      ci: {
        command: '',
        dependsOn: ['check', 'build', 'test'],
      },
      fix: {
        command: '',
        dependsOn: ['mbt:fix', '@go/c-plugin-e2e#fix'],
      },
      'mbt:build': {
        command: 'moon build --target native',
        input: [{ auto: true }, '!**/_build/**'],
      },
      'mbt:check': {
        command: 'moon check --target native',
        input: [{ auto: true }, '!**/_build/**'],
      },
      'mbt:fix': {
        command: 'moon fmt',
        input: [{ auto: true }, '!**/_build/**'],
      },
      'mbt:test': {
        command: 'LD_LIBRARY_PATH="$MOONBIT_OPENSSL_LIBRARY_PATH" moon test --target native --no-parallelize',
        env: ['MOONBIT_OPENSSL_LIBRARY_PATH'],
        input: [{ auto: true }, '!**/_build/**'],
      },
      test: {
        command: '',
        dependsOn: ['mbt:test', '@go/c-plugin-e2e#test'],
      },
    },
  },
})
