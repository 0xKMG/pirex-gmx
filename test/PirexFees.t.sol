// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexFees} from "src/PirexFees.sol";
import {PirexGmx} from "src/PirexGmx.sol";
import {Helper} from "./Helper.sol";

contract PirexFeesTest is Helper {
    address internal immutable DEFAULT_TREASURY = testAccounts[1];
    address internal immutable DEFAULT_CONTRIBUTORS = testAccounts[2];
    uint8 internal constant DEFAULT_TREASURY_PERCENT = 75;

    uint8 internal constant MAX_TREASURY_PERCENT = 75;

    /**
        @notice Get PirexFee variables that are frequently accessed
        @return feeNumerator     uint256  Fee numerator (i.e. fee value)
        @return feeDenominator   uint256  Fee denominator (PirexGmx)
        @return feePercent       uint256  Fee percent denominator (PirexFees)
        @return treasuryPercent  uint256  Treasury fee percent
        @return treasury         address  Treasury address
        @return contributors     address  Contributors address
     */
    function _getPirexFeeVariables(PirexGmx.Fees f)
        internal
        view
        returns (
            uint256 feeNumerator,
            uint256 feeDenominator,
            uint256 feePercent,
            uint256 treasuryPercent,
            address treasury,
            address contributors
        )
    {
        feeNumerator = pirexGmx.fees(f);
        feeDenominator = pirexGmx.FEE_DENOMINATOR();
        feePercent = pirexFees.PERCENT_DENOMINATOR();
        treasuryPercent = pirexFees.treasuryPercent();
        treasury = pirexFees.treasury();
        contributors = pirexFees.contributors();
    }

    /**
        @notice Calculate the expected PirexFee fee values
        @param  assets                            uint256  Underlying GMX or GLP token assets
        @param  feeNumerator                      uint256  Fee numerator
        @param  feeDenominator                    uint256  Fee denominator
        @param  feePercent                        uint256  Fee percent
        @param  treasuryPercent                   uint256  Treasury fee percent
        @return expectedDistribution              uint256  Expected fee distribution
        @return expectedTreasuryDistribution      uint256  Expected fee distribution for treasury
        @return expectedContributorsDistribution  uint256  Expected fee distribution for contributors
     */
    function _calculateExpectedPirexFeeValues(
        uint256 assets,
        uint256 feeNumerator,
        uint256 feeDenominator,
        uint256 feePercent,
        uint256 treasuryPercent
    )
        internal
        pure
        returns (
            uint256 expectedDistribution,
            uint256 expectedTreasuryDistribution,
            uint256 expectedContributorsDistribution
        )
    {
        expectedDistribution = (assets * feeNumerator) / feeDenominator;
        expectedTreasuryDistribution =
            (expectedDistribution * treasuryPercent) /
            feePercent;
        expectedContributorsDistribution =
            expectedDistribution -
            expectedTreasuryDistribution;

        // Distribution should equal the sum of the treasury and contributors distributions
        assert(
            expectedDistribution ==
                expectedTreasuryDistribution + expectedContributorsDistribution
        );
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

        vm.expectRevert(NOT_OWNER_ERROR);

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

        vm.expectRevert(NOT_OWNER_ERROR);

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
        address receiver = address(this);
        (
            uint256 feeNumerator,
            uint256 feeDenominator,
            uint256 feePercent,
            uint256 treasuryPercent,
            address treasury,
            address contributors
        ) = _getPirexFeeVariables(PirexGmx.Fees.Deposit);
        (
            uint256 expectedDistribution,
            uint256 expectedTreasuryDistribution,
            uint256 expectedContributorsDistribution
        ) = _calculateExpectedPirexFeeValues(
                gmxAmount,
                feeNumerator,
                feeDenominator,
                feePercent,
                treasuryPercent
            );

        assertEq(depositFee, feeNumerator);
        assertEq(0, token.balanceOf(treasury));
        assertEq(0, token.balanceOf(contributors));

        _mintGmx(gmxAmount);
        GMX.approve(address(pirexGmx), gmxAmount);
        pirexGmx.depositGmx(gmxAmount, receiver);

        assertEq(expectedDistribution, token.balanceOf(address(pirexFees)));

        vm.expectEmit(true, false, false, true, address(pirexFees));

        emit DistributeFees(
            token,
            expectedDistribution,
            expectedTreasuryDistribution,
            expectedContributorsDistribution
        );

        pirexFees.distributeFees(token);

        assertEq(expectedTreasuryDistribution, pxGmx.balanceOf(treasury));
        assertEq(
            expectedContributorsDistribution,
            pxGmx.balanceOf(contributors)
        );
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
        (
            uint256 feeNumerator,
            uint256 feeDenominator,
            uint256 feePercent,
            uint256 treasuryPercent,
            address treasury,
            address contributors
        ) = _getPirexFeeVariables(PirexGmx.Fees.Deposit);

        assertEq(depositFee, feeNumerator);
        assertEq(0, token.balanceOf(address(this)));
        assertEq(0, token.balanceOf(treasury));
        assertEq(0, token.balanceOf(contributors));

        vm.deal(address(this), ethAmount);

        (uint256 postFeeAmount, uint256 feeAmount) = pirexGmx.depositGlpETH{
            value: ethAmount
        }(1, _calculateMinGlpAmount(address(0), ethAmount, 18), address(this));
        (
            uint256 expectedDistribution,
            uint256 expectedTreasuryDistribution,
            uint256 expectedContributorsDistribution
        ) = _calculateExpectedPirexFeeValues(
                postFeeAmount + feeAmount,
                feeNumerator,
                feeDenominator,
                feePercent,
                treasuryPercent
            );

        assertEq(expectedDistribution, token.balanceOf(address(pirexFees)));

        vm.expectEmit(true, false, false, true, address(pirexFees));

        emit DistributeFees(
            token,
            expectedDistribution,
            expectedTreasuryDistribution,
            expectedContributorsDistribution
        );

        pirexFees.distributeFees(token);

        assertEq(expectedTreasuryDistribution, token.balanceOf(treasury));
        assertEq(
            expectedContributorsDistribution,
            token.balanceOf(contributors)
        );
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

        // Commented out due to "Stack too deep..." error
        // ERC20 token = pxGlp;
        (
            uint256 feeNumerator,
            uint256 feeDenominator,
            uint256 feePercent,
            uint256 treasuryPercent,
            address treasury,
            address contributors
        ) = _getPirexFeeVariables(PirexGmx.Fees.Deposit);

        assertEq(depositFee, feeNumerator);
        assertEq(0, pxGlp.balanceOf(treasury));
        assertEq(0, pxGlp.balanceOf(contributors));

        _mintWbtc(wbtcAmount);
        WBTC.approve(address(pirexGmx), wbtcAmount);

        (uint256 postFeeAmount, uint256 feeAmount) = pirexGmx.depositGlp(
            address(WBTC),
            wbtcAmount,
            1,
            _calculateMinGlpAmount(address(WBTC), wbtcAmount, 8),
            address(this)
        );
        (
            uint256 expectedDistribution,
            uint256 expectedTreasuryDistribution,
            uint256 expectedContributorsDistribution
        ) = _calculateExpectedPirexFeeValues(
                postFeeAmount + feeAmount,
                feeNumerator,
                feeDenominator,
                feePercent,
                treasuryPercent
            );

        assertEq(expectedDistribution, pxGlp.balanceOf(address(pirexFees)));

        vm.expectEmit(true, false, false, true, address(pirexFees));

        emit DistributeFees(
            pxGlp,
            expectedDistribution,
            expectedTreasuryDistribution,
            expectedContributorsDistribution
        );

        pirexFees.distributeFees(pxGlp);

        assertEq(expectedTreasuryDistribution, pxGlp.balanceOf(treasury));
        assertEq(
            expectedContributorsDistribution,
            pxGlp.balanceOf(contributors)
        );
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
        (
            uint256 feeNumerator,
            uint256 feeDenominator,
            uint256 feePercent,
            uint256 treasuryPercent,
            address treasury,
            address contributors
        ) = _getPirexFeeVariables(PirexGmx.Fees.Redemption);

        assertEq(redemptionFee, feeNumerator);
        assertEq(0, token.balanceOf(address(this)));
        assertEq(0, token.balanceOf(treasury));
        assertEq(0, token.balanceOf(contributors));

        vm.deal(address(this), ethAmount);

        pirexGmx.depositGlpETH{value: ethAmount}(
            1,
            _calculateMinGlpAmount(address(0), ethAmount, 18),
            address(this)
        );

        uint256 redemptionAmount = token.balanceOf(address(this)) /
            balanceDivisor;

        // Warp past timelock for GLP redemption
        vm.warp(block.timestamp + 1 hours);

        token.approve(address(pirexGmx), redemptionAmount);

        (
            uint256 expectedDistribution,
            uint256 expectedTreasuryDistribution,
            uint256 expectedContributorsDistribution
        ) = _calculateExpectedPirexFeeValues(
                redemptionAmount,
                feeNumerator,
                feeDenominator,
                feePercent,
                treasuryPercent
            );

        pirexGmx.redeemPxGlpETH(
            redemptionAmount,
            _calculateMinOutAmount(
                address(WETH),
                redemptionAmount - expectedDistribution
            ),
            address(this)
        );

        assertEq(expectedDistribution, token.balanceOf(address(pirexFees)));

        vm.expectEmit(true, false, false, true, address(pirexFees));

        emit DistributeFees(
            token,
            expectedDistribution,
            expectedTreasuryDistribution,
            expectedContributorsDistribution
        );

        pirexFees.distributeFees(token);

        assertEq(expectedTreasuryDistribution, token.balanceOf(treasury));
        assertEq(
            expectedContributorsDistribution,
            token.balanceOf(contributors)
        );
    }

    /**
        @notice Test tx success: distribute fees for redeemPxGlpETH
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
        (
            uint256 feeNumerator,
            uint256 feeDenominator,
            uint256 feePercent,
            uint256 treasuryPercent,
            address treasury,
            address contributors
        ) = _getPirexFeeVariables(PirexGmx.Fees.Redemption);

        assertEq(redemptionFee, feeNumerator);
        assertEq(0, token.balanceOf(address(this)));
        assertEq(0, token.balanceOf(treasury));
        assertEq(0, token.balanceOf(contributors));

        vm.deal(address(this), ethAmount);

        pirexGmx.depositGlpETH{value: ethAmount}(
            1,
            _calculateMinGlpAmount(address(0), ethAmount, 18),
            address(this)
        );

        uint256 redemptionAmount = token.balanceOf(address(this)) /
            balanceDivisor;

        vm.warp(block.timestamp + 1 hours);

        token.approve(address(pirexGmx), redemptionAmount);

        (
            uint256 expectedDistribution,
            uint256 expectedTreasuryDistribution,
            uint256 expectedContributorsDistribution
        ) = _calculateExpectedPirexFeeValues(
                redemptionAmount,
                feeNumerator,
                feeDenominator,
                feePercent,
                treasuryPercent
            );

        pirexGmx.redeemPxGlp(
            address(WETH),
            redemptionAmount,
            _calculateMinOutAmount(
                address(WETH),
                redemptionAmount - expectedDistribution
            ),
            address(this)
        );

        assertEq(expectedDistribution, token.balanceOf(address(pirexFees)));

        vm.expectEmit(true, false, false, true, address(pirexFees));

        emit DistributeFees(
            token,
            expectedDistribution,
            expectedTreasuryDistribution,
            expectedContributorsDistribution
        );

        pirexFees.distributeFees(token);

        assertEq(expectedTreasuryDistribution, token.balanceOf(treasury));
        assertEq(
            expectedContributorsDistribution,
            token.balanceOf(contributors)
        );
    }

    /**
        @notice Test tx success: distribute fees for redeemPxGlpETH
        @param  rewardFee       uint24  Reward fee
        @param  gmxAmount       uint96  Amount of pxGMX to get from the deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testDistributeFeesClaimUserReward(
        uint24 rewardFee,
        uint96 gmxAmount,
        uint32 secondsElapsed
    ) external {
        vm.assume(rewardFee != 0);
        vm.assume(rewardFee < pirexGmx.FEE_MAX());
        vm.assume(gmxAmount != 0);
        vm.assume(gmxAmount < 100000e18);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);

        // Set up rewards state and accrual
        pirexRewards.addRewardToken(pxGmx, pxGmx);
        pirexRewards.addRewardToken(pxGmx, WETH);

        // Mint pxGMX/GLP to accrue rewards and test fee distribution
        _depositGmx(gmxAmount, address(this));

        // Verify entire pxGMX supply is owned by this contract (gets all rewards)
        assertEq(pxGmx.balanceOf(address(this)), pxGmx.totalSupply());

        // Forward timestamp to begin accruing rewards
        vm.warp(block.timestamp + secondsElapsed);

        (
            ,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = pirexRewards.harvest();

        assertEq(address(WETH), address(rewardTokens[0]));
        assertEq(address(pxGmx), address(rewardTokens[2]));

        pirexGmx.setFee(PirexGmx.Fees.Reward, rewardFee);

        (uint256 feeNumerator, , , , , ) = _getPirexFeeVariables(
            PirexGmx.Fees.Reward
        );
        (
            uint256 expectedDistributionWeth,
            uint256 expectedTreasuryDistributionWeth,
            uint256 expectedContributorsDistributionWeth
        ) = _calculateExpectedPirexFeeValues(
                rewardAmounts[0],
                feeNumerator,
                pirexGmx.FEE_DENOMINATOR(),
                pirexFees.PERCENT_DENOMINATOR(),
                pirexFees.treasuryPercent()
            );
        (
            uint256 expectedDistributionPxGmx,
            uint256 expectedTreasuryDistributionPxGmx,
            uint256 expectedContributorsDistributionPxGmx
        ) = _calculateExpectedPirexFeeValues(
                rewardAmounts[2],
                feeNumerator,
                pirexGmx.FEE_DENOMINATOR(),
                pirexFees.PERCENT_DENOMINATOR(),
                pirexFees.treasuryPercent()
            );

        // Pre-claim balance assertions to ensure we're (mostly) starting from a clean slate
        assertEq(rewardFee, feeNumerator);
        assertEq(0, WETH.balanceOf(address(this)));
        assertEq(0, pxGmx.balanceOf(address(this)) - gmxAmount);

        pirexRewards.claim(pxGmx, address(this));

        assertEq(expectedDistributionWeth, WETH.balanceOf(address(pirexFees)));
        assertEq(
            expectedDistributionPxGmx,
            pxGmx.balanceOf(address(pirexFees))
        );

        vm.expectEmit(true, false, false, true, address(pirexFees));

        emit DistributeFees(
            WETH,
            expectedDistributionWeth,
            expectedTreasuryDistributionWeth,
            expectedContributorsDistributionWeth
        );

        pirexFees.distributeFees(WETH);

        assertEq(
            expectedTreasuryDistributionWeth,
            WETH.balanceOf(pirexFees.treasury())
        );
        assertEq(
            expectedContributorsDistributionWeth,
            WETH.balanceOf(pirexFees.contributors())
        );

        vm.expectEmit(true, false, false, true, address(pirexFees));

        emit DistributeFees(
            pxGmx,
            expectedDistributionPxGmx,
            expectedTreasuryDistributionPxGmx,
            expectedContributorsDistributionPxGmx
        );

        pirexFees.distributeFees(pxGmx);

        assertEq(
            expectedTreasuryDistributionPxGmx,
            pxGmx.balanceOf(pirexFees.treasury())
        );
        assertEq(
            expectedContributorsDistributionPxGmx,
            pxGmx.balanceOf(pirexFees.contributors())
        );
    }
}
