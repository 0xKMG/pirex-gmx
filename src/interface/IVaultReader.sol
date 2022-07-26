// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// https://arbiscan.io/address/0xfebB9f4CAC4cD523598fE1C5771181440143F24A#code
interface IVaultReader {
    function getVaultTokenInfoV4(
        address _vault,
        address _positionManager,
        address _weth,
        uint256 _usdgAmount,
        address[] memory _tokens
    ) external view returns (uint256[] memory);
}
