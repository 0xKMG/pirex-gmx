// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexFees} from "src/PirexFees.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {Helper} from "./Helper.t.sol";

contract PirexFeesTest is Helper {
    address internal immutable DEFAULT_TREASURY = testAccounts[0];
    address internal immutable DEFAULT_CONTRIBUTORS = testAccounts[1];
    uint8 internal constant DEFAULT_TREASURY_PERCENT = 75;

    uint8 internal constant MAX_TREASURY_PERCENT = 75;

    /**
        @notice Get PirexFee variables that are frequently accessed
        @return feeNumerator     uint256  Fee numerator (i.e. fee value)
        @return feeDenominator   uint256  Fee denominator (PirexGmxGlp)
        @return feePercent       uint256  Fee percent denominator (PirexFees)
        @return treasuryPercent  uint256  Treasury fee percent
        @return treasury         address  Treasury address
        @return contributors     address  Contributors address
     */
    function _getPirexFeeVariables(PirexGmxGlp.Fees f)
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
        feeNumerator = pirexGmxGlp.fees(f);
        feeDenominator = pirexGmxGlp.FEE_DENOMINATOR();
        feePercent = pirexFees.PERCENT_DENOMINATOR();
        treasuryPercent = pirexFees.treasuryPercent();
        treasury = pirexFees.treasury();
        contributors = pirexFees.contributors();
    }

    /**
        @notice Calculate the expected PirexFee fee values
        @param  assets                         uint256  Underlying GMX or GLP token assets
        @param  feeNumerator                   uint256  Fee numerator
        @param  feeDenominator                 uint256  Fee denominator
        @param  feePercent                     uint256  Fee percent
        @param  treasuryPercent                uint256  Treasury fee percent
        @return expectedFeeAmount              uint256  Expected fee amount
        @return expectedFeeAmountTreasury      uint256  Expected fee amount for treasury
        @return expectedFeeAmountContributors  uint256  Expected fee amount for contributors
        @return expectedUserAmount             uint256  Expected user amount (mint/burn/etc.)
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
            uint256 expectedFeeAmount,
            uint256 expectedFeeAmountTreasury,
            uint256 expectedFeeAmountContributors,
            uint256 expectedUserAmount
        )
    {
        expectedFeeAmount = (assets * feeNumerator) / feeDenominator;
        expectedFeeAmountTreasury =
            (expectedFeeAmount * treasuryPercent) /
            feePercent;
        expectedFeeAmountContributors =
            expectedFeeAmount -
            expectedFeeAmountTreasury;
        expectedUserAmount = assets - expectedFeeAmount;
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
        address recipient = testAccounts[2];

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
        vm.assume(depositFee < pirexGmxGlp.FEE_MAX());
        vm.assume(gmxAmount != 0);
        vm.assume(gmxAmount < 100000e18);

        pirexGmxGlp.setFee(PirexGmxGlp.Fees.Deposit, depositFee);

        address receiver = address(this);
        (
            uint256 feeNumerator,
            uint256 feeDenominator,
            uint256 feePercent,
            uint256 treasuryPercent,
            address treasury,
            address contributors
        ) = _getPirexFeeVariables(PirexGmxGlp.Fees.Deposit);

        (
            uint256 expectedFeeAmount,
            uint256 expectedFeeAmountTreasury,
            uint256 expectedFeeAmountContributors,
            uint256 expectedMintAmount
        ) = _calculateExpectedPirexFeeValues(
                gmxAmount,
                feeNumerator,
                feeDenominator,
                feePercent,
                treasuryPercent
            );

        assertEq(depositFee, feeNumerator);
        assertEq(0, pxGmx.balanceOf(receiver));
        assertEq(0, pxGmx.balanceOf(treasury));
        assertEq(0, pxGmx.balanceOf(contributors));

        _mintGmx(gmxAmount);
        GMX.approve(address(pirexGmxGlp), gmxAmount);

        vm.expectEmit(true, true, false, true, address(pirexGmxGlp));

        emit DepositGmx(
            address(this),
            receiver,
            gmxAmount,
            expectedMintAmount,
            expectedFeeAmount
        );

        pirexGmxGlp.depositGmx(gmxAmount, receiver);

        assertGt(expectedMintAmount, 0);
        assertEq(
            expectedFeeAmountTreasury + expectedFeeAmountContributors,
            expectedFeeAmount
        );
        assertEq(expectedMintAmount, pxGmx.balanceOf(receiver));
        assertEq(expectedFeeAmountTreasury, pxGmx.balanceOf(treasury));
        assertEq(expectedFeeAmountContributors, pxGmx.balanceOf(contributors));
        assertEq(expectedMintAmount + expectedFeeAmount, gmxAmount);
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
        vm.assume(depositFee < pirexGmxGlp.FEE_MAX());
        vm.assume(ethAmount > 0.001 ether);
        vm.assume(ethAmount < 10000 ether);

        pirexGmxGlp.setFee(PirexGmxGlp.Fees.Deposit, depositFee);

        uint256 minUsdg = 1;
        uint256 minGlp = _calculateMinGlpAmount(address(0), ethAmount, 18);
        address receiver = address(this);
        (
            uint256 feeNumerator,
            uint256 feeDenominator,
            uint256 feePercent,
            uint256 treasuryPercent,
            address treasury,
            address contributors
        ) = _getPirexFeeVariables(PirexGmxGlp.Fees.Deposit);

        assertEq(depositFee, feeNumerator);
        assertEq(0, pxGlp.balanceOf(receiver));
        assertEq(0, pxGlp.balanceOf(treasury));
        assertEq(0, pxGlp.balanceOf(contributors));

        vm.deal(address(this), ethAmount);

        uint256 assets = pirexGmxGlp.depositGlpETH{value: ethAmount}(
            minUsdg,
            minGlp,
            receiver
        );
        (
            uint256 expectedFeeAmount,
            uint256 expectedFeeAmountTreasury,
            uint256 expectedFeeAmountContributors,
            uint256 expectedMintAmount
        ) = _calculateExpectedPirexFeeValues(
                assets,
                feeNumerator,
                feeDenominator,
                feePercent,
                treasuryPercent
            );

        assertGt(expectedMintAmount, 0);
        assertEq(
            expectedFeeAmountTreasury + expectedFeeAmountContributors,
            expectedFeeAmount
        );
        assertEq(expectedMintAmount, pxGlp.balanceOf(receiver));
        assertEq(expectedFeeAmountTreasury, pxGlp.balanceOf(treasury));
        assertEq(expectedFeeAmountContributors, pxGlp.balanceOf(contributors));
        assertEq(expectedMintAmount + expectedFeeAmount, assets);
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
        vm.assume(depositFee < pirexGmxGlp.FEE_MAX());
        vm.assume(wbtcAmount > 1e5);
        vm.assume(wbtcAmount < 100e8);

        pirexGmxGlp.setFee(PirexGmxGlp.Fees.Deposit, depositFee);

        uint256 minUsdg = 1;
        uint256 minGlp = _calculateMinGlpAmount(address(WBTC), wbtcAmount, 8);
        address receiver = address(this);
        (
            uint256 feeNumerator,
            uint256 feeDenominator,
            uint256 feePercent,
            uint256 treasuryPercent,
            address treasury,
            address contributors
        ) = _getPirexFeeVariables(PirexGmxGlp.Fees.Deposit);

        assertEq(depositFee, feeNumerator);
        assertEq(0, pxGlp.balanceOf(receiver));
        assertEq(0, pxGlp.balanceOf(treasury));
        assertEq(0, pxGlp.balanceOf(contributors));

        _mintWbtc(wbtcAmount);
        WBTC.approve(address(pirexGmxGlp), wbtcAmount);

        uint256 assets = pirexGmxGlp.depositGlp(
            address(WBTC),
            wbtcAmount,
            minUsdg,
            minGlp,
            receiver
        );
        (
            uint256 expectedFeeAmount,
            uint256 expectedFeeAmountTreasury,
            uint256 expectedFeeAmountContributors,
            uint256 expectedMintAmount
        ) = _calculateExpectedPirexFeeValues(
                assets,
                feeNumerator,
                feeDenominator,
                feePercent,
                treasuryPercent
            );

        assertGt(expectedMintAmount, 0);
        assertEq(
            expectedFeeAmountTreasury + expectedFeeAmountContributors,
            expectedFeeAmount
        );
        assertEq(expectedMintAmount, pxGlp.balanceOf(receiver));
        assertEq(expectedFeeAmountTreasury, pxGlp.balanceOf(treasury));
        assertEq(expectedFeeAmountContributors, pxGlp.balanceOf(contributors));
        assertEq(expectedMintAmount + expectedFeeAmount, assets);
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
        vm.assume(redemptionFee < pirexGmxGlp.FEE_MAX());
        vm.assume(ethAmount > 0.001 ether);
        vm.assume(ethAmount < 10000 ether);
        vm.assume(balanceDivisor != 0);

        pirexGmxGlp.setFee(PirexGmxGlp.Fees.Redemption, redemptionFee);

        (
            uint256 feeNumerator,
            uint256 feeDenominator,
            uint256 feePercent,
            uint256 treasuryPercent,
            address treasury,
            address contributors
        ) = _getPirexFeeVariables(PirexGmxGlp.Fees.Redemption);

        assertEq(redemptionFee, feeNumerator);
        assertEq(0, pxGlp.balanceOf(address(this)));
        assertEq(0, pxGlp.balanceOf(treasury));
        assertEq(0, pxGlp.balanceOf(contributors));

        vm.deal(address(this), ethAmount);

        pirexGmxGlp.depositGlpETH{value: ethAmount}(
            1,
            _calculateMinGlpAmount(address(0), ethAmount, 18),
            address(this)
        );

        uint256 redemptionAmount = pxGlp.balanceOf(address(this)) /
            balanceDivisor;

        assertGt(redemptionAmount, 0);

        // Warp past timelock for GLP redemption
        vm.warp(block.timestamp + 1 hours);

        pxGlp.approve(address(pirexGmxGlp), redemptionAmount);

        uint256 supplyBeforeRedemption = pxGlp.totalSupply();
        uint256 fsGlpBalanceBeforeRedemption = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        );
        (
            uint256 expectedFeeAmount,
            uint256 expectedFeeAmountTreasury,
            uint256 expectedFeeAmountContributors,
            uint256 expectedBurnAmount
        ) = _calculateExpectedPirexFeeValues(
                redemptionAmount,
                feeNumerator,
                feeDenominator,
                feePercent,
                treasuryPercent
            );

        pirexGmxGlp.redeemPxGlpETH(
            redemptionAmount,
            _calculateMinOutAmount(
                address(WETH),
                redemptionAmount - expectedFeeAmount
            ),
            address(this)
        );

        assertEq(
            (fsGlpBalanceBeforeRedemption - redemptionAmount) +
                expectedFeeAmount,
            FEE_STAKED_GLP.balanceOf(address(pirexGmxGlp))
        );
        assertGt(expectedBurnAmount, 0);
        assertEq(
            expectedFeeAmountTreasury + expectedFeeAmountContributors,
            expectedFeeAmount
        );
        assertEq(expectedFeeAmountTreasury, pxGlp.balanceOf(treasury));
        assertEq(expectedFeeAmountContributors, pxGlp.balanceOf(contributors));
        assertEq(
            expectedBurnAmount,
            supplyBeforeRedemption - pxGlp.totalSupply()
        );
        assertEq(expectedBurnAmount + expectedFeeAmount, redemptionAmount);
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
        vm.assume(redemptionFee < pirexGmxGlp.FEE_MAX());
        vm.assume(ethAmount > 0.001 ether);
        vm.assume(ethAmount < 10000 ether);
        vm.assume(balanceDivisor != 0);

        pirexGmxGlp.setFee(PirexGmxGlp.Fees.Redemption, redemptionFee);

        (
            uint256 feeNumerator,
            uint256 feeDenominator,
            uint256 feePercent,
            uint256 treasuryPercent,
            address treasury,
            address contributors
        ) = _getPirexFeeVariables(PirexGmxGlp.Fees.Redemption);

        assertEq(redemptionFee, feeNumerator);
        assertEq(0, pxGlp.balanceOf(address(this)));
        assertEq(0, pxGlp.balanceOf(treasury));
        assertEq(0, pxGlp.balanceOf(contributors));

        vm.deal(address(this), ethAmount);

        pirexGmxGlp.depositGlpETH{value: ethAmount}(
            1,
            _calculateMinGlpAmount(address(0), ethAmount, 18),
            address(this)
        );

        uint256 redemptionAmount = pxGlp.balanceOf(address(this)) /
            balanceDivisor;

        assertGt(redemptionAmount, 0);

        vm.warp(block.timestamp + 1 hours);

        pxGlp.approve(address(pirexGmxGlp), redemptionAmount);

        uint256 supplyBeforeRedemption = pxGlp.totalSupply();
        uint256 fsGlpBalanceBeforeRedemption = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        );
        (
            uint256 expectedFeeAmount,
            uint256 expectedFeeAmountTreasury,
            uint256 expectedFeeAmountContributors,
            uint256 expectedBurnAmount
        ) = _calculateExpectedPirexFeeValues(
                redemptionAmount,
                feeNumerator,
                feeDenominator,
                feePercent,
                treasuryPercent
            );

        pirexGmxGlp.redeemPxGlp(
            address(WETH),
            redemptionAmount,
            _calculateMinOutAmount(
                address(WETH),
                redemptionAmount - expectedFeeAmount
            ),
            address(this)
        );

        assertEq(
            (fsGlpBalanceBeforeRedemption - redemptionAmount) +
                expectedFeeAmount,
            FEE_STAKED_GLP.balanceOf(address(pirexGmxGlp))
        );
        assertGt(expectedBurnAmount, 0);
        assertEq(expectedFeeAmountTreasury, pxGlp.balanceOf(treasury));
        assertEq(expectedFeeAmountContributors, pxGlp.balanceOf(contributors));
        assertEq(
            expectedBurnAmount,
            (supplyBeforeRedemption - pxGlp.totalSupply())
        );
        assertEq(expectedBurnAmount + expectedFeeAmount, redemptionAmount);
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
        vm.assume(rewardFee < pirexGmxGlp.FEE_MAX());
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

        pirexGmxGlp.setFee(PirexGmxGlp.Fees.Reward, rewardFee);

        (uint256 feeNumerator, , , , , ) = _getPirexFeeVariables(
            PirexGmxGlp.Fees.Reward
        );

        (
            uint256 expectedFeeAmountWeth,
            uint256 expectedFeeAmountTreasuryWeth,
            uint256 expectedFeeAmountContributorsWeth,
            uint256 expectedClaimAmountWeth
        ) = _calculateExpectedPirexFeeValues(
                rewardAmounts[0],
                feeNumerator,
                pirexGmxGlp.FEE_DENOMINATOR(),
                pirexFees.PERCENT_DENOMINATOR(),
                pirexFees.treasuryPercent()
            );
        (
            uint256 expectedFeeAmountPxGmx,
            uint256 expectedFeeAmountTreasuryPxGmx,
            uint256 expectedFeeAmountContributorsPxGmx,
            uint256 expectedClaimAmountPxGmx
        ) = _calculateExpectedPirexFeeValues(
                rewardAmounts[2],
                feeNumerator,
                pirexGmxGlp.FEE_DENOMINATOR(),
                pirexFees.PERCENT_DENOMINATOR(),
                pirexFees.treasuryPercent()
            );

        // Pre-claim balance assertions to ensure we're (mostly) starting from a clean slate
        assertEq(rewardFee, feeNumerator);
        assertEq(0, WETH.balanceOf(address(this)));
        assertEq(0, pxGmx.balanceOf(address(this)) - gmxAmount);

        pirexRewards.claim(pxGmx, address(this));

        assertEq(
            expectedFeeAmountTreasuryWeth + expectedFeeAmountContributorsWeth,
            expectedFeeAmountWeth
        );
        assertEq(
            expectedFeeAmountTreasuryWeth,
            WETH.balanceOf(pirexFees.treasury())
        );
        assertEq(
            expectedFeeAmountContributorsWeth,
            WETH.balanceOf(pirexFees.contributors())
        );
        assertEq(expectedClaimAmountWeth, WETH.balanceOf(address(this)));
        assertEq(
            expectedFeeAmountTreasuryPxGmx + expectedFeeAmountContributorsPxGmx,
            expectedFeeAmountPxGmx
        );
        assertEq(
            expectedFeeAmountTreasuryPxGmx,
            pxGmx.balanceOf(pirexFees.treasury())
        );
        assertEq(
            expectedFeeAmountContributorsPxGmx,
            pxGmx.balanceOf(pirexFees.contributors())
        );
        assertEq(
            expectedClaimAmountPxGmx,
            pxGmx.balanceOf(address(this)) - gmxAmount
        );
    }
}
