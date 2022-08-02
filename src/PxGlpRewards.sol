// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {PirexGlp} from "./PirexGlp.sol";

/**
    Originally inspired by Flywheel V2 (thank you Tribe team):
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/FlywheelCore.sol
*/
contract PxGlpRewards is Owned {
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

    ERC20 public constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

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
    event ClaimWETHRewards(
        address indexed caller,
        address indexed receiver,
        uint256 globalRewardsBeforeClaim,
        uint256 userRewardsBeforeClaim,
        uint256 wethFromGmx,
        uint256 wethFromGlp
    );

    error ZeroAddress();

    constructor() Owned(msg.sender) {}

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
    function globalAccrue() public returns (GlobalState memory) {
        (uint256 fromGmx, uint256 fromGlp, ) = pirexGlp.claimWETHRewards();

        globalState = GlobalState({
            lastUpdate: block.timestamp,
            // Calculate the latest global rewards accrued based on the seconds elapsed * total supply
            rewards: globalState.rewards +
                (block.timestamp - globalState.lastUpdate) *
                strategy.totalSupply(),
            wethFromGmx: globalState.wethFromGmx + fromGmx,
            wethFromGlp: globalState.wethFromGlp + fromGlp
        });

        return globalState;
    }

    /**
        @notice Update user rewards accrual state
        @param  user  address  User
    */
    function userAccrue(address user) public returns (UserState memory) {
        UserState storage u = userStates[user];

        // Calculate the amount of rewards accrued by the user up to this call
        u.rewards =
            u.rewards +
            u.lastBalance *
            (block.timestamp - u.lastUpdate);
        u.lastUpdate = block.timestamp;
        u.lastBalance = strategy.balanceOf(user);

        return u;
    }

    /**
        @notice Claim WETH rewards for user
        @param  receiver  address  Recipient of WETH rewards
    */
    function claimWETHRewards(address receiver) external {
        if (receiver == address(0)) revert ZeroAddress();

        GlobalState memory g = globalAccrue();
        UserState memory u = userAccrue(msg.sender);

        // User's share of global WETH rewards earned from GMX and GLP
        uint256 wethFromGmx = (g.wethFromGmx * u.rewards) / g.rewards;
        uint256 wethFromGlp = (g.wethFromGlp * u.rewards) / g.rewards;

        // Update global and user reward states to prevent double claims
        globalState.rewards = globalState.rewards - u.rewards;
        globalState.wethFromGmx = g.wethFromGmx - wethFromGmx;
        globalState.wethFromGlp = g.wethFromGlp - wethFromGlp;
        userStates[msg.sender].rewards = 0;

        emit ClaimWETHRewards(
            msg.sender,
            receiver,
            g.rewards,
            u.rewards,
            wethFromGmx,
            wethFromGlp
        );

        WETH.safeTransfer(receiver, wethFromGmx + wethFromGlp);
    }
}
