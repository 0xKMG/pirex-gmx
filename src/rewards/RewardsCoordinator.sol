// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

/**
    Originally inspired by Flywheel V2 (thank you Tribe team):
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/FlywheelCore.sol
*/
contract RewardsCoordinator {
    struct GlobalState {
        uint256 lastUpdate;
        uint256 lastSupply;
        uint256 rewards;
    }

    struct UserState {
        uint256 lastUpdate;
        uint256 lastBalance;
        uint256 rewards;
    }

    // Producer tokens mapped to their respective global states
    mapping(ERC20 => GlobalState) public globalStates;

    // Producer tokens mapped to their users' state
    mapping(ERC20 => mapping(address => UserState)) public userStates;

    event GlobalAccrue(
        ERC20 indexed producerToken,
        uint256 lastUpdate,
        uint256 lastSupply,
        uint256 rewards
    );

    error ZeroAddress();

    /**
        @notice Update global rewards accrual state
        @param  producerToken  ERC20  Rewards-producing token
    */
    function globalAccrue(ERC20 producerToken) public {
        if (address(producerToken) == address(0)) revert ZeroAddress();

        GlobalState memory g = globalStates[producerToken];
        uint256 timestamp = block.timestamp;
        uint256 totalSupply = producerToken.totalSupply();

        // Calculate rewards, the product of seconds elapsed and last supply
        uint256 rewards = g.rewards + (timestamp - g.lastUpdate) * g.lastSupply;

        globalStates[producerToken] = GlobalState({
            lastUpdate: timestamp,
            lastSupply: totalSupply,
            rewards: rewards
        });

        emit GlobalAccrue(producerToken, timestamp, totalSupply, rewards);
    }
}
