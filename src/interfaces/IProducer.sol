// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IProducer {
    function claimWETHRewards(address receiver)
        external
        returns (
            address[] memory producerTokens,
            uint256[] memory rewardAmounts
        );
}
