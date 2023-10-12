import { expect, use } from 'chai'
import { upgrades } from 'hardhat'
import { jestSnapshotPlugin } from 'mocha-chai-jest-snapshot'

upgrades.silenceWarnings()

use(jestSnapshotPlugin())

export { expect }
