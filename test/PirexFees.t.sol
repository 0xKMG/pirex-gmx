// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexFees} from "src/PirexFees.sol";
import {PirexGmx} from "src/PirexGmx.sol";
import {Helper} from "./Helper.sol";

contract PirexFeesTest is Helper {
    address internal immutable DEFAULT_TREASURY = treasuryAddress;
    address internal immutable DEFAULT_CONTRIBUTORS = contributorsAddress;
    uint8 internal constant DEFAULT_TREASURY_PERCENT = 75;

    uint8 internal constant MAX_TREASURY_PERCENT = 75;

    /**
        @notice Calculate the expected PirexFee fee values
        @param  assets                            uint256  Underlying GMX or GLP token assets
        @param  feeNumerator                      uint256  Fee numerator
        @return expectedDistribution              uint256  Expected fee distribution
        @return expectedTreasuryDistribution      uint256  Expected fee distribution for treasury
        @return expectedContributorsDistribution  uint256  Expected fee distribution for contributors
     */
    function _calculateExpectedPirexFeeValues(
        uint256 assets,
        uint256 feeNumerator
    )
        internal
        view
        returns (
            uint256 expectedDistribution,
            uint256 expectedTreasuryDistribution,
            uint256 expectedContributorsDistribution
        )
    {
        expectedDistribution = (assets * feeNumerator) / feeDenominator;
        expectedTreasuryDistribution =
            (expectedDistribution * treasuryPercent) /
            percentDenominator;
        expectedContributorsDistribution =
            expectedDistribution -
            expectedTreasuryDistribution;

        // Distribution should equal the sum of the treasury and contributors distributions
        assert(
            expectedDistribution ==
                expectedTreasuryDistribution + expectedContributorsDistribution
        );
    }

    /**
        @notice Calculate the expected claimable user rewards
        @param  producer     ERC20  Producer token
        @param  rewardToken  ERC20  Reward token
        @param  user         address  User address
        @return              uint256  Expected fee claimable amount
     */
    function _calculateClaimableUserReward(
        ERC20 producer,
        ERC20 rewardToken,
        address user
    ) internal view returns (uint256) {
        // Sum of reward amounts that the user/recipient is entitled to
        return
            (pirexRewards.getRewardState(producer, rewardToken) *
                _calculateUserRewards(producer, user)) /
            _calculateGlobalRewards(producer);
    }

    /**
        @notice Claim and aggregate total expected fees data
        @param  feeNumerator                                uint256  Fee numerator
        @return totalExpectedDistributionWeth               uint256  Total expected overall fee for WETH
        @return totalExpectedTreasuryDistributionWeth       uint256  Total expected treasury fee for WETH
        @return totalExpectedContributorsDistributionWeth   uint256  Total expected contributors fee for WETH
        @return totalExpectedDistributionPxGmx              uint256  Total expected overall fee for PxGMX
        @return totalExpectedTreasuryDistributionPxGmx      uint256  Total expected treasury fee for PxGMX
        @return totalExpectedContributorsDistributionPxGmx  uint256  Total expected contributors fee for PxGMX
     */
    function _claimAndAggregateExpectedFees(uint256 feeNumerator)
        internal
        returns (
            uint256 totalExpectedDistributionWeth,
            uint256 totalExpectedTreasuryDistributionWeth,
            uint256 totalExpectedContributorsDistributionWeth,
            uint256 totalExpectedDistributionPxGmx,
            uint256 totalExpectedTreasuryDistributionPxGmx,
            uint256 totalExpectedContributorsDistributionPxGmx
        )
    {
        // Claim and assert on all test accounts, while also calculating total expected fees
        for (uint256 i; i < testAccounts.length; ++i) {
            assertEq(0, WETH.balanceOf(testAccounts[i]));

            (
                uint256 expectedDistributionWeth,
                ,

            ) = _calculateExpectedPirexFeeValues(
                    _calculateClaimableUserReward(pxGmx, WETH, testAccounts[i]),
                    feeNumerator
                );

            (
                uint256 expectedDistributionPxGmx,
                ,

            ) = _calculateExpectedPirexFeeValues(
                    _calculateClaimableUserReward(
                        pxGmx,
                        pxGmx,
                        testAccounts[i]
                    ),
                    feeNumerator
                );

            totalExpectedDistributionWeth += expectedDistributionWeth;
            totalExpectedDistributionPxGmx += expectedDistributionPxGmx;

            pirexRewards.claim(pxGmx, testAccounts[i]);

            assertGt(WETH.balanceOf(testAccounts[i]), 0);
        }

        // Separately calculate the total aggregated expected fees for treasury
        // and contributors to avoid rounding issue
        totalExpectedTreasuryDistributionWeth =
            (totalExpectedDistributionWeth * treasuryPercent) /
            percentDenominator;
        totalExpectedContributorsDistributionWeth =
            totalExpectedDistributionWeth -
            totalExpectedTreasuryDistributionWeth;
        totalExpectedTreasuryDistributionPxGmx =
            (totalExpectedDistributionPxGmx * treasuryPercent) /
            percentDenominator;
        totalExpectedContributorsDistributionPxGmx =
            totalExpectedDistributionPxGmx -
            totalExpectedTreasuryDistributionPxGmx;
    }

    /*//////////////////////////////////////////////////////////////
                        setFeeRecipient TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotSetFeeRecipientNotAuthorized() external {
        assertEq(DEFAULT_TREASURY, pirexFees.treasury());
        assertEq(DEFAULT_CONTRIBUTORS, pirexFees.contributors());

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(testAccounts[0]);

        pirexFees.setFeeRecipient(
            PirexFees.FeeRecipient.Contributors,
            address(this)
        );
    }

    /**
        @notice Test tx reversion: recipient is zero address
     */
    function testCannotSetFeeRecipientZeroAddress() external {
        assertEq(DEFAULT_TREASURY, pirexFees.treasury());
        assertEq(DEFAULT_CONTRIBUTORS, pirexFees.contributors());

        vm.expectRevert(PirexFees.ZeroAddress.selector);

        pirexFees.setFeeRecipient(
            PirexFees.FeeRecipient.Contributors,
            address(0)
        );
    }

    /**
        @notice Test tx success: set fee recipient
        @param  fVal  uint8  Integer representation of the recipient enum
     */
    function testSetFeeRecipient(uint8 fVal) external {
        vm.assume(fVal <= uint8(type(PirexFees.FeeRecipient).max));

        assertEq(DEFAULT_TREASURY, pirexFees.treasury());
        assertEq(DEFAULT_CONTRIBUTORS, pirexFees.contributors());

        PirexFees.FeeRecipient f = PirexFees.FeeRecipient(fVal);
        address recipient = testAccounts[0];

        vm.expectEmit(false, false, false, true);

        emit SetFeeRecipient(f, recipient);

        pirexFees.setFeeRecipient(f, recipient);

        assertEq(
            (
                f == PirexFees.FeeRecipient.Treasury
                    ? pirexFees.treasury()
                    : pirexFees.contributors()
            ),
            recipient
        );
    }

    /*//////////////////////////////////////////////////////////////
                        setTreasuryPercent TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotSetTreasuryPercentNotAuthorized() external {
        assertEq(DEFAULT_TREASURY_PERCENT, pirexFees.treasuryPercent());

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(testAccounts[0]);

        pirexFees.setTreasuryPercent(MAX_TREASURY_PERCENT);
    }

    /**
        @notice Test tx reversion: treasury percent is invalid
     */
    function testCannotSetTreasuryPercentInvalidFeePercent() external {
        assertEq(DEFAULT_TREASURY_PERCENT, pirexFees.treasuryPercent());

        // The percentage is invalid if > maxTreasuryPercent
        vm.expectRevert(PirexFees.InvalidFeePercent.selector);

        pirexFees.setTreasuryPercent(MAX_TREASURY_PERCENT + 1);
    }

    /**
        @notice Test tx success: set treasury percent
        @param  percent  uint8  Treasury percent
     */
    function testSetTreasuryPercent(uint8 percent) external {
        vm.assume(percent <= MAX_TREASURY_PERCENT);

        assertEq(DEFAULT_TREASURY_PERCENT, pirexFees.treasuryPercent());

        vm.expectEmit(false, false, false, true);

        emit SetTreasuryPercent(percent);

        pirexFees.setTreasuryPercent(percent);

        assertEq(pirexFees.treasuryPercent(), percent);
    }

    /*//////////////////////////////////////////////////////////////
                        distributeFees TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test success tx: distribute fees for depositGmx
        @param  depositFee  uint24  Deposit fee
        @param  gmxAmount   uint96  GMX amount
     */
    function testDistributeFeesDepositGmx(uint24 depositFee, uint96 gmxAmount)
        external
    {
        vm.assume(depositFee != 0);
        vm.assume(depositFee < pirexGmx.FEE_MAX());
        vm.assume(gmxAmount != 0);
        vm.assume(gmxAmount < 100000e18);

        pirexGmx.setFee(PirexGmx.Fees.Deposit, depositFee);

        ERC20 token = pxGmx;

        assertEq(0, token.balanceOf(treasury));
        assertEq(0, token.balanceOf(contributors));

        uint256 totalExpectedTreasuryDistribution;
        uint256 totalExpectedContributorsDistribution;

        // Perform pxGMX deposit for all test accounts and assert fees
        for (uint256 i; i < testAccounts.length; ++i) {
            _depositGmx(gmxAmount, testAccounts[i]);

            (
                uint256 expectedDistribution,
                uint256 expectedTreasuryDistribution,
                uint256 expectedContributorsDistribution
            ) = _calculateExpectedPirexFeeValues(gmxAmount, depositFee);

            totalExpectedTreasuryDistribution += expectedTreasuryDistribution;
            totalExpectedContributorsDistribution += expectedContributorsDistribution;

            assertEq(expectedDistribution, token.balanceOf(address(pirexFees)));

            vm.expectEmit(true, false, false, true, address(pirexFees));

            emit DistributeFees(
                token,
                expectedDistribution,
                expectedTreasuryDistribution,
                expectedContributorsDistribution
            );

            pirexFees.distributeFees(token);

            assertEq(
                totalExpectedTreasuryDistribution,
                token.balanceOf(treasury)
            );
            assertEq(
                totalExpectedContributorsDistribution,
                token.balanceOf(contributors)
            );
        }
    }

    /**
        @notice Test tx success: distribute fees for depositGlpETH
        @param  depositFee  uint24  Deposit fee
        @param  ethAmount   uint96  ETH amount
     */
    function testDistributeFeesDepositGlpETH(
        uint24 depositFee,
        uint96 ethAmount
    ) external {
        vm.assume(depositFee != 0);
        vm.assume(depositFee < pirexGmx.FEE_MAX());
        vm.assume(ethAmount > 0.001 ether);
        vm.assume(ethAmount < 10000 ether);

        pirexGmx.setFee(PirexGmx.Fees.Deposit, depositFee);

        ERC20 token = pxGlp;

        assertEq(0, token.balanceOf(treasury));
        assertEq(0, token.balanceOf(contributors));

        uint256 totalExpectedTreasuryDistribution;
        uint256 totalExpectedContributorsDistribution;

        // Perform pxGLP deposit using ETH for all test accounts and assert fees
        for (uint256 i; i < testAccounts.length; ++i) {
            (uint256 postFeeAmount, uint256 feeAmount) = _depositGlpETH(
                ethAmount,
                testAccounts[i]
            );

            (
                uint256 expectedDistribution,
                uint256 expectedTreasuryDistribution,
                uint256 expectedContributorsDistribution
            ) = _calculateExpectedPirexFeeValues(
                    postFeeAmount + feeAmount,
                    depositFee
                );

            totalExpectedTreasuryDistribution += expectedTreasuryDistribution;
            totalExpectedContributorsDistribution += expectedContributorsDistribution;

            assertEq(expectedDistribution, token.balanceOf(address(pirexFees)));

            vm.expectEmit(true, false, false, true, address(pirexFees));

            emit DistributeFees(
                token,
                expectedDistribution,
                expectedTreasuryDistribution,
                expectedContributorsDistribution
            );

            pirexFees.distributeFees(token);

            assertEq(
                totalExpectedTreasuryDistribution,
                token.balanceOf(treasury)
            );
            assertEq(
                totalExpectedContributorsDistribution,
                token.balanceOf(contributors)
            );
        }
    }

    /**
        @notice Test tx success: distribute fees for depositGlp
        @param  depositFee  uint24  Deposit fee
        @param  wbtcAmount  uint40  WBTC amount
     */
    function testDistributeFeesDepositGlp(uint24 depositFee, uint40 wbtcAmount)
        external
    {
        vm.assume(depositFee != 0);
        vm.assume(depositFee < pirexGmx.FEE_MAX());
        vm.assume(wbtcAmount > 1e5);
        vm.assume(wbtcAmount < 100e8);

        pirexGmx.setFee(PirexGmx.Fees.Deposit, depositFee);

        assertEq(0, pxGlp.balanceOf(treasury));
        assertEq(0, pxGlp.balanceOf(contributors));

        uint256 totalExpectedTreasuryDistribution;
        uint256 totalExpectedContributorsDistribution;

        // Perform pxGLP deposit using WBTC (ERC20) for all test accounts and assert fees
        for (uint256 i; i < testAccounts.length; ++i) {
            (uint256 deposited, , ) = _depositGlp(wbtcAmount, testAccounts[i]);

            (
                uint256 expectedDistribution,
                uint256 expectedTreasuryDistribution,
                uint256 expectedContributorsDistribution
            ) = _calculateExpectedPirexFeeValues(deposited, depositFee);

            totalExpectedTreasuryDistribution += expectedTreasuryDistribution;
            totalExpectedContributorsDistribution += expectedContributorsDistribution;

            assertEq(expectedDistribution, pxGlp.balanceOf(address(pirexFees)));

            vm.expectEmit(true, false, false, true, address(pirexFees));

            emit DistributeFees(
                pxGlp,
                expectedDistribution,
                expectedTreasuryDistribution,
                expectedContributorsDistribution
            );

            pirexFees.distributeFees(pxGlp);

            assertEq(
                totalExpectedTreasuryDistribution,
                pxGlp.balanceOf(treasury)
            );
            assertEq(
                totalExpectedContributorsDistribution,
                pxGlp.balanceOf(contributors)
            );
        }
    }

    /**
        @notice Test tx success: distribute fees for redeemPxGlpETH
        @param  redemptionFee   uint24  Redemption fee
        @param  ethAmount       uint96  ETH amount
        @param  balanceDivisor  uint8   Divides balance to vary redemption amount
     */
    function testDistributeFeesRedeemPxGlpETH(
        uint24 redemptionFee,
        uint96 ethAmount,
        uint8 balanceDivisor
    ) external {
        vm.assume(redemptionFee != 0);
        vm.assume(redemptionFee < pirexGmx.FEE_MAX());
        vm.assume(ethAmount > 0.001 ether);
        vm.assume(ethAmount < 10000 ether);
        vm.assume(balanceDivisor != 0);

        pirexGmx.setFee(PirexGmx.Fees.Redemption, redemptionFee);

        ERC20 token = pxGlp;

        assertEq(0, token.balanceOf(treasury));
        assertEq(0, token.balanceOf(contributors));

        uint256 totalExpectedTreasuryDistribution;
        uint256 totalExpectedContributorsDistribution;

        // Perform pxGLP deposit then redeem back to ETH for all test accounts and assert fees
        for (uint256 i; i < testAccounts.length; ++i) {
            _depositGlpETH(ethAmount, testAccounts[i]);

            uint256 redemptionAmount = token.balanceOf(testAccounts[i]) /
                balanceDivisor;

            (
                uint256 expectedDistribution,
                uint256 expectedTreasuryDistribution,
                uint256 expectedContributorsDistribution
            ) = _calculateExpectedPirexFeeValues(
                    redemptionAmount,
                    redemptionFee
                );

            totalExpectedTreasuryDistribution += expectedTreasuryDistribution;
            totalExpectedContributorsDistribution += expectedContributorsDistribution;

            vm.startPrank(testAccounts[i]);

            token.approve(address(pirexGmx), redemptionAmount);

            pirexGmx.redeemPxGlpETH(
                redemptionAmount,
                _calculateMinOutAmount(
                    address(WETH),
                    redemptionAmount - expectedDistribution
                ),
                testAccounts[i]
            );

            vm.stopPrank();

            assertEq(expectedDistribution, token.balanceOf(address(pirexFees)));

            vm.expectEmit(true, false, false, true, address(pirexFees));

            emit DistributeFees(
                token,
                expectedDistribution,
                expectedTreasuryDistribution,
                expectedContributorsDistribution
            );

            pirexFees.distributeFees(token);

            assertEq(
                totalExpectedTreasuryDistribution,
                token.balanceOf(treasury)
            );
            assertEq(
                totalExpectedContributorsDistribution,
                token.balanceOf(contributors)
            );
        }
    }

    /**
        @notice Test tx success: distribute fees for redeemPxGlp
        @param  redemptionFee   uint24  Redemption fee
        @param  ethAmount       uint96  ETH amount
        @param  balanceDivisor  uint8   Divides balance to vary redemption amount
     */
    function testDistributeFeesRedeemPxGlp(
        uint24 redemptionFee,
        uint96 ethAmount,
        uint8 balanceDivisor
    ) external {
        vm.assume(redemptionFee != 0);
        vm.assume(redemptionFee < pirexGmx.FEE_MAX());
        vm.assume(ethAmount > 0.001 ether);
        vm.assume(ethAmount < 10000 ether);
        vm.assume(balanceDivisor != 0);

        pirexGmx.setFee(PirexGmx.Fees.Redemption, redemptionFee);

        ERC20 token = pxGlp;

        assertEq(0, token.balanceOf(treasury));
        assertEq(0, token.balanceOf(contributors));

        uint256 totalExpectedTreasuryDistribution;
        uint256 totalExpectedContributorsDistribution;

        // Perform pxGLP deposit then redeem back to WETH (ERC20) for all test accounts and assert fees
        for (uint256 i; i < testAccounts.length; ++i) {
            _depositGlpETH(ethAmount, testAccounts[i]);

            uint256 redemptionAmount = token.balanceOf(testAccounts[i]) /
                balanceDivisor;

            (
                uint256 expectedDistribution,
                uint256 expectedTreasuryDistribution,
                uint256 expectedContributorsDistribution
            ) = _calculateExpectedPirexFeeValues(
                    redemptionAmount,
                    redemptionFee
                );

            totalExpectedTreasuryDistribution += expectedTreasuryDistribution;
            totalExpectedContributorsDistribution += expectedContributorsDistribution;

            vm.startPrank(testAccounts[i]);

            token.approve(address(pirexGmx), redemptionAmount);

            pirexGmx.redeemPxGlp(
                address(WETH),
                redemptionAmount,
                _calculateMinOutAmount(
                    address(WETH),
                    redemptionAmount - expectedDistribution
                ),
                testAccounts[i]
            );

            vm.stopPrank();

            assertEq(expectedDistribution, token.balanceOf(address(pirexFees)));

            vm.expectEmit(true, false, false, true, address(pirexFees));

            emit DistributeFees(
                token,
                expectedDistribution,
                expectedTreasuryDistribution,
                expectedContributorsDistribution
            );

            pirexFees.distributeFees(token);

            assertEq(
                totalExpectedTreasuryDistribution,
                token.balanceOf(treasury)
            );
            assertEq(
                totalExpectedContributorsDistribution,
                token.balanceOf(contributors)
            );
        }
    }

    /**
        @notice Test tx success: distribute fees for redeemPxGlpETH
        @param  rewardFee       uint24  Reward fee
        @param  secondsElapsed  uint32  Seconds to forward timestamp
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
     */
    function testDistributeFeesClaimUserReward(
        uint24 rewardFee,
        uint32 secondsElapsed,
        uint8 multiplier
    ) external {
        vm.assume(rewardFee != 0);
        vm.assume(rewardFee < pirexGmx.FEE_MAX());
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        // Set up rewards state and accrual
        pirexRewards.addRewardToken(pxGmx, pxGmx);
        pirexRewards.addRewardToken(pxGmx, WETH);

        // Mint pxGMX to accrue rewards and test fee distribution for all test accounts
        _depositForTestAccountsPxGmx(multiplier);

        // Forward timestamp to begin accruing rewards
        vm.warp(block.timestamp + secondsElapsed);

        // Expected values for rewards will be counted at a separate logic
        // to prevent rounding error issue
        (, ERC20[] memory rewardTokens, ) = pirexRewards.harvest();

        assertEq(address(WETH), address(rewardTokens[0]));
        assertEq(address(pxGmx), address(rewardTokens[2]));

        pirexGmx.setFee(PirexGmx.Fees.Reward, rewardFee);

        assertEq(0, WETH.balanceOf(address(pirexFees)));
        assertEq(0, WETH.balanceOf(treasury));
        assertEq(0, WETH.balanceOf(contributors));

        (
            uint256 totalExpectedDistributionWeth,
            uint256 totalExpectedTreasuryDistributionWeth,
            uint256 totalExpectedContributorsDistributionWeth,
            uint256 totalExpectedDistributionPxGmx,
            uint256 totalExpectedTreasuryDistributionPxGmx,
            uint256 totalExpectedContributorsDistributionPxGmx
        ) = _claimAndAggregateExpectedFees(rewardFee);

        assertEq(
            totalExpectedDistributionWeth,
            WETH.balanceOf(address(pirexFees))
        );
        assertEq(
            totalExpectedDistributionPxGmx,
            pxGmx.balanceOf(address(pirexFees))
        );

        vm.expectEmit(true, false, false, true, address(pirexFees));

        emit DistributeFees(
            WETH,
            totalExpectedDistributionWeth,
            totalExpectedTreasuryDistributionWeth,
            totalExpectedContributorsDistributionWeth
        );

        pirexFees.distributeFees(WETH);

        assertEq(
            totalExpectedTreasuryDistributionWeth,
            WETH.balanceOf(pirexFees.treasury())
        );
        assertEq(
            totalExpectedContributorsDistributionWeth,
            WETH.balanceOf(pirexFees.contributors())
        );

        vm.expectEmit(true, false, false, true, address(pirexFees));

        emit DistributeFees(
            pxGmx,
            totalExpectedDistributionPxGmx,
            totalExpectedTreasuryDistributionPxGmx,
            totalExpectedContributorsDistributionPxGmx
        );

        pirexFees.distributeFees(pxGmx);

        assertEq(
            totalExpectedTreasuryDistributionPxGmx,
            pxGmx.balanceOf(pirexFees.treasury())
        );
        assertEq(
            totalExpectedContributorsDistributionPxGmx,
            pxGmx.balanceOf(pirexFees.contributors())
        );
    }
}
