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

    function _getGlobalRewardsAccrued() internal returns (uint256) {
        (uint256 lastUpdate, uint256 rewards, , ) = flywheelCore.globalState();

        vm.prank(address(flywheelCore));

        return rewards + (block.timestamp - lastUpdate) * pxGlp.totalSupply();
    }

    /**
        @notice Test minting pxGLP and reward point accrual for multiple users
        @param  secondsElapsed  uint256  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  multiplier      uint256  Multiplied with fixed token amounts for randomness
        @param  useETH          bool     Whether or not to use ETH as the source asset for minting GLP
        @param  accrueGlobal    bool     Whether or not to update global reward accrual state
     */
    function testAccrue(
        uint256 secondsElapsed,
        uint256 multiplier,
        bool useETH,
        bool accrueGlobal
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        _mintForTestAccounts(multiplier, useETH);

        // Forward timestamp by X seconds which will determine the total amount of rewards accrued
        vm.warp(block.timestamp + secondsElapsed);

        uint256 timestampBeforeAccrue = block.timestamp;
        uint256 expectedGlobalRewards = _getGlobalRewardsAccrued();

        if (accrueGlobal) {
            flywheelCore.globalAccrue();

            (
                uint256 globalLastUpdateAfterAccrue,
                uint256 globalRewardsAfterAccrue,
                ,

            ) = flywheelCore.globalState();

            assertEq(globalLastUpdateAfterAccrue, timestampBeforeAccrue);
            assertEq(globalRewardsAfterAccrue, expectedGlobalRewards);
        }

        // The sum of all user rewards accrued for comparison against the expected global amount
        uint256 totalRewards;

        // Iterate over test accounts and check that reward accrual amount is correct for each one
        for (uint256 i; i < testAccounts.length; ++i) {
            address testAccount = testAccounts[i];
            (
                uint256 lastUpdateBeforeAccrue,
                uint256 lastBalanceBeforeAccrue,
                uint256 rewardsBeforeAccrue
            ) = flywheelCore.userStates(testAccount);
            uint256 balanceBeforeAccrue = pxGlp.balanceOf(testAccount);
            uint256 expectedRewards = rewardsBeforeAccrue +
                lastBalanceBeforeAccrue *
                (timestampBeforeAccrue - lastUpdateBeforeAccrue);

            assertGt(expectedRewards, 0);

            flywheelCore.userAccrue(testAccount);

            (
                uint256 lastUpdateAfterAccrue,
                uint256 lastBalanceAfterAccrue,
                uint256 rewardsAfterAccrue
            ) = flywheelCore.userStates(testAccount);

            // Total rewards accrued by all users should add up to the gloabl rewards
            totalRewards += rewardsAfterAccrue;

            assertEq(lastUpdateAfterAccrue, timestampBeforeAccrue);
            assertEq(balanceBeforeAccrue, lastBalanceAfterAccrue);
            assertEq(expectedRewards, rewardsAfterAccrue);
        }

        assertEq(expectedGlobalRewards, totalRewards);
    }

    /**
        @notice Test minting pxGLP and reward point accrual for multiple users with one who accrues asynchronously
        @param  rounds               uint256  Number of rounds to fast forward time and accrue rewards
        @param  multiplier           uint256  Multiplied with fixed token amounts for randomness
        @param  useETH               bool     Whether or not to use ETH as the source asset for minting GLP
        @param  delayedAccountIndex  uint256  Test account index that will delay reward accrual until the end
     */
    function testAccrueAsync(
        uint256 rounds,
        uint256 multiplier,
        bool useETH,
        uint256 delayedAccountIndex
    ) external {
        vm.assume(rounds != 0);
        vm.assume(rounds < 10);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);
        vm.assume(delayedAccountIndex < 3);

        _mintForTestAccounts(multiplier, useETH);

        // Sum up the rewards accrued - after all rounds - for accounts where accrual is not delayed
        uint256 nonDelayedTotalRewards;

        uint256 secondsElapsed = 1000;
        uint256 tLen = testAccounts.length;

        // Iterate over a number of rounds and accrue for non-delayed accounts
        for (uint256 i; i < rounds; ++i) {
            uint256 timestampBeforeAccrue = block.timestamp;

            // Forward timestamp by X seconds which will determine the total amount of rewards accrued
            vm.warp(timestampBeforeAccrue + secondsElapsed);

            for (uint256 j; j < tLen; ++j) {
                if (j != delayedAccountIndex) {
                    (, , uint256 rewardsBefore) = flywheelCore.userStates(
                        testAccounts[j]
                    );

                    flywheelCore.userAccrue(testAccounts[j]);

                    (, , uint256 rewardsAfter) = flywheelCore.userStates(
                        testAccounts[j]
                    );

                    nonDelayedTotalRewards += rewardsAfter - rewardsBefore;
                }
            }
        }

        // Calculate the rewards which should be accrued by the delayed account
        address delayedAccount = testAccounts[delayedAccountIndex];
        (
            uint256 lastUpdateBeforeAccrue,
            ,
            uint256 rewardsBeforeAccrue
        ) = flywheelCore.userStates(delayedAccount);
        uint256 expectedDelayedRewards = rewardsBeforeAccrue +
            pxGlp.balanceOf(delayedAccount) *
            (block.timestamp - lastUpdateBeforeAccrue);
        uint256 expectedGlobalRewards = _getGlobalRewardsAccrued();

        // Accrue rewards and check that the actual amount matches the expected
        flywheelCore.userAccrue(delayedAccount);

        (, , uint256 rewardsAfterAccrue) = flywheelCore.userStates(
            delayedAccount
        );

        assertEq(rewardsAfterAccrue, expectedDelayedRewards);
        assertEq(
            nonDelayedTotalRewards + rewardsAfterAccrue,
            expectedGlobalRewards
        );
    }

    /**
        @notice Test correctness of reward accruals in the case of pxGLP transfers
        @param  tokenAmount     uint256  Amount of pxGLP to mint the sender
        @param  secondsElapsed  uint256  Seconds to forward timestamp (equivalent to total rewards accrued)
     */
    function testAccrueTransfer(uint256 tokenAmount, uint256 secondsElapsed)
        external
    {
        vm.assume(tokenAmount > 0.001 ether);
        vm.assume(tokenAmount < 10000 ether);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);

        address sender = testAccounts[0];
        address receiver = testAccounts[1];

        vm.deal(address(this), tokenAmount);

        pirexGlp.mintWithETH{value: tokenAmount}(1, sender);

        // Forward time in order to accrue rewards for sender
        vm.warp(block.timestamp + secondsElapsed);

        // Test sender reward accrual before transfer
        (
            uint256 senderLastUpdateBeforeTransfer,
            uint256 senderLastBalanceBeforeTransfer,
            uint256 senderRewardsBeforeTransfer
        ) = flywheelCore.userStates(sender);
        uint256 transferAmount = pxGlp.balanceOf(sender);
        uint256 expectedSenderRewards = senderRewardsBeforeTransfer +
            senderLastBalanceBeforeTransfer *
            (block.timestamp - senderLastUpdateBeforeTransfer);

        vm.prank(sender);

        pxGlp.transfer(receiver, transferAmount);

        (, , uint256 senderRewardsAfterTransfer) = flywheelCore.userStates(
            sender
        );

        assertEq(expectedSenderRewards, senderRewardsAfterTransfer);

        // Forward time in order to accrue rewards for receiver
        vm.warp(block.timestamp + secondsElapsed);

        // Test receiver reward accrual
        (
            uint256 receiverLastUpdateBeforeAccrue,
            uint256 receiverLastBalanceBeforeAccrue,
            uint256 receiverRewardsBeforeAccrue
        ) = flywheelCore.userStates(receiver);
        uint256 expectedReceiverRewards = receiverRewardsBeforeAccrue +
            receiverLastBalanceBeforeAccrue *
            (block.timestamp - receiverLastUpdateBeforeAccrue);

        // Accrue rewards for both sender and receiver
        flywheelCore.userAccrue(sender);
        flywheelCore.userAccrue(receiver);

        // Test that sender has not accrued any additional rewards
        (, , uint256 senderRewardsAfterTransferAndWarp) = flywheelCore
            .userStates(sender);

        // Test that receiver has accrued rewards from their new balance
        (, , uint256 receiverRewardsAfterTransferAndWarp) = flywheelCore
            .userStates(receiver);

        assertEq(senderRewardsAfterTransferAndWarp, senderRewardsAfterTransfer);
        assertEq(expectedReceiverRewards, receiverRewardsAfterTransferAndWarp);
    }
}
