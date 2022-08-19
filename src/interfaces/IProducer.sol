// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

interface IProducer {
    function claimRewards()
        external
        returns (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        );

    function claimUserReward(
        address recipient,
        address rewardTokenAddress,
        uint256 rewardAmount
    ) external;
}
