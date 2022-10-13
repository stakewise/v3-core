import { expect, use } from 'chai'
import { upgrades } from 'hardhat'
import { solidity } from 'ethereum-waffle'
import { jestSnapshotPlugin } from 'mocha-chai-jest-snapshot'

upgrades.silenceWarnings()

use(solidity)
use(jestSnapshotPlugin())

export { expect }
