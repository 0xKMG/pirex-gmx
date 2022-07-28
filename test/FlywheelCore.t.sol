// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {FlywheelCore} from "src/FlywheelCore.sol";
import {Helper} from "./Helper.t.sol";

contract FlywheelCoreTest is Helper {
    /**
        @notice Mint pxGLP for test accounts
        @param  multiplier  uint256  Multiplied with fixed token amounts for randomness
        @param  useETH      bool     Whether or not to use ETH as the source asset for minting GLP
     */
    function _mintForTestAccounts(uint256 multiplier, bool useETH) internal {
        uint256 tLen = testAccounts.length;
        uint256[] memory tokenAmounts = new uint256[](tLen);

        // Conditionally set ETH or WBTC amounts and call the appropriate method for acquiring
        if (useETH) {
            tokenAmounts[0] = 1 ether * multiplier;
            tokenAmounts[1] = 2 ether * multiplier;
            tokenAmounts[2] = 3 ether * multiplier;

            vm.deal(
                address(this),
                tokenAmounts[0] + tokenAmounts[1] + tokenAmounts[2]
            );
        } else {
            tokenAmounts[0] = 1e8 * multiplier;
            tokenAmounts[1] = 2e8 * multiplier;
            tokenAmounts[2] = 3e8 * multiplier;
            uint256 wBtcTotalAmount = tokenAmounts[0] +
                tokenAmounts[1] +
                tokenAmounts[2];

            _mintWbtc(wBtcTotalAmount);
            WBTC.approve(address(pirexGlp), wBtcTotalAmount);
        }

        // Iterate over test accounts and mint pxGLP for each to kick off reward accrual
        for (uint256 i; i < tLen; ++i) {
            uint256 tokenAmount = tokenAmounts[i];

            // Call the appropriate method based on the type of currency
            if (useETH) {
                pirexGlp.mintWithETH{value: tokenAmount}(1, testAccounts[i]);
            } else {
                pirexGlp.mintWithERC20(
                    address(WBTC),
                    tokenAmount,
                    1,
                    testAccounts[i]
                );
            }
        }
    }

    /**
        @notice Test minting pxGLP and reward point accrual for multiple users
        @param  secondsElapsed  uint256  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  multiplier      uint256  Multiplied with fixed token amounts for randomness
        @param  useETH          bool     Whether or not to use ETH as the source asset for minting GLP
     */
    function testAccrue(
        uint256 secondsElapsed,
        uint256 multiplier,
        bool useETH
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 604800);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        _mintForTestAccounts(multiplier, useETH);

        // Forward timestamp by X seconds which will determine the total amount of rewards accrued
        vm.warp(block.timestamp + secondsElapsed);

        (
            uint256 globalLastUpdateBeforeAccrue,
            uint256 globalRewardsBeforeAccrue,
            ,

        ) = flywheelCore.globalState();

        vm.prank(address(flywheelCore));

        uint256 timestampBeforeAccrue = block.timestamp;
        uint256 expectedGlobalRewards = globalRewardsBeforeAccrue +
            (timestampBeforeAccrue - globalLastUpdateBeforeAccrue) *
            pxGlp.totalSupply();

        flywheelCore.globalAccrue();

        (
            uint256 globalLastUpdateAfterAccrue,
            uint256 globalRewardsAfterAccrue,
            ,

        ) = flywheelCore.globalState();
        uint256 totalRewards;

        assertEq(globalLastUpdateAfterAccrue, timestampBeforeAccrue);
        assertEq(globalRewardsAfterAccrue, expectedGlobalRewards);

        // Iterate over test accounts and check that reward accrual amount is correct for each one
        for (uint256 i; i < testAccounts.length; ++i) {
            (
                uint256 lastUpdateBeforeAccrue,
                uint256 lastBalanceBeforeAccrue,
                uint256 rewardsBeforeAccrue
            ) = flywheelCore.userStates(testAccounts[i]);
            uint256 balanceBeforeAccrue = pxGlp.balanceOf(testAccounts[i]);
            uint256 expectedRewards = rewardsBeforeAccrue +
                lastBalanceBeforeAccrue *
                (timestampBeforeAccrue - lastUpdateBeforeAccrue);

            assertGt(expectedRewards, 0);

            flywheelCore.userAccrue(testAccounts[i]);

            (
                uint256 lastUpdateAfterAccrue,
                uint256 lastBalanceAfterAccrue,
                uint256 rewardsAfterAccrue
            ) = flywheelCore.userStates(testAccounts[i]);

            // Total rewards accrued by all users should add up to the gloabl rewards
            totalRewards += rewardsAfterAccrue;

            assertEq(lastUpdateAfterAccrue, timestampBeforeAccrue);
            assertEq(balanceBeforeAccrue, lastBalanceAfterAccrue);
            assertEq(expectedRewards, rewardsAfterAccrue);
        }

        assertEq(globalRewardsAfterAccrue, totalRewards);
    }
}
