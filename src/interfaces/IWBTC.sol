// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// https://arbiscan.io/address/0x3f770ac673856f105b586bb393d122721265ad46#code
interface IWBTC {
    function balanceOf(address account) external view returns (uint256);

    function bridgeMint(address account, uint256 amount) external;

    function approve(address spender, uint256 amount) external returns (bool);
}
