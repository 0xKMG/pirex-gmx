// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {PirexGlp} from "./PirexGlp.sol";

/**
    Originally inspired by Flywheel V2 (thank you Tribe team):
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/FlywheelCore.sol
*/
contract PxGlpRewards is Owned {
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
