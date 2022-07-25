// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {Auth, Authority} from "solmate/auth/Auth.sol";
import {BaseFlywheelRewards} from "./BaseFlywheelRewards.sol";

/**
    Original source code:
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/rewards/FlywheelStaticRewards.sol

    Modifications:
    - Pin pragma to 0.8.13
    - Modify code formatting and comment descriptions to be consistent with Pirex
*/
contract FlywheelStaticRewards is Auth, BaseFlywheelRewards {
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

    /**
    @param  _flywheel   FlywheelCore  FlywheelCore contract
    @param  _owner      address       Owner address
    @param  _authority  Authority     Authority contract
 */
    constructor(
        FlywheelCore _flywheel,
        address _owner,
        Authority _authority
    ) Auth(_owner, _authority) BaseFlywheelRewards(_flywheel) {}

    /**
        @notice Set rewards per second and rewards end time for Fei Rewards
        @param  strategy  ERC20        The strategy to accrue rewards for
        @param  rewards   RewardsInfo  The rewards info for the strategy
     */
    function setRewardsInfo(ERC20 strategy, RewardsInfo calldata rewards)
        external
        requiresAuth
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
