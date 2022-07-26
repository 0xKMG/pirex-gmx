// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {BaseFlywheelRewards} from "./BaseFlywheelRewards.sol";
import {FlywheelCore} from "./FlywheelCore.sol";

/**
    Original source code:
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/rewards/FlywheelStaticRewards.sol

    Modifications:
    - Pin pragma to 0.8.13
    - Modify code formatting and comment descriptions to be consistent with Pirex
*/
contract FlywheelStaticRewards is AccessControl, BaseFlywheelRewards {
    struct RewardsInfo {
        // Rewards per second
        uint224 rewardsPerSecond;
        // The timestamp the rewards end at (0 = no end)
        uint32 rewardsEndTimestamp;
    }

    // Rewards info per strategy
    mapping(ERC20 => RewardsInfo) public rewardsInfo;

    event RewardsInfoUpdate(
        ERC20 indexed strategy,
        uint224 rewardsPerSecond,
        uint32 rewardsEndTimestamp
    );

    error ZeroAddress();

    /**
        @param  _flywheel   FlywheelCore  FlywheelCore contract
        @param  _owner      address       Owner address
    */
    constructor(FlywheelCore _flywheel, address _owner)
        BaseFlywheelRewards(_flywheel)
    {
        if (address(_flywheel) == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();

        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    /**
        @notice Set rewards per second and rewards end time for Fei Rewards
        @param  strategy  ERC20        The strategy to accrue rewards for
        @param  rewards   RewardsInfo  The rewards info for the strategy
     */
    function setRewardsInfo(ERC20 strategy, RewardsInfo calldata rewards)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        rewardsInfo[strategy] = rewards;

        emit RewardsInfoUpdate(
            strategy,
            rewards.rewardsPerSecond,
            rewards.rewardsEndTimestamp
        );
    }

    /**
        @notice Calculate and transfer accrued rewards to flywheel core
        @param  strategy              ERC20    The strategy to accrue rewards for
        @param  lastUpdatedTimestamp  uint32   The last updated time for strategy
        @return amount                uint256  Amount of tokens accrued and transferred
     */
    function getAccruedRewards(ERC20 strategy, uint32 lastUpdatedTimestamp)
        external
        view
        override
        onlyFlywheel
        returns (uint256 amount)
    {
        RewardsInfo memory rewards = rewardsInfo[strategy];
        uint256 elapsed;

        if (
            rewards.rewardsEndTimestamp == 0 ||
            rewards.rewardsEndTimestamp > block.timestamp
        ) {
            elapsed = block.timestamp - lastUpdatedTimestamp;
        } else if (rewards.rewardsEndTimestamp > lastUpdatedTimestamp) {
            elapsed = rewards.rewardsEndTimestamp - lastUpdatedTimestamp;
        }

        amount = rewards.rewardsPerSecond * elapsed;
    }
}
