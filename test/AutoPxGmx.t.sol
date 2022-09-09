// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {AutoPxGmx} from "src/vaults/AutoPxGmx.sol";
import {Helper} from "./Helper.t.sol";

contract AutoPxGmxTest is Helper {
    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event CompoundIncentiveUpdated(uint256 percent);
    event PlatformUpdated(address _platform);
    event RewardsModuleUpdated(address _rewardsModule);
    event Compounded(
        address indexed caller,
        uint24 fee,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        uint256 wethAmountIn,
        uint256 gmxAmountOut,
        uint256 pxGmxMintAmount,
        uint256 totalFee,
        uint256 incentive
    );

    /**
        @notice Provision reward state to test compounding of rewards
        @param  gmxAmount         uint256  Amount of pxGMX to get from the deposit
        @param  receiver          address  Receiver of the GMX and pxGMX tokens (i.e. user)
        @param  secondsElapsed    uint256  Seconds to forward timestamp
        @return wethRewardState   uint256  WETH reward state
        @return pxGmxRewardState  uint256  pxGMX reward state
     */
    function _provisionRewardState(
        uint256 gmxAmount,
        address receiver,
        uint256 secondsElapsed
    ) internal returns (uint256 wethRewardState, uint256 pxGmxRewardState) {
        _depositGmx(gmxAmount, receiver);
        pxGmx.approve(address(autoPxGmx), pxGmx.balanceOf(receiver));
        autoPxGmx.deposit(pxGmx.balanceOf(receiver), receiver);
        pirexRewards.addRewardToken(pxGmx, WETH);
        pirexRewards.addRewardToken(pxGmx, pxGmx);

        vm.warp(block.timestamp + secondsElapsed);

        pirexRewards.harvest();

        wethRewardState = pirexRewards.getRewardState(pxGmx, WETH);
        pxGmxRewardState = pirexRewards.getRewardState(pxGmx, pxGmx);
    }

    /*//////////////////////////////////////////////////////////////
                        setWithdrawalPenalty TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetWithdrawalPenaltyUnauthorized() external {
        // Define function arguments
        uint256 penalty = 1;

        // Define post-transition/upcoming state or effects
        vm.expectRevert("UNAUTHORIZED");

        // Execute state transition
        vm.prank(testAccounts[0]);

        autoPxGmx.setWithdrawalPenalty(penalty);
    }

    /**
        @notice Test tx reversion: penalty exceeds max
     */
    function testCannotSetWithdrawalPenaltyExceedsMax() external {
        uint256 invalidPenalty = autoPxGmx.MAX_WITHDRAWAL_PENALTY() + 1;

        vm.expectRevert(AutoPxGmx.ExceedsMax.selector);

        autoPxGmx.setWithdrawalPenalty(invalidPenalty);
    }

    /**
        @notice Test tx success: set withdrawal penalty
     */
    function testSetWithdrawalPenalty() external {
        uint256 initialWithdrawalPenalty = autoPxGmx.withdrawalPenalty();
        uint256 penalty = 1;
        uint256 expectedWithdrawalPenalty = penalty;

        vm.expectEmit(false, false, false, true, address(autoPxGmx));

        emit WithdrawalPenaltyUpdated(expectedWithdrawalPenalty);

        autoPxGmx.setWithdrawalPenalty(penalty);

        assertEq(expectedWithdrawalPenalty, autoPxGmx.withdrawalPenalty());
        assertTrue(expectedWithdrawalPenalty != initialWithdrawalPenalty);
    }

    /*//////////////////////////////////////////////////////////////
                        setPlatformFee TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetPlatformFeeUnauthorized() external {
        uint256 fee = 1;

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(testAccounts[0]);

        autoPxGmx.setPlatformFee(fee);
    }

    /**
        @notice Test tx reversion: fee exceeds max
     */
    function testCannotSetPlatformFeeExceedsMax() external {
        uint256 invalidFee = autoPxGmx.MAX_PLATFORM_FEE() + 1;

        vm.expectRevert(AutoPxGmx.ExceedsMax.selector);

        autoPxGmx.setPlatformFee(invalidFee);
    }

    /**
        @notice Test tx success: set platform fee
     */
    function testSetPlatformFee() external {
        uint256 initialPlatformFee = autoPxGmx.platformFee();
        uint256 fee = 1;
        uint256 expectedPlatformFee = fee;

        vm.expectEmit(false, false, false, true, address(autoPxGmx));

        emit PlatformFeeUpdated(expectedPlatformFee);

        autoPxGmx.setPlatformFee(fee);

        assertEq(expectedPlatformFee, autoPxGmx.platformFee());
        assertTrue(expectedPlatformFee != initialPlatformFee);
    }

    /*//////////////////////////////////////////////////////////////
                        setCompoundIncentive TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetCompoundIncentiveUnauthorized() external {
        uint256 incentive = 1;

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(testAccounts[0]);

        autoPxGmx.setCompoundIncentive(incentive);
    }

    /**
        @notice Test tx reversion: incentive exceeds max
     */
    function testCannotSetCompoundIncentiveExceedsMax() external {
        uint256 invalidIncentive = autoPxGmx.MAX_COMPOUND_INCENTIVE() + 1;

        vm.expectRevert(AutoPxGmx.ExceedsMax.selector);

        autoPxGmx.setCompoundIncentive(invalidIncentive);
    }

    /**
        @notice Test tx success: set compound incentive percent
     */
    function testSetCompoundIncentive() external {
        uint256 initialCompoundIncentive = autoPxGmx.compoundIncentive();
        uint256 incentive = 1;
        uint256 expectedCompoundIncentive = incentive;

        vm.expectEmit(false, false, false, true, address(autoPxGmx));

        emit CompoundIncentiveUpdated(expectedCompoundIncentive);

        autoPxGmx.setCompoundIncentive(incentive);

        assertEq(expectedCompoundIncentive, autoPxGmx.compoundIncentive());
        assertTrue(expectedCompoundIncentive != initialCompoundIncentive);
    }

    /*//////////////////////////////////////////////////////////////
                        setPlatform TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetPlatformUnauthorized() external {
        address platform = address(this);

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(testAccounts[0]);

        autoPxGmx.setPlatform(platform);
    }

    /**
        @notice Test tx reversion: platform is zero address
     */
    function testCannotSetPlatformZeroAddress() external {
        address invalidPlatform = address(0);

        vm.expectRevert(AutoPxGmx.ZeroAddress.selector);

        autoPxGmx.setPlatform(invalidPlatform);
    }

    /**
        @notice Test tx success: set platform
     */
    function testSetPlatform() external {
        address initialPlatform = autoPxGmx.platform();
        address platform = address(this);
        address expectedPlatform = platform;

        vm.expectEmit(false, false, false, true, address(autoPxGmx));

        emit PlatformUpdated(expectedPlatform);

        autoPxGmx.setPlatform(platform);

        assertEq(expectedPlatform, autoPxGmx.platform());
        assertTrue(expectedPlatform != initialPlatform);
    }

    /*//////////////////////////////////////////////////////////////
                        setRewardsModule TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetRewardsModuleUnauthorized() external {
        address rewardsModule = address(this);

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(testAccounts[0]);

        autoPxGmx.setRewardsModule(rewardsModule);
    }

    /**
        @notice Test tx reversion: rewardsModule is zero address
     */
    function testCannotSetRewardsModuleZeroAddress() external {
        address invalidRewardsModule = address(0);

        vm.expectRevert(AutoPxGmx.ZeroAddress.selector);

        autoPxGmx.setRewardsModule(invalidRewardsModule);
    }

    /**
        @notice Test tx success: set rewardsModule
     */
    function testSetRewardsModule() external {
        address initialRewardsModule = autoPxGmx.rewardsModule();
        address rewardsModule = address(this);
        address expectedRewardsModule = rewardsModule;

        vm.expectEmit(false, false, false, true, address(autoPxGmx));

        emit RewardsModuleUpdated(expectedRewardsModule);

        autoPxGmx.setRewardsModule(rewardsModule);

        assertEq(expectedRewardsModule, autoPxGmx.rewardsModule());
        assertTrue(expectedRewardsModule != initialRewardsModule);
    }

    /*//////////////////////////////////////////////////////////////
                        totalAssets TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice  Test tx success: return the total assets
    */
    function testTotalAssets() external {
        uint256 initialTotalAssets = autoPxGmx.totalAssets();
        uint256 assets = 1;
        address receiver = address(this);
        uint256 expectedTotalAssets = assets;

        _depositGmx(assets, receiver);
        pxGmx.approve(address(autoPxGmx), assets);
        autoPxGmx.deposit(assets, receiver);

        assertEq(expectedTotalAssets, autoPxGmx.totalAssets());
        assertTrue(expectedTotalAssets != initialTotalAssets);
    }

    /*//////////////////////////////////////////////////////////////
                        compound TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: fee is invalid param
     */
    function testCannotCompoundFeeInvalidParam() external {
        uint24 invalidFee = 0;
        uint256 amountOutMinimum = 1;
        uint160 sqrtPriceLimitX96 = 1;
        bool optOutIncentive = true;

        vm.expectRevert(AutoPxGmx.InvalidParam.selector);

        autoPxGmx.compound(
            invalidFee,
            amountOutMinimum,
            sqrtPriceLimitX96,
            optOutIncentive
        );
    }

    /**
        @notice Test tx reversion: amountOutMinimum is invalid param
     */
    function testCannotCompoundAmountOutMinimumInvalidParam() external {
        uint24 fee = 3000;
        uint256 invalidAmountOutMinimum = 0;
        uint160 sqrtPriceLimitX96 = 1;
        bool optOutIncentive = true;

        vm.expectRevert(AutoPxGmx.InvalidParam.selector);

        autoPxGmx.compound(
            fee,
            invalidAmountOutMinimum,
            sqrtPriceLimitX96,
            optOutIncentive
        );
    }

    /**
        @notice Test tx success: compound pxGMX rewards into more pxGMX
        @param  gmxAmount       uint96  Amount of pxGMX to get from the deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testCompound(uint96 gmxAmount, uint32 secondsElapsed) external {
        vm.assume(gmxAmount > 5e17);
        vm.assume(gmxAmount < 100000e18);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);

        // Configure initial pre-compound state
        autoPxGmx.setRewardsModule(address(pirexRewards));

        (
            uint256 wethRewardState,
            uint256 pxGmxRewardState
        ) = _provisionRewardState(gmxAmount, address(this), secondsElapsed);
        uint256 totalAssetsBeforeCompound = autoPxGmx.totalAssets();
        uint256 shareToAssetAmountBeforeCompound = autoPxGmx.convertToAssets(
            autoPxGmx.balanceOf(address(this))
        );

        // Confirm current state prior to primary state mutating action
        assertEq(gmxAmount, autoPxGmx.balanceOf(address(this)));
        assertEq(gmxAmount, totalAssetsBeforeCompound);
        assertGt(wethRewardState, 0);
        assertGt(pxGmxRewardState, 0);
        assertEq(0, pxGmx.balanceOf(autoPxGmx.owner()));

        vm.expectEmit(true, false, false, false, address(autoPxGmx));

        emit Compounded(testAccounts[0], 3000, 1, 0, 0, 0, 0, 0, 0);

        // Call as testAccounts[0] to test compound incentive transfer
        vm.prank(testAccounts[0]);

        // Input literal argument values due to callstack depth error
        (
            uint256 wethAmountIn,
            uint256 gmxAmountOut,
            uint256 pxGmxMintAmount,
            uint256 totalFee,
            uint256 incentive
        ) = autoPxGmx.compound(3000, 1, 0, false);

        uint256 expectedTotalFee = ((pxGmxMintAmount + pxGmxRewardState) *
            autoPxGmx.platformFee()) / autoPxGmx.FEE_DENOMINATOR();
        uint256 expectedCompoundIncentive = (totalFee *
            autoPxGmx.compoundIncentive()) / autoPxGmx.FEE_DENOMINATOR();
        uint256 expectedPlatformFee = expectedTotalFee -
            expectedCompoundIncentive;
        uint256 expectedTotalAssets = totalAssetsBeforeCompound +
            pxGmxMintAmount +
            pxGmxRewardState -
            expectedTotalFee;
        uint256 expectedShareToAssetAmountDifference = ((autoPxGmx.balanceOf(
            address(this)
        ) * expectedTotalAssets) / autoPxGmx.totalSupply()) -
            shareToAssetAmountBeforeCompound;

        assertEq(wethRewardState, wethAmountIn);

        // // This will not always be the case in production (external party transfers GMX to vault)
        // // But for this test, this assertion should hold true
        assertEq(gmxAmountOut, pxGmxMintAmount);

        assertEq(
            gmxAmountOut + pxGmxRewardState - expectedTotalFee,
            autoPxGmx.totalAssets() - totalAssetsBeforeCompound
        );
        assertEq(
            pxGmxMintAmount + pxGmxRewardState - expectedTotalFee,
            autoPxGmx.totalAssets() - totalAssetsBeforeCompound
        );
        assertGt(expectedTotalAssets, totalAssetsBeforeCompound);
        assertEq(expectedTotalAssets, autoPxGmx.totalAssets());
        assertEq(
            expectedShareToAssetAmountDifference,
            autoPxGmx.convertToAssets(autoPxGmx.balanceOf(address(this))) -
                shareToAssetAmountBeforeCompound
        );
        assertEq(expectedTotalFee, totalFee);
        assertEq(expectedCompoundIncentive, incentive);
        assertEq(expectedPlatformFee + expectedCompoundIncentive, totalFee);
        assertEq(expectedPlatformFee, pxGmx.balanceOf(autoPxGmx.owner()));
        assertEq(expectedCompoundIncentive, pxGmx.balanceOf(testAccounts[0]));
        assertLt(
            shareToAssetAmountBeforeCompound,
            autoPxGmx.convertToAssets(autoPxGmx.balanceOf(address(this)))
        );
    }
}