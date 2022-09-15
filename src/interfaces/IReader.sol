// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// https://arbiscan.io/address/0x22199a49A999c351eF7927602CFB187ec3cae489#code
interface IReader {
    function getTokenBalancesWithSupplies(
        address _account,
        address[] memory _tokens
    ) external view returns (uint256[] memory);
}
