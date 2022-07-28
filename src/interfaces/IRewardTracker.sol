// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// https://arbiscan.io/address/0x4e971a87900b931ff39d1aad67697f49835400b6#code
interface IRewardTracker {
    function claimable(address _account) external view returns (uint256);
}
