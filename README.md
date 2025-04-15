# StakeWise Protocol V3

StakeWise V3 is a decentralized liquid staking protocol that operates on Ethereum and other EVM-compatible chains such as Gnosis Chain. The protocol allows users to stake their assets (ETH, GNO) and receive liquid staking tokens in return, enabling them to maintain liquidity while earning staking rewards.

[![Discord](https://user-images.githubusercontent.com/7288322/34471967-1df7808a-efbb-11e7-9088-ed0b04151291.png)](https://discord.gg/stakewise)

## Architecture Overview

The StakeWise V3 protocol consists of several key components:

### Vaults

Modular smart contracts that manage staked assets:

- **EthVault**: For Ethereum staking
- **GnoVault**: For Gnosis Chain staking
- **Specialized variants**: Blocklist vaults, private vaults, ERC20 vaults

### Token System

- **OsToken**: Over-collateralized staked token
- **OsTokenVaultController**: Manages the minting and burning of OsToken shares
- **OsTokenConfig**: Configuration parameters for OsToken operations

### Validator Management

- **ValidatorsRegistry**: Interface with the blockchain's validator system
- **KeeperValidators**: Approves validator registrations
- **ValidatorsChecker**: Validates deposit data

### MEV Management

- **OwnMevEscrow**: Accumulates MEV for individual vaults
- **SharedMevEscrow**: Collects and distributes MEV rewards accross multiple vaults

### Auxiliary Components

- **Keeper**: Updates vault rewards and approves validator registrations
- **VaultsRegistry**: Tracks all deployed vaults and factories
- **RewardSplitter**: Distributes fee based on configured shares

## Key Features

- **Modular Architecture**: Components can be developed independently
- **Multi-Chain Support**: Works on Ethereum and Gnosis Chain
- **MEV Capture**: Captures and distributes MEV rewards
- **Validator Management**: Full lifecycle management of validators
- **Customizable Vaults**: Different vault types for various use cases
- **Over-Collateralized Tokens**: Liquid staking with osToken system
- **Governance Controls**: Admin functions for parameter updates

## Installation

This project uses Foundry as the development environment.

1. Install Foundry:

```shell
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Clone the repository and install dependencies:

```shell
git clone https://github.com/stakewise/v3-core.git
cd v3-core
forge install
```

3. Create and update .env file

```shell
cp .env.example .env
```

## Development

### Compilation

Compile contracts with Foundry:

```shell
forge build --skip test
```

### Testing

Run tests with Foundry:

```shell
FOUNDRY_PROFILE=test forge test --isolate
```

### Local Deployment

1. Start a local Anvil node (Foundry's local chain):

```shell
anvil --fork-url https://eth.merkle.io
```

2. Deploy contracts using Foundry scripts:

```shell
# Ethereum
forge script script/UpgradeEthNetwork.s.sol:UpgradeEthNetwork --rpc-url http://localhost:8545 --broadcast
# Gnosis Chain
forge script script/UpgradeGnoNetwork.s.sol:UpgradeGnoNetwork --rpc-url http://localhost:8545 --broadcast 
```

### Gas Analysis

Generate a gas report:

```shell
FOUNDRY_PROFILE=test forge test --isolate --gas-report
```

## Contract Documentation

Detailed documentation for each contract is available in the `contracts` directory. For integration purposes, review the interfaces in the `contracts/interfaces` directory.

Key interfaces include:

- `IEthVault.sol`: Ethereum staking vaults
- `IGnoVault.sol`: Gnosis Chain staking vaults
- `IOsToken.sol`: Over-collateralized staked tokens
- `IKeeper.sol`: Validator and rewards management

## Protocol Architecture

The protocol follows a modular design with several key components:

1. **Vaults**: Hold staked assets and manage validator operations
2. **Tokens**: Represent staked positions with liquid tokens
3. **Keepers**: External services that update rewards and approve validators
4. **MEV Escrows**: Capture and distribute MEV rewards

## Contributing

Contributions are welcome! The project follows standard GitHub flow:

1. Fork the repository
2. Create a feature branch
3. Implement changes with tests
4. Submit a pull request

Development happens in the open on GitHub, and we are grateful to the community for contributing bug fixes and improvements.

## Contact

- [Discord](https://chat.stakewise.io/)
- [Telegram](https://t.me/stakewise_io)
- [Twitter](https://twitter.com/stakewise_io)

## License

The license for StakeWise V3 Core is the Business Source License 1.1 (BUSL-1.1), see [LICENSE](./LICENSE.md).
