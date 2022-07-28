// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FlywheelCore} from "./FlywheelCore.sol";

/**
    Original source code:
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/rewards/FlywheelStaticRewards.sol

    Modifications:
    - Pin pragma to 0.8.13
    - Modify code formatting and comment descriptions to be consistent with Pirex
    - Merge FlywheelRewards-related contract logic
    - Remove logic for supporting multiple strategies
    - Remove modifier and unnecessary AccessControl base contract
    - Define fixed logic for reward accrual calculations
*/
contract FlywheelRewards {
    using SafeTransferLib for ERC20;

    // Amount of reward points to issue per second
    uint256 public constant REWARDS_PER_SECOND = 1;

    // Reward token
    ERC20 public immutable rewardToken;

    // FlywheelCore contract
    FlywheelCore public immutable flywheel;

    error FlywheelError();
    error ZeroAddress();

    /**
        @param  _flywheel  FlywheelCore  FlywheelCore contract
    */
    constructor(FlywheelCore _flywheel) {
        if (address(_flywheel) == address(0)) revert ZeroAddress();

        flywheel = _flywheel;
        rewardToken = _flywheel.rewardToken();

        rewardToken.safeApprove(address(_flywheel), type(uint256).max);
    }

    /**
        @notice Calculate and transfer accrued rewards to flywheel core
        @param  lastUpdatedTimestamp  uint256  The last updated time for strategy
        @return                       uint256  Amount of tokens accrued and transferred
     */
    function getAccruedRewards(uint256 lastUpdatedTimestamp)
        external
        view
        returns (uint256)
    {
        if (msg.sender != address(flywheel)) revert FlywheelError();

        return REWARDS_PER_SECOND * (block.timestamp - lastUpdatedTimestamp);
    }
}
