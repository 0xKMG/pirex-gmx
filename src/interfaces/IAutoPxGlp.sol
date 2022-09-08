// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IAutoPxGlp {
    function compound(uint256 minGlpAmount, bool optOutIncentive)
        external
        returns (
            uint256 wethAmountIn,
            uint256 pxGmxAmountOut,
            uint256 pxGlpAmountOut,
            uint256 totalPxGlpFee,
            uint256 totalPxGmxFee,
            uint256 pxGlpIncentive,
            uint256 pxGmxIncentive
        );
}
