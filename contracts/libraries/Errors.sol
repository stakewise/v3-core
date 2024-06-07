// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title Errors
 * @author StakeWise
 * @notice Contains all the custom errors
 */
library Errors {
  error AccessDenied();
  error InvalidShares();
  error InvalidAssets();
  error ZeroAddress();
  error InsufficientAssets();
  error CapacityExceeded();
  error InvalidCapacity();
  error InvalidSecurityDeposit();
  error InvalidFeeRecipient();
  error InvalidFeePercent();
  error NotHarvested();
  error NotCollateralized();
  error InvalidProof();
  error LowLtv();
  error RedemptionExceeded();
  error InvalidPosition();
  error InvalidLtv();
  error InvalidHealthFactor();
  error InvalidReceivedAssets();
  error InvalidTokenMeta();
  error UpgradeFailed();
  error InvalidValidators();
  error DeadlineExpired();
  error PermitInvalidSigner();
  error InvalidValidatorsRegistryRoot();
  error InvalidVault();
  error AlreadyAdded();
  error AlreadyRemoved();
  error InvalidOracles();
  error NotEnoughSignatures();
  error InvalidOracle();
  error TooEarlyUpdate();
  error InvalidAvgRewardPerSecond();
  error InvalidRewardsRoot();
  error HarvestFailed();
  error LiquidationDisabled();
  error InvalidLiqThresholdPercent();
  error InvalidLiqBonusPercent();
  error InvalidLtvPercent();
  error InvalidCheckpointIndex();
  error InvalidCheckpointValue();
  error MaxOraclesExceeded();
  error ExitRequestNotProcessed();
  error ValueNotChanged();
  error EigenInvalidWithdrawal();
  error InvalidEigenQueuedWithdrawals();
  error InvalidWithdrawalCredentials();
  error EigenPodNotFound();
}
