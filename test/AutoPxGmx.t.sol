// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {AutoPxGmx} from "src/vaults/AutoPxGmx.sol";
import {Helper} from "./Helper.t.sol";

contract AutoPxGmxTest is Test, Helper {
    uint256 internal constant DEFAULT_WITHDRAWAL_PENALTY = 300;
    uint256 internal constant DEFAULT_PLATFORM_FEE = 1000;
    address internal constant DEFAULT_PLATFORM = address(0);
    uint256 internal constant DEFAULT_TOTAL_ASSETS = 0;

    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event PlatformUpdated(address indexed _platform);

    /*//////////////////////////////////////////////////////////////
                        setWithdrawalPenalty TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetWithdrawalPenaltyUnauthorized() external {
        // Confirm pre-transition/current state
        assertEq(DEFAULT_WITHDRAWAL_PENALTY, autoPxGmx.withdrawalPenalty());

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
        assertEq(DEFAULT_WITHDRAWAL_PENALTY, autoPxGmx.withdrawalPenalty());

        uint256 invalidPenalty = autoPxGmx.MAX_WITHDRAWAL_PENALTY() + 1;

        vm.expectRevert(AutoPxGmx.ExceedsMax.selector);

        autoPxGmx.setWithdrawalPenalty(invalidPenalty);
    }

    /**
        @notice Test tx success: set withdrawal penalty
     */
    function testSetWithdrawalPenalty() external {
        assertEq(DEFAULT_WITHDRAWAL_PENALTY, autoPxGmx.withdrawalPenalty());

        uint256 penalty = 1;
        uint256 expectedWithdrawalPenalty = penalty;

        vm.expectEmit(false, false, false, true, address(autoPxGmx));

        emit WithdrawalPenaltyUpdated(expectedWithdrawalPenalty);

        autoPxGmx.setWithdrawalPenalty(penalty);

        assertEq(expectedWithdrawalPenalty, autoPxGmx.withdrawalPenalty());
        assertTrue(expectedWithdrawalPenalty != DEFAULT_WITHDRAWAL_PENALTY);
    }

    /*//////////////////////////////////////////////////////////////
                        setPlatformFee TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetPlatformFeeUnauthorized() external {
        assertEq(DEFAULT_PLATFORM_FEE, autoPxGmx.platformFee());

        uint256 fee = 1;

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(testAccounts[0]);

        autoPxGmx.setPlatformFee(fee);
    }

    /**
        @notice Test tx reversion: fee exceeds max
     */
    function testCannotSetPlatformFeeExceedsMax() external {
        assertEq(DEFAULT_PLATFORM_FEE, autoPxGmx.platformFee());

        uint256 invalidFee = autoPxGmx.MAX_PLATFORM_FEE() + 1;

        vm.expectRevert(AutoPxGmx.ExceedsMax.selector);

        autoPxGmx.setPlatformFee(invalidFee);
    }

    /**
        @notice Test tx success: set platform fee
     */
    function testSetPlatformFee() external {
        assertEq(DEFAULT_PLATFORM_FEE, autoPxGmx.platformFee());

        uint256 fee = 1;
        uint256 expectedPlatformFee = fee;

        vm.expectEmit(false, false, false, true, address(autoPxGmx));

        emit PlatformFeeUpdated(expectedPlatformFee);

        autoPxGmx.setPlatformFee(fee);

        assertEq(expectedPlatformFee, autoPxGmx.platformFee());
        assertTrue(expectedPlatformFee != DEFAULT_PLATFORM_FEE);
    }

    /*//////////////////////////////////////////////////////////////
                        setPlatform TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetPlatformUnauthorized() external {
        assertEq(DEFAULT_PLATFORM, autoPxGmx.platform());

        address platform = address(this);

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(testAccounts[0]);

        autoPxGmx.setPlatform(platform);
    }

    /**
        @notice Test tx reversion: platform is zero address
     */
    function testCannotSetPlatformZeroAddress() external {
        assertEq(DEFAULT_PLATFORM, autoPxGmx.platform());

        address invalidPlatform = address(0);

        vm.expectRevert(AutoPxGmx.ZeroAddress.selector);

        autoPxGmx.setPlatform(invalidPlatform);
    }

    /**
        @notice Test tx success: set platform
     */
    function testSetPlatform() external {
        assertEq(DEFAULT_PLATFORM, autoPxGmx.platform());

        address platform = address(this);
        address expectedPlatform = platform;

        vm.expectEmit(true, false, false, true, address(autoPxGmx));

        emit PlatformUpdated(expectedPlatform);

        autoPxGmx.setPlatform(platform);

        assertEq(expectedPlatform, autoPxGmx.platform());
        assertTrue(expectedPlatform != DEFAULT_PLATFORM);
    }

    /*//////////////////////////////////////////////////////////////
                        totalAssets TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice  Test tx success: return the total assets
    */
    function testTotalAssets() external {
        assertEq(DEFAULT_TOTAL_ASSETS, autoPxGmx.totalAssets());

        uint256 assets = 1;
        address receiver = address(this);
        uint256 expectedTotalAssets = assets;

        _depositGmx(assets, receiver);
        pxGmx.approve(address(autoPxGmx), assets);
        autoPxGmx.deposit(assets, receiver);

        assertEq(expectedTotalAssets, autoPxGmx.totalAssets());
    }
}
