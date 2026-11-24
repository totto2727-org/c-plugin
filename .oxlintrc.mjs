import preset from '@totto2727/oxlint/preset/application'
import { defineConfig } from 'oxlint'

// oxlint-disable-next-line import/no-default-export -- Oxlint loads the default export of an ESM configuration.
export default defineConfig({ extends: [preset] })
