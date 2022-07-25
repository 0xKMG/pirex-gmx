// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";
import {IFlywheelRewards} from "./IFlywheelRewards.sol";
import {FlywheelCore} from "./FlywheelCore.sol";

/**
    Original source code:
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/rewards/BaseFlywheelRewards.sol

    Modifications:
    - Pin pragma to 0.8.13
    - Modify code formatting and comment descriptions to be consistent with Pirex
*/
abstract contract BaseFlywheelRewards is IFlywheelRewards {
    using SafeTransferLib for ERC20;

    // The reward token paid
    ERC20 public immutable override rewardToken;

    // The flywheel core contract
    FlywheelCore public immutable override flywheel;

    // Thrown when caller is not the flywheel
    error FlywheelError();

    /**
        @param  _flywheel  FlywheelCore  FlywheelCore contract
    */
    constructor(FlywheelCore _flywheel) {
        flywheel = _flywheel;
        rewardToken = _flywheel.rewardToken();

        rewardToken.safeApprove(address(_flywheel), type(uint256).max);
    }

    modifier onlyFlywheel() {
        if (msg.sender != address(flywheel)) revert FlywheelError();

        _;
    }
}
