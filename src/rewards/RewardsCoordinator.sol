// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

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

    // Producer token addresses mapped to their respective global states
    mapping(address => GlobalState) public globalStates;

    // Producer token addresses mapped to their users' state
    mapping(address => mapping(address => UserState)) public userStates;
}
