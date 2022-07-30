// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {PirexGlp} from "./PirexGlp.sol";

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
    - Replace Flywheel accrual methods with lightweight alternatives
*/
contract FlywheelCore is Owned {
    using SafeTransferLib for ERC20;

    struct GlobalState {
        uint256 lastUpdate;
        uint256 rewards;
        uint256 wethFromGmx;
        uint256 wethFromGlp;
    }

    struct UserState {
        uint256 lastUpdate;
        uint256 lastBalance;
        uint256 rewards;
    }

    // Token to reward
    ERC20 public immutable rewardToken;

    // Strategy producing rewards
    ERC20 public strategy;

    // PirexGlp contract for claiming WETH rewards
    PirexGlp public pirexGlp;

    // Global state
    GlobalState public globalState;

    // User state
    mapping(address => UserState) public userStates;

    // Accrued but not yet transferred rewards for each user
    mapping(address => uint256) public rewardsAccrued;

    event ClaimRewards(address indexed user, uint256 amount);
    event SetStrategy(address newStrategy);
    event SetPirexGlp(address pirexGlp);

    error ZeroAddress();

    /**
        @param  _rewardToken  ERC20  Rewards token
    */
    constructor(ERC20 _rewardToken) Owned(msg.sender) {
        if (address(_rewardToken) == address(0)) revert ZeroAddress();

        rewardToken = _rewardToken;
    }

    /**
        @notice Claim rewards for a given user
        @param  user  address  The user claiming rewards
    */
    function claimRewards(address user) external {
        uint256 accrued = rewardsAccrued[user];

        if (accrued != 0) {
            rewardsAccrued[user] = 0;

            rewardToken.safeTransfer(user, accrued);

            emit ClaimRewards(user, accrued);
        }
    }

    /**
        @notice Set the strategy
        @param  _strategy  ERC20  Strategy
    */
    function setStrategyForRewards(ERC20 _strategy) external onlyOwner {
        if (address(_strategy) == address(0)) revert ZeroAddress();

        strategy = _strategy;

        emit SetStrategy(address(_strategy));
    }

    /**
        @notice Set pirexGlp
        @param  _pirexGlp  PirexGlp  PirexGlp contract
    */
    function setPirexGlp(PirexGlp _pirexGlp) external onlyOwner {
        if (address(_pirexGlp) == address(0)) revert ZeroAddress();

        pirexGlp = _pirexGlp;

        emit SetPirexGlp(address(_pirexGlp));
    }

    /**
        @notice Update global rewards accrual state
    */
    function globalAccrue() external {
        (uint256 fromGmx, uint256 fromGlp, ) = pirexGlp.claimWETHRewards();

        globalState = GlobalState({
            lastUpdate: block.timestamp,
            // Calculate the latest global rewards accrued based on the seconds elapsed * total supply
            rewards: globalState.rewards +
                (block.timestamp - globalState.lastUpdate) *
                strategy.totalSupply(),
            wethFromGmx: fromGmx,
            wethFromGlp: fromGlp
        });
    }

    /**
        @notice Update user rewards accrual state
        @param  user  address  User
    */
    function userAccrue(address user) external {
        UserState storage u = userStates[user];

        // Calculate the amount of rewards accrued by the user up to this call
        u.rewards =
            u.rewards +
            u.lastBalance *
            (block.timestamp - u.lastUpdate);
        u.lastUpdate = block.timestamp;
        u.lastBalance = strategy.balanceOf(user);
    }
}
