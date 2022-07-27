// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
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
    - Update accrueStrategy and accrueUser to use rewards accrued/s when calculating delta
    - Add new methods for managing global and user reward accrual state
*/
contract FlywheelCore is AccessControl {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    struct RewardsState {
        // The strategy's last updated index
        uint224 index;
        // The timestamp the index was last updated at
        uint32 lastUpdatedTimestamp;
    }

    struct Global {
        uint256 lastUpdate;
        uint256 rewards;
    }

    struct User {
        uint256 lastUpdate;
        uint256 lastBalance;
        uint256 rewards;
    }

    // Global state
    Global public global;

    // User state
    mapping(address => User) public users;

    uint224 STARTING_INDEX = 1;

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

    // Previous user balance per strategy
    mapping(ERC20 => mapping(address => uint256)) public previousUserBalance;

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

    error ZeroAddress();

    /**
        @param  _rewardToken      ERC20             Rewards token
        @param  _owner            address           Contract owner
    */
    constructor(ERC20 _rewardToken, address _owner) {
        if (address(_rewardToken) == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();

        rewardToken = _rewardToken;

        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
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
    function addStrategyForRewards(ERC20 strategy)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(strategyState[strategy].index == 0, "strategy");

        strategyState[strategy] = RewardsState({
            index: STARTING_INDEX,
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
        onlyRole(DEFAULT_ADMIN_ROLE)
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
            // Update rewardState based on amount of rewards/s accrued since last update
            rewardsState = RewardsState({
                index: state.index + strategyRewardsAccrued.safeCastTo224(),
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

        // First-time user who should not have any rewards accrued
        if (supplierIndex == 0) {
            supplierIndex = strategyIndex;
        }

        // Sync user index to global
        userIndex[strategy][user] = strategyIndex;
        uint224 deltaIndex = strategyIndex - supplierIndex;

        // Use the user's previous balance to calculate rewards accrued to-date
        uint256 supplierTokens = previousUserBalance[strategy][user];

        // Update the user's previous balance
        previousUserBalance[strategy][user] = strategy.balanceOf(user);

        // Accumulate rewards by multiplying user tokens by rewardsPerToken index and adding on unclaimed
        uint256 supplierDelta = (supplierTokens * deltaIndex) /
            strategy.totalSupply();
        uint256 supplierAccrued = rewardsAccrued[user] + supplierDelta;

        rewardsAccrued[user] = supplierAccrued;

        emit AccrueRewards(strategy, user, supplierDelta, strategyIndex);

        return supplierAccrued;
    }

    /**
        @notice Update global rewards accrual state
        @param  strategy  ERC20  Strategy contract
    */
    function globalAccrue(ERC20 strategy) external {
        global = Global({
            lastUpdate: block.timestamp,
            // Calculate the latest global rewards accrued based on the seconds elapsed * total supply
            rewards: global.rewards + (block.timestamp - global.lastUpdate) * strategy.totalSupply()
        });
    }

    /**
        @notice Update user rewards accrual state
        @param  strategy  ERC20    Strategy contract
        @param  user      address  User
    */
    function userAccrue(ERC20 strategy, address user) external {
        User storage u = users[user];

        // Calculate the amount of rewards accrued by the user up to this call
        u.rewards = u.rewards + u.lastBalance * (block.timestamp - u.lastUpdate);
        u.lastUpdate = block.timestamp;
        u.lastBalance = strategy.balanceOf(user);
    }
}
