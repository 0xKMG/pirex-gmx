// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {IFlywheelRewards} from "./IFlywheelRewards.sol";

/**
    Original source code:
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/FlywheelCore.sol

    Modifications:
    - Pin pragma to 0.8.13
    - Remove the Flywheel Booster and related logic
    - Update IFlywheelRewards file path to current directory
    - Move variables and even declarations to the top of the contract
    - Modify code formatting and comment descriptions to be consistent with Pirex
    - Consolidate addStrategyForRewards and _addStrategyForRewards
*/
contract FlywheelCore is Auth {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    struct RewardsState {
        // The strategy's last updated index
        uint224 index;

        // The timestamp the index was last updated at
        uint32 lastUpdatedTimestamp;
    }

    // The fixed point factor of flywheel
    uint224 public constant ONE = 1e18;

    // The token to reward
    ERC20 public immutable rewardToken;

    // Append-only list of strategies added
    ERC20[] public allStrategies;

    // The rewards contract for managing streams
    IFlywheelRewards public flywheelRewards;

    // The accrued but not yet transferred rewards for each user
    mapping(address => uint256) public rewardsAccrued;

    // The strategy index and last updated per strategy
    mapping(ERC20 => RewardsState) public strategyState;

    // User index per strategy
    mapping(ERC20 => mapping(address => uint224)) public userIndex;

    /**
        @notice Emitted when a user's rewards accrue to a given strategy
        @param  strategy      ERC20    The updated rewards strategy
        @param  user          address  The user of the rewards
        @param  rewardsDelta  uint256  How many new rewards accrued to the user
        @param  rewardsIndex  uint256  The market index for rewards per token accrued
    */
    event AccrueRewards(
        ERC20 indexed strategy,
        address indexed user,
        uint256 rewardsDelta,
        uint256 rewardsIndex
    );

    /**
        @notice Emitted when a user claims accrued rewards
        @param  user    address  The user of the rewards
        @param  amount  uint256  The amount of rewards claimed
    */
    event ClaimRewards(address indexed user, uint256 amount);

    /**
        @notice Emitted when a new strategy is added to flywheel by the admin
        @param  newStrategy  address  The new added strategy
    */
    event AddStrategy(address indexed newStrategy);

    /**
        @notice Emitted when the rewards module changes
        @param  newFlywheelRewards  address  The new rewards module
    */
    event FlywheelRewardsUpdate(address indexed newFlywheelRewards);

    /**
        @param  _rewardToken      ERC20             Rewards token
        @param  _flywheelRewards  IFlywheelRewards  FlywheelRewards contract
        @param  _owner            address           Contract owner
        @param  _authority        Authority         Authority contract
    */
    constructor(
        ERC20 _rewardToken,
        IFlywheelRewards _flywheelRewards,
        address _owner,
        Authority _authority
    ) Auth(_owner, _authority) {
        rewardToken = _rewardToken;
        flywheelRewards = _flywheelRewards;
    }

    /**
        @notice Accrue rewards for a single user on a strategy
        @param  strategy  ERC20    The strategy to accrue a user's rewards on
        @param  user      address  The user to be accrued
        @return The cumulative amount of rewards accrued to user (including prior)
    */
    function accrue(ERC20 strategy, address user) public returns (uint256) {
        RewardsState memory state = strategyState[strategy];

        if (state.index == 0) return 0;

        state = accrueStrategy(strategy, state);

        return accrueUser(strategy, user, state);
    }

    /**
        @notice Accrue rewards for a two users on a strategy
        @param  strategy    ERC20    The strategy to accrue a user's rewards on
        @param  user        address  The first user to be accrued
        @param  secondUser  address  The second user to be accrued
        @return             uint256  The cumulative amount of the first user's rewards accrued
        @return             uint256  The cumulative amount of the second user's rewards accrued
    */
    function accrue(
        ERC20 strategy,
        address user,
        address secondUser
    ) public returns (uint256, uint256) {
        RewardsState memory state = strategyState[strategy];

        if (state.index == 0) return (0, 0);

        state = accrueStrategy(strategy, state);

        return (
            accrueUser(strategy, user, state),
            accrueUser(strategy, secondUser, state)
        );
    }

    /**
        @notice Claim rewards for a given user
        @param  user  address  The user claiming rewards
    */
    function claimRewards(address user) external {
        uint256 accrued = rewardsAccrued[user];

        if (accrued != 0) {
            rewardsAccrued[user] = 0;

            rewardToken.safeTransferFrom(
                address(flywheelRewards),
                user,
                accrued
            );

            emit ClaimRewards(user, accrued);
        }
    }

    /**
        @notice Initialize a new strategy
        @param  strategy  ERC20  New strategy
    */
    function addStrategyForRewards(ERC20 strategy) external requiresAuth {
        require(strategyState[strategy].index == 0, "strategy");

        strategyState[strategy] = RewardsState({
            index: ONE,
            lastUpdatedTimestamp: block.timestamp.safeCastTo32()
        });

        allStrategies.push(strategy);

        emit AddStrategy(address(strategy));
    }

    /**
        @notice Get strategy contracts
        @return ERC20[]  Strategy contracts
    */
    function getAllStrategies() external view returns (ERC20[] memory) {
        return allStrategies;
    }

    /**
        @notice Set the FlywheelRewards contract
        @param  newFlywheelRewards  IFlywheelRewards  New FlywheelRewards contract
    */
    function setFlywheelRewards(IFlywheelRewards newFlywheelRewards)
        external
        requiresAuth
    {
        uint256 oldRewardBalance = rewardToken.balanceOf(
            address(flywheelRewards)
        );

        if (oldRewardBalance > 0) {
            rewardToken.safeTransferFrom(
                address(flywheelRewards),
                address(newFlywheelRewards),
                oldRewardBalance
            );
        }

        flywheelRewards = newFlywheelRewards;

        emit FlywheelRewardsUpdate(address(newFlywheelRewards));
    }

    /**
        @notice Accrue rewards for a strategy
        @param  strategy      ERC20         Strategy contract
        @param  state         RewardsState  Reward state input
        @return rewardsState  RewardsState  Reward state output
    */
    function accrueStrategy(ERC20 strategy, RewardsState memory state)
        private
        returns (RewardsState memory rewardsState)
    {
        // Calculate accrued rewards through module
        uint256 strategyRewardsAccrued = flywheelRewards.getAccruedRewards(
            strategy,
            state.lastUpdatedTimestamp
        );

        rewardsState = state;

        if (strategyRewardsAccrued > 0) {
            uint256 supplyTokens = strategy.totalSupply();

            uint224 deltaIndex;

            if (supplyTokens != 0)
                deltaIndex = ((strategyRewardsAccrued * ONE) / supplyTokens)
                    .safeCastTo224();

            // Accumulate rewards per token onto the index, multiplied by fixed-point factor
            rewardsState = RewardsState({
                index: state.index + deltaIndex,
                lastUpdatedTimestamp: block.timestamp.safeCastTo32()
            });

            strategyState[strategy] = rewardsState;
        }
    }

    /**
        @notice Accrue rewards for a user
        @param  strategy  ERC20         Strategy contract
        @param  user      address       User
        @param  state     RewardsState  Reward state input
        @return           uint256       User rewards
    */
    function accrueUser(
        ERC20 strategy,
        address user,
        RewardsState memory state
    ) private returns (uint256) {
        // Load indices
        uint224 strategyIndex = state.index;
        uint224 supplierIndex = userIndex[strategy][user];

        // Sync user index to global
        userIndex[strategy][user] = strategyIndex;

        // If user hasn't yet accrued rewards, grant them interest from the strategy beginning if they have a balance
        // Zero balances will have no effect other than syncing to global index
        if (supplierIndex == 0) {
            supplierIndex = ONE;
        }

        uint224 deltaIndex = strategyIndex - supplierIndex;
        uint256 supplierTokens = strategy.balanceOf(user);

        // Accumulate rewards by multiplying user tokens by rewardsPerToken index and adding on unclaimed
        uint256 supplierDelta = (supplierTokens * deltaIndex) / ONE;
        uint256 supplierAccrued = rewardsAccrued[user] + supplierDelta;

        rewardsAccrued[user] = supplierAccrued;

        emit AccrueRewards(strategy, user, supplierDelta, strategyIndex);

        return supplierAccrued;
    }
}
