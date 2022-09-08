// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

library Common {
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
}
