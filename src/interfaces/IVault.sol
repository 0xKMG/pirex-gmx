// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// https://arbiscan.io/address/0x489ee077994B6658eAfA855C308275EAd8097C4A#code
interface IVault {
    function whitelistedTokens(address _token) external view returns (bool);

    function totalTokenWeights() external view returns (uint256);

    function getRedemptionAmount(address _token, uint256 _usdgAmount)
        external
        view
        returns (uint256);
}
