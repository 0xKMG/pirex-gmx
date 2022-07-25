// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FlywheelCore} from "./FlywheelCore.sol";

/**
    Original source code:
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/interfaces/IFlywheelRewards.sol

    Modifications:
    - Pin pragma to 0.8.13
    - Update FlywheelCore file path to current directory
    - Modify code formatting and comment descriptions to be consistent with Pirex
*/
interface IFlywheelRewards {
    /**
        @notice Calculate the rewards amount accrued to a strategy since the last update
        @param  strategy              ERC20    The strategy to accrue rewards for
        @param  lastUpdatedTimestamp  uint32   The last time rewards were accrued for the strategy
        @return rewards               uint256  Rewards the amount of rewards accrued to the market
    */
    function getAccruedRewards(ERC20 strategy, uint32 lastUpdatedTimestamp)
        external
        returns (uint256 rewards);

    // Return the flywheel core address
    function flywheel() external view returns (FlywheelCore);

    // Return the reward token associated with flywheel core
    function rewardToken() external view returns (ERC20);
}
