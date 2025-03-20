// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {GnoHelpers} from '../helpers/GnoHelpers.sol';
import {Errors} from '../../contracts/libraries/Errors.sol';
import {IGnoErc20Vault} from '../../contracts/interfaces/IGnoErc20Vault.sol';
import {GnoErc20Vault} from '../../contracts/vaults/gnosis/GnoErc20Vault.sol';

contract GnoErc20VaultTest is Test, GnoHelpers {
  ForkContracts public contracts;
  GnoErc20Vault public vault;

  address public sender;
  address public receiver;
  address public admin;
  address public other;
  address public referrer = address(0);

  function setUp() public {
    // Activate Gnosis fork and get the contracts
    contracts = _activateGnosisFork();

    // Set up test accounts
    sender = makeAddr('sender');
    receiver = makeAddr('receiver');
    admin = makeAddr('admin');
    other = makeAddr('other');

    // Fund accounts with GNO for testing
    _mintGnoToken(sender, 100 ether);
    _mintGnoToken(other, 100 ether);
    _mintGnoToken(admin, 100 ether);

    // create vault
    bytes memory initParams = abi.encode(
      IGnoErc20Vault.GnoErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        name: 'SW GNO Vault',
        symbol: 'SW-GNO-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _getOrCreateVault(VaultType.GnoErc20Vault, admin, initParams, false);
    vault = GnoErc20Vault(payable(_vault));
  }

  function test_cannotInitializeTwice() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    vault.initialize('0x');
  }

  function test_depositEmitsTransfer() public {}

  function test_enterExitQueueEmitsTransfer() public {}

  function test_cannotTransferSharesWithLowLtv() public {}

  function test_canTransferSharesWithHighLtv() public {}

  function test_deploysCorrectly() public {
    // create vault
    bytes memory initParams = abi.encode(
      IGnoErc20Vault.GnoErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        name: 'SW GNO Vault',
        symbol: 'SW-GNO-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );

    _startSnapshotGas('GnoErc20VaultTest_test_deploysCorrectly');
    address _vault = _createVault(VaultType.GnoErc20Vault, admin, initParams, false);
    _stopSnapshotGas();
    GnoErc20Vault erc20Vault = GnoErc20Vault(payable(_vault));

    assertEq(erc20Vault.vaultId(), keccak256('GnoErc20Vault'));
    assertEq(erc20Vault.version(), 3);
    assertEq(erc20Vault.admin(), admin);
    assertEq(erc20Vault.capacity(), 1000 ether);
    assertEq(erc20Vault.feePercent(), 1000);
    assertEq(erc20Vault.feeRecipient(), admin);
    assertEq(erc20Vault.validatorsManager(), _depositDataRegistry);
    assertEq(erc20Vault.queuedShares(), 0);
    assertEq(erc20Vault.totalShares(), _securityDeposit);
    assertEq(erc20Vault.totalAssets(), _securityDeposit);
    assertEq(erc20Vault.totalExitingAssets(), 0);
    assertEq(erc20Vault.validatorsManagerNonce(), 0);
    assertEq(erc20Vault.totalSupply(), _securityDeposit);
    assertEq(erc20Vault.symbol(), 'SW-GNO-1');
    assertEq(erc20Vault.name(), 'SW GNO Vault');
  }

  function test_upgradesCorrectly() public {
    // create prev version vault
    bytes memory initParams = abi.encode(
      IGnoErc20Vault.GnoErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        name: 'SW GNO Vault',
        symbol: 'SW-GNO-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _createPrevVersionVault(VaultType.GnoErc20Vault, admin, initParams, false);
    GnoErc20Vault erc20Vault = GnoErc20Vault(payable(_vault));

    _depositToVault(address(erc20Vault), 15 ether, admin, admin);
    _registerGnoValidator(address(erc20Vault), 1 ether, true);

    vm.prank(admin);
    erc20Vault.enterExitQueue(10 ether, admin);

    uint256 totalSharesBefore = erc20Vault.totalShares();
    uint256 totalAssetsBefore = erc20Vault.totalAssets();
    uint256 totalExitingAssetsBefore = erc20Vault.totalExitingAssets();
    uint256 queuedSharesBefore = erc20Vault.queuedShares();

    assertEq(erc20Vault.vaultId(), keccak256('GnoErc20Vault'));
    assertEq(erc20Vault.version(), 2);
    assertEq(
      contracts.gnoToken.allowance(address(erc20Vault), address(contracts.validatorsRegistry)),
      0
    );

    _startSnapshotGas('GnoErc20VaultTest_test_upgradesCorrectly');
    _upgradeVault(VaultType.GnoErc20Vault, address(erc20Vault));
    _stopSnapshotGas();

    assertEq(erc20Vault.vaultId(), keccak256('GnoErc20Vault'));
    assertEq(erc20Vault.version(), 3);
    assertEq(erc20Vault.admin(), admin);
    assertEq(erc20Vault.capacity(), 1000 ether);
    assertEq(erc20Vault.feePercent(), 1000);
    assertEq(erc20Vault.feeRecipient(), admin);
    assertEq(erc20Vault.validatorsManager(), _depositDataRegistry);
    assertEq(erc20Vault.queuedShares(), queuedSharesBefore);
    assertEq(erc20Vault.totalShares(), totalSharesBefore);
    assertEq(erc20Vault.totalAssets(), totalAssetsBefore);
    assertEq(erc20Vault.totalExitingAssets(), totalExitingAssetsBefore);
    assertEq(erc20Vault.validatorsManagerNonce(), 0);
    assertEq(
      contracts.gnoToken.allowance(address(erc20Vault), address(contracts.validatorsRegistry)),
      type(uint256).max
    );
    assertEq(erc20Vault.totalSupply(), totalSharesBefore);
    assertEq(erc20Vault.symbol(), 'SW-GNO-1');
    assertEq(erc20Vault.name(), 'SW GNO Vault');
  }

  // Helper function to deposit GNO to the vault
  function _depositGno(uint256 amount, address from, address to) internal {
    _depositToVault(address(vault), amount, from, to);
  }
}
