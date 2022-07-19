// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// RewardRouterV2.sol https://arbiscan.io/address/0xa906f338cb21815cbc4bc87ace9e68c87ef8d8f1#code
interface IRewardRouterV2 {
    function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp)
        external
        payable
        returns (uint256);
}
