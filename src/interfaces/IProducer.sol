// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

interface IProducer {
    function claimWETHRewards()
        external
        returns (
            ERC20[2] memory producerTokens,
            ERC20[2] memory rewardTokens,
            uint256[2] memory rewardAmounts
        );
}
