// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {FlywheelRewards} from "./FlywheelRewards.sol";

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
    - Add new logic for managing global and user reward accrual state
    - Remove logic for supporting multiple strategies
    - Update to reflect consolidation of pxGLP's FlywheelRewards-related contract
    - Replace accrual methods with lightweight alternatives
*/
contract FlywheelCore is AccessControl {
    using SafeTransferLib for ERC20;

    struct GlobalState {
        uint256 lastUpdate;
        uint256 rewards;
    }

    struct UserState {
        uint256 lastUpdate;
        uint256 lastBalance;
        uint256 rewards;
    }

    // Global state
    GlobalState public globalState;

    // User state
    mapping(address => UserState) public userStates;

    // Token to reward
    ERC20 public immutable rewardToken;

    // Strategy producing rewards
    ERC20 public strategy;

    // Rewards contract for managing streams
    FlywheelRewards public flywheelRewards;

    // Accrued but not yet transferred rewards for each user
    mapping(address => uint256) public rewardsAccrued;

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
        @notice Set the strategy
        @param  _strategy  ERC20  Strategy
    */
    function setStrategyForRewards(ERC20 _strategy)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (address(_strategy) == address(0)) revert ZeroAddress();

        strategy = _strategy;

        emit AddStrategy(address(_strategy));
    }

    /**
        @notice Set the FlywheelRewards contract
        @param  newFlywheelRewards  FlywheelRewards  New FlywheelRewards contract
    */
    function setFlywheelRewards(FlywheelRewards newFlywheelRewards)
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
        @notice Update global rewards accrual state
    */
    function globalAccrue() external {
        globalState = GlobalState({
            lastUpdate: block.timestamp,
            // Calculate the latest global rewards accrued based on the seconds elapsed * total supply
            rewards: globalState.rewards + (block.timestamp - globalState.lastUpdate) * strategy.totalSupply()
        });
    }

    /**
        @notice Update user rewards accrual state
        @param  user  address  User
    */
    function userAccrue(address user) external {
        UserState storage u = userStates[user];

        // Calculate the amount of rewards accrued by the user up to this call
        u.rewards = u.rewards + u.lastBalance * (block.timestamp - u.lastUpdate);
        u.lastUpdate = block.timestamp;
        u.lastBalance = strategy.balanceOf(user);
    }
}
