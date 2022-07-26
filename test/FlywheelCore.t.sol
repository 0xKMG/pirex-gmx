// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {FlywheelCore} from "src/rewards/FlywheelCore.sol";
import {Helper} from "./Helper.t.sol";

contract FlywheelCoreTest is Test, Helper {
    /**
        @notice Test minting pxGLP and reward point accrual for multiple users
        @param  secondsElapsed         uint256  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  etherAmountMultiplier  uint256  Multiplied with fixed ether amounts to maintain randomness when minting
     */
    function testAccrue(uint256 secondsElapsed, uint256 etherAmountMultiplier)
        external
    {
        vm.assume(secondsElapsed > 5);
        vm.assume(secondsElapsed < 604800);
        vm.assume(etherAmountMultiplier != 0);
        vm.assume(etherAmountMultiplier < 10);

        uint256 tLen = testAccounts.length;
        uint256[] memory etherAmounts = new uint256[](tLen);
        etherAmounts[0] = 1 ether * etherAmountMultiplier;
        etherAmounts[1] = 2 ether * etherAmountMultiplier;
        etherAmounts[2] = 3 ether * etherAmountMultiplier;

        vm.deal(
            address(this),
            etherAmounts[0] + etherAmounts[1] + etherAmounts[2]
        );

        // Iterate over test accounts and mint pxGLP for each to kick off reward accrual
        for (uint256 i; i < tLen; ++i) {
            uint256 etherAmount = etherAmounts[i];

            pirexGlp.mintWithETH{value: etherAmount}(1, testAccounts[i]);
        }

        // Forward timestamp by X seconds which will determine the total amount of rewards accrued
        vm.warp(block.timestamp + secondsElapsed);

        // Get the total accrued rewards which will enable us to calculate reward accrual amounts per user
        (, uint32 lastUpdatedTimestamp) = flywheelCore.strategyState(pxGlp);

        vm.prank(address(flywheelCore));

        uint256 totalRewardsAccrued = flywheelRewards.getAccruedRewards(
            pxGlp,
            lastUpdatedTimestamp
        );
        uint256 totalPxGlpSupply = pxGlp.totalSupply();

        // Iterate over test accounts and check that reward accrual amount is correct for each one
        for (uint256 j; j < tLen; ++j) {
            address testAccount = testAccounts[j];
            uint256 rewardsAccruedBefore = flywheelCore.rewardsAccrued(
                testAccount
            );
            uint256 expectedRewardsAccrued = (pxGlp.balanceOf(testAccount) *
                totalRewardsAccrued) / totalPxGlpSupply;

            // Call accrue in order to update the amount of rewards user has accrued
            flywheelCore.accrue(pxGlp, testAccount);

            assertGt(expectedRewardsAccrued, 0);

            // Delta between rewards accrued before and now should be equal to the amonut of seconds elapsed
            assertTrue(
                flywheelCore.rewardsAccrued(testAccount) -
                    rewardsAccruedBefore ==
                    expectedRewardsAccrued
            );
        }
    }
}
