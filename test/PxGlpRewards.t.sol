// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PxGlpRewards} from "src/PxGlpRewards.sol";
import {PirexGlp} from "src/PirexGlp.sol";
import {Helper} from "./Helper.t.sol";

contract PxGlpRewardsTest is Helper {
    event SetStrategy(address newStrategy);
    event SetPirexGlp(address pirexGlp);
    event ClaimWETHRewards(
        address indexed caller,
        address indexed receiver,
        uint256 globalRewardsBeforeClaim,
        uint256 userRewardsBeforeClaim,
        uint256 wethFromGmx,
        uint256 wethFromGlp
    );

    /**
        @notice Mint pxGLP for test accounts
        @param  multiplier  uint256  Multiplied with fixed token amounts (uint256 to avoid overflow)
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
                pirexGlp.depositWithETH{value: tokenAmount}(1, testAccounts[i]);
            } else {
                pirexGlp.depositWithERC20(
                    address(WBTC),
                    tokenAmount,
                    1,
                    testAccounts[i]
                );
            }
        }
    }

    /**
        @notice Calculate the global rewards
        @return uint256  Global rewards
    */
    function _calculateGlobalRewards() internal view returns (uint256) {
        (uint256 lastUpdate, uint256 rewards, , ) = pxGlpRewards.globalState();

        return rewards + (block.timestamp - lastUpdate) * pxGlp.totalSupply();
    }

    /**
        @notice Calculate a user's rewards
        @param  user  address  User
        @return       uint256  User rewards
    */
    function _calculateUserRewards(address user)
        internal
        view
        returns (uint256)
    {
        (
            uint256 lastUpdate,
            uint256 lastBalance,
            uint256 previousRewards
        ) = pxGlpRewards.userStates(user);

        return previousRewards + lastBalance * (block.timestamp - lastUpdate);
    }

    /*//////////////////////////////////////////////////////////////
                        setStrategyForRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to caller not being the owner
     */
    function testCannotSetStrategyForRewardsNotOwner() external {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(testAccounts[0]);

        pxGlpRewards.setStrategyForRewards(ERC20(address(this)));
    }

    /**
        @notice Test tx reversion due to _strategy being the zero address
     */
    function testCannotSetStrategyForRewardsStrategyZeroAddress() external {
        ERC20 invalidStrategy = ERC20(address(0));

        vm.expectRevert(PxGlpRewards.ZeroAddress.selector);

        pxGlpRewards.setStrategyForRewards(invalidStrategy);
    }

    /**
        @notice Test setting strategy
     */
    function testSetStrategyForRewards() external {
        ERC20 strategy = ERC20(address(this));
        address strategyAddr = address(strategy);

        assertTrue(strategyAddr != address(pxGlpRewards.strategy()));

        vm.expectEmit(false, false, false, true, address(pxGlpRewards));

        emit SetStrategy(strategyAddr);

        pxGlpRewards.setStrategyForRewards(strategy);

        assertEq(strategyAddr, address(pxGlpRewards.strategy()));
    }

    /*//////////////////////////////////////////////////////////////
                        setPirexGlp TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to caller not being the owner
     */
    function testCannotSetPirexGlpNotOwner() external {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(testAccounts[0]);

        pxGlpRewards.setPirexGlp(PirexGlp(address(this)));
    }

    /**
        @notice Test tx reversion due to _pirexGlp being the zero address
     */
    function testCannotSetPirexGlpPirexGlpZeroAddress() external {
        PirexGlp invalidPirexGlp = PirexGlp(address(0));

        vm.expectRevert(PxGlpRewards.ZeroAddress.selector);

        pxGlpRewards.setPirexGlp(invalidPirexGlp);
    }

    /**
        @notice Test setting pirexGlp
     */
    function testSetPirexGlp() external {
        PirexGlp _pirexGlp = PirexGlp(address(this));
        address pirexGlpAddr = address(_pirexGlp);

        assertTrue(pirexGlpAddr != address(pxGlpRewards.pirexGlp()));

        vm.expectEmit(false, false, false, true, address(pxGlpRewards));

        emit SetPirexGlp(pirexGlpAddr);

        pxGlpRewards.setPirexGlp(_pirexGlp);

        assertEq(pirexGlpAddr, address(pxGlpRewards.pirexGlp()));
    }

    /*//////////////////////////////////////////////////////////////
                        globalAccrue TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test global rewards accrual
        @param  secondsElapsed  uint32   Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  multiplier      uint8    Multiplied with fixed token amounts for randomness
        @param  useETH          bool     Whether or not to use ETH as the source asset for minting GLP
     */
    function testGlobalAccrue(
        uint32 secondsElapsed,
        uint8 multiplier,
        bool useETH
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        (
            uint256 lastUpdateBefore,
            uint256 rewardsBefore,
            ,
            uint256 wethFromGlpBefore
        ) = pxGlpRewards.globalState();
        uint256 warpTimestamp = block.timestamp + secondsElapsed;

        assertEq(lastUpdateBefore, 0);
        assertEq(rewardsBefore, 0);
        assertEq(wethFromGlpBefore, 0);

        _mintForTestAccounts(multiplier, useETH);

        vm.warp(warpTimestamp);

        uint256 expectedGlobalRewards = _calculateGlobalRewards();

        pxGlpRewards.globalAccrue();

        (
            uint256 lastUpdateAfter,
            uint256 rewardsAfter,
            ,
            uint256 wethFromGlpAfter
        ) = pxGlpRewards.globalState();

        assertEq(lastUpdateAfter, warpTimestamp);
        assertEq(rewardsAfter, expectedGlobalRewards);
        assertGt(wethFromGlpAfter, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        userAccrue TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test user rewards accrual
        @param  secondsElapsed    uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  multiplier        uint8   Multiplied with fixed token amounts for randomness
        @param  useETH            bool    Whether or not to use ETH as the source asset for minting GLP
        @param  testAccountIndex  uint8   Index of test account
     */
    function testUserAccrue(
        uint32 secondsElapsed,
        uint8 multiplier,
        bool useETH,
        uint8 testAccountIndex
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);
        vm.assume(testAccountIndex < 3);

        uint256 timestampBeforeMint = block.timestamp;

        _mintForTestAccounts(multiplier, useETH);

        address user = testAccounts[testAccountIndex];
        uint256 pxGlpBalance = pxGlp.balanceOf(user);
        (
            uint256 lastUpdateBefore,
            uint256 lastBalanceBefore,
            uint256 rewardsBefore
        ) = pxGlpRewards.userStates(user);
        uint256 warpTimestamp = block.timestamp + secondsElapsed;

        assertEq(lastUpdateBefore, timestampBeforeMint);

        // The recently minted balance amount should be what is stored in state
        assertEq(lastBalanceBefore, pxGlpBalance);

        // User should not accrue rewards until time has passed
        assertEq(rewardsBefore, 0);

        vm.warp(warpTimestamp);

        uint256 expectedUserRewards = _calculateUserRewards(user);

        pxGlpRewards.userAccrue(user);

        (
            uint256 lastUpdateAfter,
            uint256 lastBalanceAfter,
            uint256 rewardsAfter
        ) = pxGlpRewards.userStates(user);

        assertEq(lastUpdateAfter, warpTimestamp);
        assertEq(lastBalanceAfter, pxGlpBalance);
        assertEq(rewardsAfter, expectedUserRewards);
    }

    /*//////////////////////////////////////////////////////////////
                globalAccrue/userAccrue integration TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test minting pxGLP and reward point accrual for multiple users
        @param  secondsElapsed  uint32   Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  multiplier      uint8    Multiplied with fixed token amounts for randomness
        @param  useETH          bool     Whether or not to use ETH as the source asset for minting GLP
        @param  accrueGlobal    bool     Whether or not to update global reward accrual state
     */
    function testAccrue(
        uint32 secondsElapsed,
        uint8 multiplier,
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
        uint256 expectedGlobalRewards = _calculateGlobalRewards();

        if (accrueGlobal) {
            pxGlpRewards.globalAccrue();

            (
                uint256 globalLastUpdateAfterAccrue,
                uint256 globalRewardsAfterAccrue,
                ,

            ) = pxGlpRewards.globalState();

            assertEq(globalLastUpdateAfterAccrue, timestampBeforeAccrue);
            assertEq(globalRewardsAfterAccrue, expectedGlobalRewards);
        }

        // The sum of all user rewards accrued for comparison against the expected global amount
        uint256 totalRewards;

        // Iterate over test accounts and check that reward accrual amount is correct for each one
        for (uint256 i; i < testAccounts.length; ++i) {
            address testAccount = testAccounts[i];
            uint256 balanceBeforeAccrue = pxGlp.balanceOf(testAccount);
            uint256 expectedRewards = _calculateUserRewards(testAccount);

            assertGt(expectedRewards, 0);

            pxGlpRewards.userAccrue(testAccount);

            (
                uint256 lastUpdateAfterAccrue,
                uint256 lastBalanceAfterAccrue,
                uint256 rewardsAfterAccrue
            ) = pxGlpRewards.userStates(testAccount);

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
        @param  rounds               uint8    Number of rounds to fast forward time and accrue rewards
        @param  multiplier           uint8    Multiplied with fixed token amounts for randomness
        @param  useETH               bool     Whether or not to use ETH as the source asset for minting GLP
        @param  delayedAccountIndex  uint8    Test account index that will delay reward accrual until the end
     */
    function testAccrueAsync(
        uint8 rounds,
        uint8 multiplier,
        bool useETH,
        uint8 delayedAccountIndex
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
                    (, , uint256 rewardsBefore) = pxGlpRewards.userStates(
                        testAccounts[j]
                    );

                    pxGlpRewards.userAccrue(testAccounts[j]);

                    (, , uint256 rewardsAfter) = pxGlpRewards.userStates(
                        testAccounts[j]
                    );

                    nonDelayedTotalRewards += rewardsAfter - rewardsBefore;
                }
            }
        }

        // Calculate the rewards which should be accrued by the delayed account
        address delayedAccount = testAccounts[delayedAccountIndex];
        uint256 expectedDelayedRewards = _calculateUserRewards(delayedAccount);
        uint256 expectedGlobalRewards = _calculateGlobalRewards();

        // Accrue rewards and check that the actual amount matches the expected
        pxGlpRewards.userAccrue(delayedAccount);

        (, , uint256 rewardsAfterAccrue) = pxGlpRewards.userStates(
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
        @param  tokenAmount      uin80   Amount of pxGLP to mint the sender
        @param  secondsElapsed   uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  transferPercent  uint8   Percent for testing partial balance transfers
        @param  useTransfer      bool    Whether or not to use the transfer method
     */
    function testAccrueTransfer(
        uint80 tokenAmount,
        uint32 secondsElapsed,
        uint8 transferPercent,
        bool useTransfer
    ) external {
        vm.assume(tokenAmount > 0.001 ether);
        vm.assume(tokenAmount < 10000 ether);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(transferPercent != 0);
        vm.assume(transferPercent <= 100);

        address sender = testAccounts[0];
        address receiver = testAccounts[1];

        vm.deal(address(this), tokenAmount);

        pirexGlp.depositWithETH{value: tokenAmount}(1, sender);

        // Forward time in order to accrue rewards for sender
        vm.warp(block.timestamp + secondsElapsed);

        // Test sender reward accrual before transfer
        uint256 transferAmount = (pxGlp.balanceOf(sender) * transferPercent) /
            100;
        uint256 expectedSenderRewardsAfterTransfer = _calculateUserRewards(
            sender
        );

        // Test both of the ERC20 transfer methods for correctness of reward accrual
        if (useTransfer) {
            vm.prank(sender);

            pxGlp.transfer(receiver, transferAmount);
        } else {
            vm.prank(sender);

            // Need to increase allowance of the caller if using transferFrom
            pxGlp.approve(address(this), transferAmount);

            pxGlp.transferFrom(sender, receiver, transferAmount);
        }

        (, , uint256 senderRewardsAfterTransfer) = pxGlpRewards.userStates(
            sender
        );

        assertEq(
            expectedSenderRewardsAfterTransfer,
            senderRewardsAfterTransfer
        );

        // Forward time in order to accrue rewards for receiver
        vm.warp(block.timestamp + secondsElapsed);

        // Get expected sender and receiver reward accrual states
        uint256 expectedReceiverRewards = _calculateUserRewards(receiver);
        uint256 expectedSenderRewardsAfterTransferAndWarp = _calculateUserRewards(
                sender
            );

        // Accrue rewards for both sender and receiver
        pxGlpRewards.userAccrue(sender);
        pxGlpRewards.userAccrue(receiver);

        // Retrieve actual user reward accrual states
        (, , uint256 receiverRewards) = pxGlpRewards.userStates(receiver);
        (, , uint256 senderRewardsAfterTransferAndWarp) = pxGlpRewards
            .userStates(sender);

        assertEq(
            senderRewardsAfterTransferAndWarp,
            expectedSenderRewardsAfterTransferAndWarp
        );
        assertEq(expectedReceiverRewards, receiverRewards);
    }

    /*//////////////////////////////////////////////////////////////
                        claimWETHRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to receiver being the zero address
     */
    function testCannotClaimWETHRewardsReceiverZeroAddress() external {
        address invalidReceiver = address(0);

        vm.expectRevert(PxGlpRewards.ZeroAddress.selector);

        pxGlpRewards.claimWETHRewards(invalidReceiver);
    }

    /**
        @notice Test correctness of state and distribution amounts for WETH reward claims
        @param  secondsElapsed   uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  multiplier       uint8   Multiplied with fixed token amounts (uint256 to avoid overflow)
        @param  useETH           bool    Whether or not to use ETH as the source asset for minting GLP
     */
    function testClaimWETHRewards(
        uint32 secondsElapsed,
        uint8 multiplier,
        bool useETH
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        _mintForTestAccounts(multiplier, useETH);

        vm.warp(block.timestamp + secondsElapsed);

        // Ensure that user and global states are properly updated, and WETH is correctly distributed
        for (uint256 i; i < testAccounts.length; ++i) {
            // Pre-claim accrual to calculate expected values and perform post-claim comparisons
            pxGlpRewards.globalAccrue();

            (
                ,
                uint256 globalRewardsPreClaim,
                uint256 wethFromGmxPreClaim,
                uint256 wethFromGlpPreClaim
            ) = pxGlpRewards.globalState();
            uint256 totalGlobalWETHPreClaim = wethFromGmxPreClaim +
                wethFromGlpPreClaim;
            address testAccount = testAccounts[i];
            uint256 userRewardsPreClaim = _calculateUserRewards(testAccount);
            uint256 expectedUserWETHRewards = (userRewardsPreClaim *
                totalGlobalWETHPreClaim) / globalRewardsPreClaim;
            uint256 userWETHBalancePreClaim = WETH.balanceOf(testAccount);

            vm.prank(testAccount);
            vm.expectEmit(true, true, false, true, address(pxGlpRewards));

            emit ClaimWETHRewards(
                testAccount,
                testAccount,
                globalRewardsPreClaim,
                userRewardsPreClaim,
                (wethFromGmxPreClaim * userRewardsPreClaim) /
                    globalRewardsPreClaim,
                (wethFromGlpPreClaim * userRewardsPreClaim) /
                    globalRewardsPreClaim
            );

            pxGlpRewards.claimWETHRewards(testAccount);

            (
                ,
                uint256 globalRewardsPostClaim,
                uint256 wethFromGmxPostClaim,
                uint256 wethFromGlpPostClaim
            ) = pxGlpRewards.globalState();
            uint256 totalGlobalWETHPostClaim = wethFromGmxPostClaim +
                wethFromGlpPostClaim;
            (, , uint256 userRewardsPostClaim) = pxGlpRewards.userStates(
                testAccount
            );

            // Ensure global and user states are properly updated after claiming
            assertEq(
                WETH.balanceOf(testAccount) - userWETHBalancePreClaim,
                expectedUserWETHRewards
            );
            assertEq(
                globalRewardsPreClaim - userRewardsPreClaim,
                globalRewardsPostClaim
            );
            assertEq(
                totalGlobalWETHPreClaim - expectedUserWETHRewards,
                totalGlobalWETHPostClaim
            );
            assertEq(userRewardsPostClaim, 0);
        }
    }
}
