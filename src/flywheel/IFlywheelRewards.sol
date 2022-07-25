// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FlywheelCore} from "./FlywheelCore.sol";

// https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/interfaces/IFlywheelRewards.sol
/**
  Modifications
    - Pin pragma to 0.8.13
    - Update FlywheelCore file path to current directory
*/
interface IFlywheelRewards {
    /**
     @notice calculate the rewards amount accrued to a strategy since the last update.
     @param strategy the strategy to accrue rewards for.
     @param lastUpdatedTimestamp the last time rewards were accrued for the strategy.
     @return rewards the amount of rewards accrued to the market
    */
    function getAccruedRewards(ERC20 strategy, uint32 lastUpdatedTimestamp)
        external
        returns (uint256 rewards);

    /// @notice return the flywheel core address
    function flywheel() external view returns (FlywheelCore);

    /// @notice return the reward token associated with flywheel core.
    function rewardToken() external view returns (ERC20);
}
