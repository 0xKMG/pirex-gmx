// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IERC4626 {
    function totalAssets() external view returns (uint256);

    function maxWithdraw(address owner) external view returns (uint256);
}
