// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EthNodesManager} from "../contracts/nodes/EthNodesManager.sol";
import {INodesManager} from "../contracts/interfaces/INodesManager.sol";
import {IEthNodesManager} from "../contracts/interfaces/IEthNodesManager.sol";
import {IVaultValidators} from "../contracts/interfaces/IVaultValidators.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {IKeeperValidators} from "../contracts/interfaces/IKeeperValidators.sol";
import {IEthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract EthNodesManagerTest is EthHelpers {
    EthNodesManager public nodesManager;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant MIN_BOND_ASSETS = 1 ether;
    uint16 public constant LTV_PERCENT = 5_000; // 50%

    uint256 public constant VALIDATOR_DEPOSIT = 32 ether;

    ForkContracts public contracts;
    address public vault;

    function setUp() public {
        contracts = _activateEthereumFork();

        owner = makeAddr("Owner");
        user1 = makeAddr("User1");
        user2 = makeAddr("User2");

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Create vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 5,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        vault = _getOrCreateVault(VaultType.EthVault, owner, initParams, false);

        // Deploy implementation and proxy
        EthNodesManager impl = new EthNodesManager(vault, address(contracts.keeper));
        address proxy = address(
            new ERC1967Proxy(
                address(impl),
                abi.encodeWithSelector(EthNodesManager.initialize.selector, owner, MIN_BOND_ASSETS, LTV_PERCENT)
            )
        );
        nodesManager = EthNodesManager(payable(proxy));

        // Set validators manager to nodesManager
        vm.prank(owner);
        IEthVault(vault).setValidatorsManager(address(nodesManager));
    }

    // ======== Initialization ========

    function test_initialState() public view {
        assertEq(nodesManager.owner(), owner);
        assertEq(nodesManager.minBondAssets(), MIN_BOND_ASSETS);
        assertEq(nodesManager.ltvPercent(), LTV_PERCENT);
        assertEq(nodesManager.vault(), vault);
        assertEq(nodesManager.withdrawalsManager(), address(0));
    }

    // ======== deposit ========

    function test_deposit() public {
        uint256 depositAmount = 10 ether;

        vm.expectEmit(true, true, true, false);
        emit INodesManager.Deposited(user1, depositAmount, IEthVault(vault).convertToShares(depositAmount));

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_deposit");
        uint256 shares = nodesManager.deposit{value: depositAmount}();
        _stopSnapshotGas();

        assertGt(shares, 0);
        assertEq(nodesManager.balances(user1), shares);
    }

    function test_deposit_belowMinBond() public {
        vm.prank(user1);
        vm.expectRevert(Errors.InvalidAssets.selector);
        nodesManager.deposit{value: MIN_BOND_ASSETS - 1}();
    }

    function test_deposit_zero() public {
        vm.prank(user1);
        vm.expectRevert(Errors.InvalidAssets.selector);
        nodesManager.deposit{value: 0}();
    }

    function test_deposit_multipleDeposits() public {
        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_deposit_multipleDeposits_first");
        uint256 shares1 = nodesManager.deposit{value: 5 ether}();
        _stopSnapshotGas();

        vm.prank(user2);
        _startSnapshotGas("EthNodesManagerTest_test_deposit_multipleDeposits_second");
        uint256 shares2 = nodesManager.deposit{value: 10 ether}();
        _stopSnapshotGas();

        assertGt(shares1, 0);
        assertGt(shares2, 0);
        assertEq(nodesManager.balances(user1), shares1);
        assertEq(nodesManager.balances(user2), shares2);
    }

    function test_deposit_accumulatesShares() public {
        vm.prank(user1);
        uint256 shares1 = nodesManager.deposit{value: 5 ether}();

        vm.prank(user1);
        uint256 shares2 = nodesManager.deposit{value: 5 ether}();

        assertEq(nodesManager.balances(user1), shares1 + shares2);
    }

    // ======== setMinBondAssets ========

    function test_setMinBondAssets() public {
        uint256 newMin = 2 ether;

        vm.expectEmit(true, true, true, true);
        emit INodesManager.MinBondAssetsUpdated(newMin);

        vm.prank(owner);
        _startSnapshotGas("EthNodesManagerTest_test_setMinBondAssets");
        nodesManager.setMinBondAssets(newMin);
        _stopSnapshotGas();

        assertEq(nodesManager.minBondAssets(), newMin);
    }

    function test_setMinBondAssets_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nodesManager.setMinBondAssets(2 ether);
    }

    function test_setMinBondAssets_sameValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        nodesManager.setMinBondAssets(MIN_BOND_ASSETS);
    }

    function test_setMinBondAssets_zero() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidAssets.selector);
        nodesManager.setMinBondAssets(0);
    }

    // ======== setLtvPercent ========

    function test_setLtvPercent() public {
        uint16 newLtv = 6_000; // 60%

        vm.expectEmit(true, true, true, true);
        emit INodesManager.LtvPercentUpdated(owner, newLtv);

        vm.prank(owner);
        _startSnapshotGas("EthNodesManagerTest_test_setLtvPercent");
        nodesManager.setLtvPercent(newLtv);
        _stopSnapshotGas();

        assertEq(nodesManager.ltvPercent(), newLtv);
    }

    function test_setLtvPercent_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nodesManager.setLtvPercent(6_000);
    }

    function test_setLtvPercent_sameValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        nodesManager.setLtvPercent(LTV_PERCENT);
    }

    function test_setLtvPercent_zero() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidLtvPercent.selector);
        nodesManager.setLtvPercent(0);
    }

    function test_setLtvPercent_maxPercent() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidLtvPercent.selector);
        nodesManager.setLtvPercent(10_000);
    }

    function test_setLtvPercent_aboveMaxPercent() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidLtvPercent.selector);
        nodesManager.setLtvPercent(10_001);
    }

    // ======== setWithdrawalsManager ========

    function test_setWithdrawalsManager() public {
        address newManager = makeAddr("WithdrawalsManager");

        vm.expectEmit(true, true, true, true);
        emit INodesManager.WithdrawalsManagerUpdated(newManager);

        vm.prank(owner);
        _startSnapshotGas("EthNodesManagerTest_test_setWithdrawalsManager");
        nodesManager.setWithdrawalsManager(newManager);
        _stopSnapshotGas();

        assertEq(nodesManager.withdrawalsManager(), newManager);
    }

    function test_setWithdrawalsManager_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nodesManager.setWithdrawalsManager(makeAddr("WithdrawalsManager"));
    }

    function test_setWithdrawalsManager_sameValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        nodesManager.setWithdrawalsManager(address(0));
    }

    // ======== registerValidators ========

    function test_registerValidators() public {
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        bytes memory oracleSignatures =
            _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);

        bytes memory publicKeys = _getValidatorsPublicKeys(approvalParams.validators);
        vm.expectEmit(true, true, true, true);
        emit INodesManager.ValidatorsRegistered(user1, 0, publicKeys);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_registerValidators");
        nodesManager.registerValidators(approvalParams, oracleSignatures);
        _stopSnapshotGas();

        _stopOracleImpersonate(address(contracts.keeper));

        // Nonce should be incremented
        assertEq(nodesManager.nonces(user1), 1);
    }

    function test_registerValidators_invalidSignatures_empty() public {
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.registerValidators(approvalParams, bytes(""));

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_invalidSignatures_wrongLength() public {
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        // Wrong length (not a multiple of 65)
        bytes memory badSig = new bytes(64);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.registerValidators(approvalParams, badSig);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_invalidSignatures_wrongSigner() public {
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        // Sign with a non-oracle key
        (, uint256 nonOracleKey) = makeAddrAndKey("nonOracle");
        bytes memory signatures = _getRegisterValidatorsSignature(user1, approvalParams.validators, nonOracleKey);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.registerValidators(approvalParams, signatures);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_signatureReplay() public {
        _addWithdrawableAssets(2);
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        bytes memory oracleSignatures =
            _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);

        vm.prank(user1);
        nodesManager.registerValidators(approvalParams, oracleSignatures);
        assertEq(nodesManager.nonces(user1), 1);

        // Replay same signatures (nonce 0) — reverts because nonce is now 1
        IKeeperValidators.ApprovalParams memory approvalParams2 =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash2", false);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.registerValidators(approvalParams2, oracleSignatures);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    // ======== fundValidators ========

    function test_fundValidators() public {
        _addWithdrawableAssets(2);
        _startOracleImpersonate(address(contracts.keeper));

        // Register validators first
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        bytes memory registerSignatures =
            _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);

        vm.prank(user1);
        nodesManager.registerValidators(approvalParams, registerSignatures);

        // Fund same validators
        bytes memory validators = approvalParams.validators;
        bytes memory fundSignatures = _getFundValidatorsSignature(user1, validators, _oraclePrivateKey);

        bytes memory publicKeys = _getValidatorsPublicKeys(validators);
        vm.expectEmit(true, true, true, true);
        emit INodesManager.ValidatorsFunded(user1, 1, publicKeys);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_fundValidators");
        nodesManager.fundValidators(validators, fundSignatures);
        _stopSnapshotGas();

        _stopOracleImpersonate(address(contracts.keeper));

        // Nonce should be incremented again
        assertEq(nodesManager.nonces(user1), 2);
    }

    function test_fundValidators_invalidSignatures_empty() public {
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.fundValidators(approvalParams.validators, bytes(""));

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_fundValidators_invalidSignatures_wrongLength() public {
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        // Wrong length (not a multiple of 65)
        bytes memory badSig = new bytes(64);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.fundValidators(approvalParams.validators, badSig);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_fundValidators_invalidSignatures_wrongSigner() public {
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        // Sign with a non-oracle key
        (, uint256 nonOracleKey) = makeAddrAndKey("nonOracle");
        bytes memory signatures = _getFundValidatorsSignature(user1, approvalParams.validators, nonOracleKey);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.fundValidators(approvalParams.validators, signatures);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_fundValidators_signatureReplay() public {
        _addWithdrawableAssets(3);
        _startOracleImpersonate(address(contracts.keeper));

        // Register validators first (nonce 0)
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        bytes memory registerSignatures =
            _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);

        vm.prank(user1);
        nodesManager.registerValidators(approvalParams, registerSignatures);
        assertEq(nodesManager.nonces(user1), 1);

        // Fund validators (nonce 1)
        bytes memory validators = approvalParams.validators;
        bytes memory fundSignatures = _getFundValidatorsSignature(user1, validators, _oraclePrivateKey);

        vm.prank(user1);
        nodesManager.fundValidators(validators, fundSignatures);
        assertEq(nodesManager.nonces(user1), 2);

        // Replay same fund signatures (nonce 1) — reverts because nonce is now 2
        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.fundValidators(validators, fundSignatures);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    // ======== withdrawValidators ========

    function test_withdrawValidators() public {
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        // Register a validator to collateralize the vault
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        bytes memory registerSignatures =
            _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);

        vm.prank(user1);
        nodesManager.registerValidators(approvalParams, registerSignatures);
        _stopOracleImpersonate(address(contracts.keeper));

        // Set withdrawals manager
        address wManager = makeAddr("WithdrawalsManager");
        vm.prank(owner);
        nodesManager.setWithdrawalsManager(wManager);

        // Construct withdrawal data: 48 bytes pubkey + 8 bytes amount (gwei)
        bytes memory pubKey = new bytes(48);
        bytes memory withdrawalData = bytes.concat(pubKey, bytes8(uint64(32 ether / 1 gwei)));

        // Fee is 0.1 ETH per validator in the mock
        uint256 fee = 0.1 ether;
        vm.deal(wManager, fee);

        vm.expectEmit(true, true, true, true);
        emit INodesManager.ValidatorWithdrawalSubmitted(wManager);

        vm.prank(wManager);
        _startSnapshotGas("EthNodesManagerTest_test_withdrawValidators");
        nodesManager.withdrawValidators{value: fee}(withdrawalData);
        _stopSnapshotGas();
    }

    function test_withdrawValidators_notWithdrawalsManager() public {
        // Set withdrawals manager
        address wManager = makeAddr("WithdrawalsManager");
        vm.prank(owner);
        nodesManager.setWithdrawalsManager(wManager);

        bytes memory withdrawalData = new bytes(56);

        vm.prank(user1);
        vm.expectRevert(Errors.AccessDenied.selector);
        nodesManager.withdrawValidators(withdrawalData);
    }

    function test_withdrawValidators_noWithdrawalsManager() public {
        bytes memory withdrawalData = new bytes(56);

        vm.prank(user1);
        vm.expectRevert(Errors.AccessDenied.selector);
        nodesManager.withdrawValidators(withdrawalData);
    }

    // ======== updateVaultState ========

    function test_updateVaultState() public {
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(vault, 0, 0);
        nodesManager.updateVaultState(harvestParams);
    }

    // ======== Helpers ========

    function _addWithdrawableAssets(uint256 validatorDeposits) internal {
        // A forked vault may have queued shares in the exit queue that reduce
        // withdrawableAssets, so account for those when pre-funding the vault.
        (uint128 queuedShares,,, uint128 totalExitingAssets,) = IEthVault(vault).getExitQueueData();
        uint256 queuedAssets = IEthVault(vault).convertToAssets(queuedShares) + totalExitingAssets;
        uint256 depositAmount = validatorDeposits * VALIDATOR_DEPOSIT + queuedAssets;
        vm.deal(address(this), depositAmount);
        IEthVault(vault).deposit{value: depositAmount}(address(this), address(0));
    }

    function _hashNodesManagerTypedData(bytes32 structHash) internal view returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("NodesManager")),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(nodesManager)
                )
            ),
            structHash
        );
    }

    function _getRegisterValidatorsSignature(address user, bytes memory validators, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        uint256 nonce = nodesManager.nonces(user);
        bytes32 digest = _hashNodesManagerTypedData(
            keccak256(
                abi.encode(
                    keccak256("RegisterValidators(address user,uint256 nonce,address vault,bytes validators)"),
                    user,
                    nonce,
                    vault,
                    keccak256(validators)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _getFundValidatorsSignature(address user, bytes memory validators, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        uint256 nonce = nodesManager.nonces(user);
        bytes32 digest = _hashNodesManagerTypedData(
            keccak256(
                abi.encode(
                    keccak256("FundValidators(address user,uint256 nonce,address vault,bytes validators)"),
                    user,
                    nonce,
                    vault,
                    keccak256(validators)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _getValidatorsPublicKeys(bytes memory validators) internal pure returns (bytes memory publicKeys) {
        uint256 validatorLength = 184;
        uint256 validatorsCount = validators.length / validatorLength;
        for (uint256 i = 0; i < validatorsCount; i++) {
            uint256 start = i * validatorLength;
            bytes memory pubKey = new bytes(48);
            for (uint256 j = 0; j < 48; j++) {
                pubKey[j] = validators[start + j];
            }
            publicKeys = bytes.concat(publicKeys, pubKey);
        }
    }
}
