// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// https://arbiscan.io/address/0xa906f338cb21815cbc4bc87ace9e68c87ef8d8f1#code
interface IRewardRouterV2 {
    function stakeGmx(uint256 _amount) external;

    function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp)
        external
        payable
        returns (uint256);

    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256);

    function unstakeAndRedeemGlpETH(
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;

    function signalTransfer(address _receiver) external;

    function acceptTransfer(address _sender) external;

    function pendingReceivers(address _sender) external returns (address);
}