// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

/**
 * @title Network
 * @author StakeWise
 * @notice Solidity library containing constants for the StakeWise protocol
 */
library Network {
    uint256 internal constant MAINNET = 1;
    uint256 internal constant HOODI = 560048;
    uint256 internal constant CHIADO = 10200;
    uint256 internal constant GNOSIS = 100;

    uint64 internal constant PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY = 1 days;
    // disable delay for private vaults as stakers are KYC'd
    uint64 internal constant PRIVATE_VAULT_EXITED_ASSETS_CLAIM_DELAY = 0;
    address internal constant VALIDATORS_WITHDRAWALS = 0x00000961Ef480Eb55e80D19ad83579A64c007002;
    address internal constant VALIDATORS_CONSOLIDATIONS = 0x0000BBdDc7CE488642fb579F8B00f3a590007251;

    // MAINNET
    address internal constant MAINNET_KEEPER = 0x6B5815467da09DaA7DC83Db21c9239d98Bb487b5;
    address internal constant MAINNET_VAULTS_REGISTRY = 0x3a0008a588772446f6e656133C2D5029CC4FC20E;
    address internal constant MAINNET_VALIDATORS_REGISTRY = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
    address internal constant MAINNET_OS_TOKEN_VAULT_CONTROLLER = 0x2A261e60FB14586B474C208b1B7AC6D0f5000306;
    address internal constant MAINNET_OS_TOKEN_CONFIG = 0x287d1e2A8dE183A8bf8f2b09Fa1340fBd766eb59;
    address internal constant MAINNET_OS_TOKEN_VAULT_ESCROW = 0x09e84205DF7c68907e619D07aFD90143c5763605;
    address internal constant MAINNET_SHARED_MEV_ESCROW = 0x48319f97E5Da1233c21c48b80097c0FB7a20Ff86;
    address internal constant MAINNET_DEPOSIT_DATA_REGISTRY = 0x75AB6DdCe07556639333d3Df1eaa684F5735223e;
    address internal constant MAINNET_LEGACY_POOL_ESCROW = 0x2296e122c1a20Fca3CAc3371357BdAd3be0dF079;
    address internal constant MAINNET_LEGACY_REWARD_TOKEN = 0x20BC832ca081b91433ff6c17f85701B6e92486c5;

    // HOODI
    address internal constant HOODI_KEEPER = 0xA7D1Ac9D6F32B404C75626874BA56f7654c1dC0f;
    address internal constant HOODI_VAULTS_REGISTRY = 0xf16fea93D3253A401C3f73B0De890C6586740B25;
    address internal constant HOODI_VALIDATORS_REGISTRY = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
    address internal constant HOODI_OS_TOKEN_VAULT_CONTROLLER = 0x140Fc69Eabd77fFF91d9852B612B2323256f7Ac1;
    address internal constant HOODI_OS_TOKEN_CONFIG = 0x5b817621EBE00622b9a71b53c942b392751c8197;
    address internal constant HOODI_OS_TOKEN_VAULT_ESCROW = 0xdC1347cC04d4a8945b98A09C3c5585286bbA5C2B;
    address internal constant HOODI_SHARED_MEV_ESCROW = 0x51FD45BAEfB12f54766B5C4d639b360Ea50063bd;
    address internal constant HOODI_DEPOSIT_DATA_REGISTRY = 0x93a3f880E07B27dacA6Ef2d3C23E77DBd6294487;
    address internal constant HOODI_LEGACY_POOL_ESCROW = 0x291Fa5849215847081B475450cBE5De46CfD4fAE;
    address internal constant HOODI_LEGACY_REWARD_TOKEN = 0x75c57bd50A3EB7291Da3429956D3566E0153A38f;

    // GNOSIS
    address internal constant GNOSIS_KEEPER = 0xcAC0e3E35d3BA271cd2aaBE688ac9DB1898C26aa;
    address internal constant GNOSIS_VAULTS_REGISTRY = 0x7d014B3C6ee446563d4e0cB6fBD8C3D0419867cB;
    address internal constant GNOSIS_VALIDATORS_REGISTRY = 0x0B98057eA310F4d31F2a452B414647007d1645d9;
    address internal constant GNOSIS_OS_TOKEN_VAULT_CONTROLLER = 0x60B2053d7f2a0bBa70fe6CDd88FB47b579B9179a;
    address internal constant GNOSIS_OS_TOKEN_CONFIG = 0xd6672fbE1D28877db598DC0ac2559A15745FC3ec;
    address internal constant GNOSIS_OS_TOKEN_VAULT_ESCROW = 0x28F325dD287a5984B754d34CfCA38af3A8429e71;
    address internal constant GNOSIS_SHARED_MEV_ESCROW = 0x30db0d10d3774e78f8cB214b9e8B72D4B402488a;
    address internal constant GNOSIS_DEPOSIT_DATA_REGISTRY = 0x58e16621B5c0786D6667D2d54E28A20940269E16;
    address internal constant GNOSIS_LEGACY_POOL_ESCROW = 0xfc9B67b6034F6B306EA9Bd8Ec1baf3eFA2490394;
    address internal constant GNOSIS_LEGACY_REWARD_TOKEN = 0x6aC78efae880282396a335CA2F79863A1e6831D4;

    // CHIADO
    address internal constant CHIADO_KEEPER = 0x5f31eD13eBF81B67a9f9498F3d1D2Da553058988;
    address internal constant CHIADO_VAULTS_REGISTRY = 0x8750594B33516232e751C8B9C350a660cD5f1BB8;
    address internal constant CHIADO_VALIDATORS_REGISTRY = 0xb97036A26259B7147018913bD58a774cf91acf25;
    address internal constant CHIADO_OS_TOKEN_VAULT_CONTROLLER = 0x5518052f2d898f062ee59964004A560F24E2eE7d;
    address internal constant CHIADO_OS_TOKEN_CONFIG = 0x6D5957e075fd93b3B9F36Da93d7462F14387706d;
    address internal constant CHIADO_OS_TOKEN_VAULT_ESCROW = 0x00aa8A78d88a9865b5b0F4ce50c3bB018c93FBa7;
    address internal constant CHIADO_SHARED_MEV_ESCROW = 0x453056f0bc4631abB15eEC656139f88067668E3E;
    address internal constant CHIADO_DEPOSIT_DATA_REGISTRY = 0xFAce8504462AEb9BB6ae7Ecb206BD7B1EdF7956D;
    address internal constant CHIADO_LEGACY_POOL_ESCROW = 0x928F9a91E674C886Cae0c377670109aBeF7e19d6;
    address internal constant CHIADO_LEGACY_REWARD_TOKEN = 0x14c74b1C7eCa8362D4ABcCd71051Ce174d61a3D4;

    struct Constants {
        address keeper;
        address vaultsRegistry;
        address validatorsRegistry;
        address validatorsWithdrawals;
        address validatorsConsolidations;
        address osTokenVaultController;
        address osTokenConfig;
        address osTokenVaultEscrow;
        address sharedMevEscrow;
        address depositDataRegistry;
        address legacyPoolEscrow;
        address legacyRewardToken;
        uint64 exitedAssetsClaimDelay;
    }

    function getNetworkConstants(uint256 chainId) internal pure returns (Constants memory) {
        if (chainId == MAINNET) {
            return Constants({
                keeper: MAINNET_KEEPER,
                vaultsRegistry: MAINNET_VAULTS_REGISTRY,
                validatorsRegistry: MAINNET_VALIDATORS_REGISTRY,
                validatorsWithdrawals: VALIDATORS_WITHDRAWALS,
                validatorsConsolidations: VALIDATORS_CONSOLIDATIONS,
                osTokenVaultController: MAINNET_OS_TOKEN_VAULT_CONTROLLER,
                osTokenConfig: MAINNET_OS_TOKEN_CONFIG,
                osTokenVaultEscrow: MAINNET_OS_TOKEN_VAULT_ESCROW,
                sharedMevEscrow: MAINNET_SHARED_MEV_ESCROW,
                depositDataRegistry: MAINNET_DEPOSIT_DATA_REGISTRY,
                legacyPoolEscrow: MAINNET_LEGACY_POOL_ESCROW,
                legacyRewardToken: MAINNET_LEGACY_REWARD_TOKEN,
                exitedAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
            });
        } else if (chainId == HOODI) {
            return Constants({
                keeper: HOODI_KEEPER,
                vaultsRegistry: HOODI_VAULTS_REGISTRY,
                validatorsRegistry: HOODI_VALIDATORS_REGISTRY,
                validatorsWithdrawals: VALIDATORS_WITHDRAWALS,
                validatorsConsolidations: VALIDATORS_CONSOLIDATIONS,
                osTokenVaultController: HOODI_OS_TOKEN_VAULT_CONTROLLER,
                osTokenConfig: HOODI_OS_TOKEN_CONFIG,
                osTokenVaultEscrow: HOODI_OS_TOKEN_VAULT_ESCROW,
                sharedMevEscrow: HOODI_SHARED_MEV_ESCROW,
                depositDataRegistry: HOODI_DEPOSIT_DATA_REGISTRY,
                legacyPoolEscrow: HOODI_LEGACY_POOL_ESCROW,
                legacyRewardToken: HOODI_LEGACY_REWARD_TOKEN,
                exitedAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
            });
        } else if (chainId == GNOSIS) {
            return Constants({
                keeper: GNOSIS_KEEPER,
                vaultsRegistry: GNOSIS_VAULTS_REGISTRY,
                validatorsRegistry: GNOSIS_VALIDATORS_REGISTRY,
                validatorsWithdrawals: VALIDATORS_WITHDRAWALS,
                validatorsConsolidations: VALIDATORS_CONSOLIDATIONS,
                osTokenVaultController: GNOSIS_OS_TOKEN_VAULT_CONTROLLER,
                osTokenConfig: GNOSIS_OS_TOKEN_CONFIG,
                osTokenVaultEscrow: GNOSIS_OS_TOKEN_VAULT_ESCROW,
                sharedMevEscrow: GNOSIS_SHARED_MEV_ESCROW,
                depositDataRegistry: GNOSIS_DEPOSIT_DATA_REGISTRY,
                legacyPoolEscrow: GNOSIS_LEGACY_POOL_ESCROW,
                legacyRewardToken: GNOSIS_LEGACY_REWARD_TOKEN,
                exitedAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
            });
        } else if (chainId == CHIADO) {
            return Constants({
                keeper: CHIADO_KEEPER,
                vaultsRegistry: CHIADO_VAULTS_REGISTRY,
                validatorsRegistry: CHIADO_VALIDATORS_REGISTRY,
                validatorsWithdrawals: VALIDATORS_WITHDRAWALS,
                validatorsConsolidations: VALIDATORS_CONSOLIDATIONS,
                osTokenVaultController: CHIADO_OS_TOKEN_VAULT_CONTROLLER,
                osTokenConfig: CHIADO_OS_TOKEN_CONFIG,
                osTokenVaultEscrow: CHIADO_OS_TOKEN_VAULT_ESCROW,
                sharedMevEscrow: CHIADO_SHARED_MEV_ESCROW,
                depositDataRegistry: CHIADO_DEPOSIT_DATA_REGISTRY,
                legacyPoolEscrow: CHIADO_LEGACY_POOL_ESCROW,
                legacyRewardToken: CHIADO_LEGACY_REWARD_TOKEN,
                exitedAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
            });
        } else {
            revert("Unsupported chain ID");
        }
    }
}
