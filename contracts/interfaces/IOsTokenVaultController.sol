// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

/**
 * @title IOsTokenVaultController
 * @author StakeWise
 * @notice Defines the interface for the OsTokenVaultController contract
 */
interface IOsTokenVaultController {
  /**
   * @notice Event emitted on minting shares
   * @param vault The address of the Vault
   * @param receiver The address that received the shares
   * @param assets The number of assets collateralized
   * @param shares The number of tokens the owner received
   */
  event Mint(address indexed vault, address indexed receiver, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on burning shares
   * @param vault The address of the Vault
   * @param owner The address that owns the shares
   * @param assets The total number of assets withdrawn
   * @param shares The total number of shares burned
   */
  event Burn(address indexed vault, address indexed owner, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on state update
   * @param profitAccrued The profit accrued since the last update
   * @param treasuryShares The number of shares minted for the treasury
   * @param treasuryAssets The number of assets minted for the treasury
   */
  event StateUpdated(uint256 profitAccrued, uint256 treasuryShares, uint256 treasuryAssets);

  /**
   * @notice Event emitted on capacity update
   * @param capacity The amount after which the OsToken stops accepting deposits
   */
  event CapacityUpdated(uint256 capacity);

  /**
   * @notice Event emitted on treasury address update
   * @param treasury The new treasury address
   */
  event TreasuryUpdated(address indexed treasury);

  /**
   * @notice Event emitted on fee percent update
   * @param feePercent The new fee percent
   */
  event FeePercentUpdated(uint16 feePercent);

  /**
   * @notice Event emitted on average reward per second update
   * @param avgRewardPerSecond The new average reward per second
   */
  event AvgRewardPerSecondUpdated(uint256 avgRewardPerSecond);

  /**
   * @notice Event emitted on keeper address update
   * @param keeper The new keeper address
   */
  event KeeperUpdated(address keeper);

  /**
   * @notice The OsToken capacity
   * @return The amount after which the OsToken stops accepting deposits
   */
  function capacity() external view returns (uint256);

  /**
   * @notice The DAO treasury address that receives OsToken fees
   * @return The address of the treasury
   */
  function treasury() external view returns (address);

  /**
   * @notice The fee percent (multiplied by 100)
   * @return The fee percent applied by the OsToken on the rewards
   */
  function feePercent() external view returns (uint64);

  /**
   * @notice The address that can update avgRewardPerSecond
   * @return The address of the keeper contract
   */
  function keeper() external view returns (address);

  /**
   * @notice The average reward per second used to mint OsToken rewards
   * @return The average reward per second earned by the Vaults
   */
  function avgRewardPerSecond() external view returns (uint256);

  /**
   * @notice The fee per share used for calculating the fee for every position
   * @return The cumulative fee per share
   */
  function cumulativeFeePerShare() external view returns (uint256);

  /**
   * @notice The total number of shares controlled by the OsToken
   * @return The total number of shares
   */
  function totalShares() external view returns (uint256);

  /**
   * @notice Total assets controlled by the OsToken
   * @return The total amount of the underlying asset that is "managed" by OsToken
   */
  function totalAssets() external view returns (uint256);

  /**
   * @notice Converts shares to assets
   * @param assets The amount of assets to convert to shares
   * @return shares The amount of shares that the OsToken would exchange for the amount of assets provided
   */
  function convertToShares(uint256 assets) external view returns (uint256 shares);

  /**
   * @notice Converts assets to shares
   * @param shares The amount of shares to convert to assets
   * @return assets The amount of assets that the OsToken would exchange for the amount of shares provided
   */
  function convertToAssets(uint256 shares) external view returns (uint256 assets);

  /**
   * @notice Updates rewards and treasury fee checkpoint for the OsToken
   */
  function updateState() external;

  /**
   * @notice Mint OsToken shares. Can only be called by the registered vault.
   * @param receiver The address that will receive the shares
   * @param shares The amount of shares to mint
   * @return assets The amount of assets minted
   */
  function mintShares(address receiver, uint256 shares) external returns (uint256 assets);

  /**
   * @notice Burn shares for withdrawn assets. Can only be called by the registered vault.
   * @param owner The address that owns the shares
   * @param shares The amount of shares to burn
   * @return assets The amount of assets withdrawn
   */
  function burnShares(address owner, uint256 shares) external returns (uint256 assets);

  /**
   * @notice Update treasury address. Can only be called by the owner.
   * @param _treasury The new treasury address
   */
  function setTreasury(address _treasury) external;

  /**
   * @notice Update capacity. Can only be called by the owner.
   * @param _capacity The amount after which the OsToken stops accepting deposits
   */
  function setCapacity(uint256 _capacity) external;

  /**
   * @notice Update fee percent. Can only be called by the owner. Cannot be larger than 10 000 (100%).
   * @param _feePercent The new fee percent
   */
  function setFeePercent(uint16 _feePercent) external;

  /**
   * @notice Update keeper address. Can only be called by the owner.
   * @param _keeper The new keeper address
   */
  function setKeeper(address _keeper) external;

  /**
   * @notice Updates average reward per second. Can only be called by the keeper.
   * @param _avgRewardPerSecond The new average reward per second
   */
  function setAvgRewardPerSecond(uint256 _avgRewardPerSecond) external;
}
