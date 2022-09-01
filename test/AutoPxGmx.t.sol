// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {AutoPxGmx} from "src/vaults/AutoPxGmx.sol";
import {Helper} from "./Helper.t.sol";

contract AutoPxGmxTest is Helper {
    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event PlatformUpdated(address _platform);
    event RewardsModuleUpdated(address _rewardsModule);

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
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotCompoundUnauthorized() external {
        uint24 fee = 3000;
        uint256 amountOutMinimum = 1;
        uint160 sqrtPriceLimitX96 = 1;

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(testAccounts[0]);

        autoPxGmx.compound(fee, amountOutMinimum, sqrtPriceLimitX96);
    }

    /**
        @notice Test tx reversion: fee is invalid param
     */
    function testCannotCompoundFeeInvalidParam() external {
        uint24 invalidFee = 0;
        uint256 amountOutMinimum = 1;
        uint160 sqrtPriceLimitX96 = 1;

        vm.expectRevert(AutoPxGmx.InvalidParam.selector);

        autoPxGmx.compound(invalidFee, amountOutMinimum, sqrtPriceLimitX96);
    }

    /**
        @notice Test tx reversion: amountOutMinimum is invalid param
     */
    function testCannotCompoundAmountOutMinimumInvalidParam() external {
        uint24 fee = 3000;
        uint256 invalidAmountOutMinimum = 0;
        uint160 sqrtPriceLimitX96 = 1;

        vm.expectRevert(AutoPxGmx.InvalidParam.selector);

        autoPxGmx.compound(fee, invalidAmountOutMinimum, sqrtPriceLimitX96);
    }

    /**
        @notice Test tx reversion: sqrtPriceLimitX96 is invalid param
     */
    function testCannotCompoundSqrtPriceLimitX96InvalidParam() external {
        uint24 fee = 3000;
        uint256 amountOutMinimum = 1;
        uint160 invalidSqrtPriceLimitX96 = 0;

        vm.expectRevert(AutoPxGmx.InvalidParam.selector);

        autoPxGmx.compound(fee, amountOutMinimum, invalidSqrtPriceLimitX96);
    }
}
