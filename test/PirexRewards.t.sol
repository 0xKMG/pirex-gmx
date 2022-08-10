// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexRewards} from "src/PirexRewards.sol";
import {Helper} from "./Helper.t.sol";

contract PirexRewardsTest is Helper {
    event SetProducer(address producer);
    event SetRewardRecipient(
        address indexed user,
        address indexed recipient,
        ERC20 indexed rewardToken
    );
    event UnsetRewardRecipient(address indexed user, ERC20 indexed rewardToken);
    event PushRewardToken(
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken
    );
    event PopRewardToken(ERC20 indexed producerToken);

    /**
        @notice Getter for a producerToken's global state
    */
    function _getGlobalState(ERC20 producerToken)
        internal
        view
        returns (
            uint256 lastUpdate,
            uint256 lastSupply,
            uint256 rewards
        )
    {
        PirexRewards.GlobalState memory globalState = pirexRewards
            .producerTokens(producerToken);

        return (
            globalState.lastUpdate,
            globalState.lastSupply,
            globalState.rewards
        );
    }

    /**
        @notice Calculate the global rewards
        @param  producerToken  ERC20    Producer token
        @return                uint256  Global rewards
    */
    function _calculateGlobalRewards(ERC20 producerToken)
        internal
        view
        returns (uint256)
    {
        (
            uint256 lastUpdate,
            uint256 lastSupply,
            uint256 rewards
        ) = _getGlobalState(producerToken);

        return rewards + (block.timestamp - lastUpdate) * lastSupply;
    }

    /**
        @notice Calculate a user's rewards
        @param  producerToken  ERC20    Producer token contract
        @param  user           address  User
        @return                uint256  User rewards
    */
    function _calculateUserRewards(ERC20 producerToken, address user)
        internal
        view
        returns (uint256)
    {
        (
            uint256 lastUpdate,
            uint256 lastBalance,
            uint256 rewards
        ) = pirexRewards.getUserState(producerToken, user);

        return rewards + lastBalance * (block.timestamp - lastUpdate);
    }

    /*//////////////////////////////////////////////////////////////
                        setProducer TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to caller not being owner
     */
    function testCannotSetProducerUnauthorized() external {
        address _producer = address(this);

        vm.prank(testAccounts[0]);
        vm.expectRevert("UNAUTHORIZED");

        pirexRewards.setProducer(_producer);
    }

    /**
        @notice Test tx reversion due to _producer being zero
     */
    function testCannotSetProducerZeroAddress() external {
        address invalidProducer = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setProducer(invalidProducer);
    }

    /**
        @notice Test setting producer
     */
    function testSetProducer() external {
        address producerBefore = address(pirexRewards.producer());
        address _producer = address(this);

        assertTrue(producerBefore != _producer);

        vm.expectEmit(false, false, false, true, address(pirexRewards));

        emit SetProducer(_producer);

        pirexRewards.setProducer(_producer);

        assertEq(_producer, address(pirexRewards.producer()));
    }

    /*//////////////////////////////////////////////////////////////
                        globalAccrue TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to producerToken being the zero address
     */
    function testCannotGlobalAccrueProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.globalAccrue(invalidProducerToken);
    }

    /**
        @notice Test global rewards accrual for minting
        @param  secondsElapsed  uint32  Seconds to forward timestamp (affects rewards accrued)
        @param  mintAmount      uint96  Amount of pxGLP to mint
     */
    function testGlobalAccrueMint(uint32 secondsElapsed, uint96 mintAmount)
        external
    {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(mintAmount != 0);
        vm.assume(mintAmount < 100000e18);

        ERC20 producerToken = pxGlp;
        uint256 timestampBeforeMint = block.timestamp;
        (
            uint256 lastUpdateBeforeMint,
            uint256 lastSupplyBeforeMint,
            uint256 rewardsBeforeMint
        ) = _getGlobalState(producerToken);

        assertEq(lastUpdateBeforeMint, 0);
        assertEq(lastSupplyBeforeMint, 0);
        assertEq(rewardsBeforeMint, 0);

        // Kick off global rewards accrual by minting first tokens
        _mintPxGlp(address(this), mintAmount);

        uint256 totalSupplyAfterMint = pxGlp.totalSupply();
        (
            uint256 lastUpdateAfterMint,
            uint256 lastSupplyAfterMint,
            uint256 rewardsAfterMint
        ) = _getGlobalState(producerToken);

        // Ensure that the update timestamp and supply are tracked
        assertEq(lastUpdateAfterMint, timestampBeforeMint);
        assertEq(lastSupplyAfterMint, totalSupplyAfterMint);

        // No rewards should have accrued since time has not elapsed
        assertEq(rewardsAfterMint, 0);

        // Amount of rewards that should have accrued after warping
        uint256 expectedRewards = lastSupplyAfterMint * secondsElapsed;

        // Forward timestamp to accrue rewards
        vm.warp(block.timestamp + secondsElapsed);

        // Post-warp timestamp should be what is stored in global accrual state
        uint256 expectedLastUpdate = block.timestamp;

        // Mint to call global reward accrual hook
        _mintPxGlp(address(this), mintAmount);

        (
            uint256 lastUpdate,
            uint256 lastSupply,
            uint256 rewards
        ) = _getGlobalState(producerToken);

        assertEq(expectedLastUpdate, lastUpdate);
        assertEq(pxGlp.totalSupply(), lastSupply);

        // Rewards should be what has been accrued based on the supply up to the mint
        assertEq(expectedRewards, rewards);
    }

    /**
        @notice Test global rewards accrual for burning
        @param  secondsElapsed  uint32  Seconds to forward timestamp (affects rewards accrued)
        @param  mintAmount      uint96  Amount of pxGLP to mint
        @param  burnPercent     uint8   Percent of pxGLP balance to burn
     */
    function testGlobalAccrueBurn(
        uint32 secondsElapsed,
        uint96 mintAmount,
        uint8 burnPercent
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(mintAmount > 1e18);
        vm.assume(mintAmount < 100000e18);
        vm.assume(burnPercent != 0);
        vm.assume(burnPercent <= 100);

        ERC20 producerToken = pxGlp;
        address user = address(this);

        _mintPxGlp(user, mintAmount);

        // Forward time in order to accrue rewards globally
        vm.warp(block.timestamp + secondsElapsed);

        uint256 preBurnSupply = pxGlp.totalSupply();
        uint256 burnAmount = (pxGlp.balanceOf(user) * burnPercent) / 100;

        // Global rewards accrued up to the token burn
        uint256 expectedRewards = _calculateGlobalRewards(producerToken);

        _burnPxGlp(user, burnAmount);

        (, , uint256 rewards) = _getGlobalState(producerToken);
        uint256 postBurnSupply = pxGlp.totalSupply();

        // Verify conditions for "less reward accrual" post-burn
        assertTrue(postBurnSupply < preBurnSupply);

        // User should have accrued rewards based on their balance up to the burn
        assertEq(expectedRewards, rewards);

        // Forward time in order to accrue rewards globally
        vm.warp(block.timestamp + secondsElapsed);

        // Global rewards accrued after the token burn
        uint256 expectedRewardsAfterBurn = _calculateGlobalRewards(
            producerToken
        );

        // Rewards accrued had supply not been reduced by burning
        uint256 noBurnRewards = rewards + preBurnSupply * secondsElapsed;

        // Delta of expected/actual rewards accrued and no-burn rewards accrued
        uint256 expectedAndNoBurnRewardDelta = (preBurnSupply -
            postBurnSupply) * secondsElapsed;

        pirexRewards.globalAccrue(producerToken);

        (, , uint256 rewardsAfterBurn) = _getGlobalState(producerToken);

        assertEq(expectedRewardsAfterBurn, rewardsAfterBurn);
        assertEq(
            noBurnRewards - expectedAndNoBurnRewardDelta,
            expectedRewardsAfterBurn
        );
    }

    /*//////////////////////////////////////////////////////////////
                        userAccrue TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to producerToken being the zero address
     */
    function testCannotUserAccrueProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        address user = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.userAccrue(invalidProducerToken, user);
    }

    /**
        @notice Test tx reversion due to user being the zero address
     */
    function testCannotUserAccrueUserZeroAddress() external {
        ERC20 producerToken = pxGlp;
        address invalidUser = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.userAccrue(producerToken, invalidUser);
    }

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
        ) = pirexRewards.getUserState(pxGlp, user);
        uint256 warpTimestamp = block.timestamp + secondsElapsed;

        assertEq(lastUpdateBefore, timestampBeforeMint);

        // The recently minted balance amount should be what is stored in state
        assertEq(lastBalanceBefore, pxGlpBalance);

        // User should not accrue rewards until time has passed
        assertEq(rewardsBefore, 0);

        vm.warp(warpTimestamp);

        uint256 expectedUserRewards = _calculateUserRewards(pxGlp, user);

        pirexRewards.userAccrue(pxGlp, user);

        (
            uint256 lastUpdateAfter,
            uint256 lastBalanceAfter,
            uint256 rewardsAfter
        ) = pirexRewards.getUserState(pxGlp, user);

        assertEq(lastUpdateAfter, warpTimestamp);
        assertEq(lastBalanceAfter, pxGlpBalance);
        assertEq(rewardsAfter, expectedUserRewards);
        assertTrue(rewardsAfter != 0);
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
        uint256 expectedGlobalRewards = _calculateGlobalRewards(pxGlp);

        if (accrueGlobal) {
            uint256 totalSupplyBeforeAccrue = pxGlp.totalSupply();

            pirexRewards.globalAccrue(pxGlp);

            (
                uint256 lastUpdate,
                uint256 lastSupply,
                uint256 rewards
            ) = _getGlobalState(pxGlp);

            assertEq(lastUpdate, timestampBeforeAccrue);
            assertEq(lastSupply, totalSupplyBeforeAccrue);
            assertEq(rewards, expectedGlobalRewards);
        }

        // The sum of all user rewards accrued for comparison against the expected global amount
        uint256 totalRewards;

        // Iterate over test accounts and check that reward accrual amount is correct for each one
        for (uint256 i; i < testAccounts.length; ++i) {
            address testAccount = testAccounts[i];
            uint256 balanceBeforeAccrue = pxGlp.balanceOf(testAccount);
            uint256 expectedRewards = _calculateUserRewards(pxGlp, testAccount);

            assertGt(expectedRewards, 0);

            pirexRewards.userAccrue(pxGlp, testAccount);

            (
                uint256 lastUpdate,
                uint256 lastBalance,
                uint256 rewards
            ) = pirexRewards.getUserState(pxGlp, testAccount);

            // Total rewards accrued by all users should add up to the global rewards
            totalRewards += rewards;

            assertEq(timestampBeforeAccrue, lastUpdate);
            assertEq(balanceBeforeAccrue, lastBalance);
            assertEq(expectedRewards, rewards);
        }

        assertEq(expectedGlobalRewards, totalRewards);
    }

    /**
        @notice Test minting pxGLP and reward point accrual for multiple users with one who accrues asynchronously
        @param  secondsElapsed       uint32   Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  rounds               uint8    Number of rounds to fast forward time and accrue rewards
        @param  multiplier           uint8    Multiplied with fixed token amounts for randomness
        @param  useETH               bool     Whether or not to use ETH as the source asset for minting GLP
        @param  delayedAccountIndex  uint8    Test account index that will delay reward accrual until the end
     */
    function testAccrueAsync(
        uint32 secondsElapsed,
        uint8 rounds,
        uint8 multiplier,
        bool useETH,
        uint8 delayedAccountIndex
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(rounds != 0);
        vm.assume(rounds < 10);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);
        vm.assume(delayedAccountIndex < 3);

        _mintForTestAccounts(multiplier, useETH);

        // Sum up the rewards accrued - after all rounds - for accounts where accrual is not delayed
        uint256 nonDelayedTotalRewards;

        uint256 tLen = testAccounts.length;

        // Iterate over a number of rounds and accrue for non-delayed accounts
        for (uint256 i; i < rounds; ++i) {
            uint256 timestampBeforeAccrue = block.timestamp;

            // Forward timestamp by X seconds which will determine the total amount of rewards accrued
            vm.warp(timestampBeforeAccrue + secondsElapsed);

            for (uint256 j; j < tLen; ++j) {
                if (j != delayedAccountIndex) {
                    (, , uint256 rewardsBefore) = pirexRewards.getUserState(
                        pxGlp,
                        testAccounts[j]
                    );

                    pirexRewards.userAccrue(pxGlp, testAccounts[j]);

                    (, , uint256 rewardsAfter) = pirexRewards.getUserState(
                        pxGlp,
                        testAccounts[j]
                    );

                    nonDelayedTotalRewards += rewardsAfter - rewardsBefore;
                }
            }
        }

        // Calculate the rewards which should be accrued by the delayed account
        address delayedAccount = testAccounts[delayedAccountIndex];
        uint256 expectedDelayedRewards = _calculateUserRewards(
            pxGlp,
            delayedAccount
        );
        uint256 expectedGlobalRewards = _calculateGlobalRewards(pxGlp);

        // Accrue rewards and check that the actual amount matches the expected
        pirexRewards.userAccrue(pxGlp, delayedAccount);

        (, , uint256 rewardsAfterAccrue) = pirexRewards.getUserState(
            pxGlp,
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
            pxGlp,
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

        (, , uint256 senderRewardsAfterTransfer) = pirexRewards.getUserState(
            pxGlp,
            sender
        );

        assertEq(
            expectedSenderRewardsAfterTransfer,
            senderRewardsAfterTransfer
        );

        // Forward time in order to accrue rewards for receiver
        vm.warp(block.timestamp + secondsElapsed);

        // Get expected sender and receiver reward accrual states
        uint256 expectedReceiverRewards = _calculateUserRewards(
            pxGlp,
            receiver
        );
        uint256 expectedSenderRewardsAfterTransferAndWarp = _calculateUserRewards(
                pxGlp,
                sender
            );

        // Accrue rewards for both sender and receiver
        pirexRewards.userAccrue(pxGlp, sender);
        pirexRewards.userAccrue(pxGlp, receiver);

        // Retrieve actual user reward accrual states
        (, , uint256 receiverRewards) = pirexRewards.getUserState(
            pxGlp,
            receiver
        );
        (, , uint256 senderRewardsAfterTransferAndWarp) = pirexRewards
            .getUserState(pxGlp, sender);

        assertEq(
            senderRewardsAfterTransferAndWarp,
            expectedSenderRewardsAfterTransferAndWarp
        );
        assertEq(expectedReceiverRewards, receiverRewards);
    }

    /**
        @notice Test correctness of reward accruals in the case of pxGLP burns
        @param  tokenAmount      uin80   Amount of pxGLP to mint the user
        @param  secondsElapsed   uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  burnPercent      uint8   Percent for testing partial balance burns
     */
    function testAccrueBurn(
        uint80 tokenAmount,
        uint32 secondsElapsed,
        uint8 burnPercent
    ) external {
        vm.assume(tokenAmount > 0.001 ether);
        vm.assume(tokenAmount < 10000 ether);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(burnPercent != 0);
        vm.assume(burnPercent <= 100);

        address user = address(this);

        vm.deal(user, tokenAmount);

        pirexGlp.depositWithETH{value: tokenAmount}(1, user);

        // Forward time in order to accrue rewards for user
        vm.warp(block.timestamp + secondsElapsed);

        uint256 preBurnBalance = pxGlp.balanceOf(user);
        uint256 burnAmount = (preBurnBalance * burnPercent) / 100;
        uint256 expectedRewardsAfterBurn = _calculateUserRewards(pxGlp, user);

        vm.prank(address(pirexGlp));

        pxGlp.burn(user, burnAmount);

        (, , uint256 rewardsAfterBurn) = pirexRewards.getUserState(pxGlp, user);
        uint256 postBurnBalance = pxGlp.balanceOf(user);

        // Verify conditions for "less reward accrual" post-burn
        assertTrue(postBurnBalance < preBurnBalance);

        // User should have accrued rewards based on their balance up to the burn
        assertEq(expectedRewardsAfterBurn, rewardsAfterBurn);

        // Forward timestamp to check that user is accruing less rewards
        vm.warp(block.timestamp + secondsElapsed);

        uint256 expectedRewards = _calculateUserRewards(pxGlp, user);

        // Rewards accrued if user were to not burn tokens
        uint256 noBurnRewards = rewardsAfterBurn +
            preBurnBalance *
            secondsElapsed;

        // Delta of expected/actual rewards accrued and no-burn rewards accrued
        uint256 expectedAndNoBurnRewardDelta = (preBurnBalance -
            postBurnBalance) * secondsElapsed;

        pirexRewards.userAccrue(pxGlp, user);

        (, , uint256 rewards) = pirexRewards.getUserState(pxGlp, user);

        assertEq(expectedRewards, rewards);
        assertEq(noBurnRewards - expectedAndNoBurnRewardDelta, rewards);
    }

    /*//////////////////////////////////////////////////////////////
                            harvest TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test harvesting WETH rewards produced by pxGLP
        @param  secondsElapsed  uint32  Seconds to forward timestamp
        @param  ethAmount       uint80  ETH amount used to mint pxGLP
     */
    function testHarvest(uint32 secondsElapsed, uint80 ethAmount) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(ethAmount > 0.001 ether);
        vm.assume(ethAmount < 10000 ether);

        address user = address(this);

        vm.deal(user, ethAmount);

        pirexGlp.depositWithETH{value: ethAmount}(1, user);

        vm.warp(block.timestamp + secondsElapsed);

        uint256 wethBalanceBeforeHarvest = WETH.balanceOf(
            address(pirexRewards)
        );
        uint256 expectedGlobalLastUpdate = block.timestamp;
        uint256 expectedGlobalLastSupply = pxGlp.totalSupply();
        uint256 expectedGlobalRewards = _calculateGlobalRewards(pxGlp);
        (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = pirexRewards.harvest();
        (
            uint256 lastUpdate,
            uint256 lastSupply,
            uint256 rewards
        ) = _getGlobalState(pxGlp);

        assertEq(expectedGlobalLastUpdate, lastUpdate);
        assertEq(expectedGlobalLastSupply, lastSupply);
        assertEq(expectedGlobalRewards, rewards);

        uint256 totalRewards;
        uint256 pLen = producerTokens.length;

        for (uint256 i; i < pLen; ++i) {
            ERC20 p = producerTokens[i];
            uint256 rewardAmount = rewardAmounts[i];

            totalRewards += rewardAmount;

            assertEq(
                rewardAmount,
                pirexRewards.getRewardState(p, rewardTokens[i])
            );
        }

        // Check that the correct amount of WETH was transferred to the silo
        assertEq(
            WETH.balanceOf(address(pirexRewards)) - wethBalanceBeforeHarvest,
            totalRewards
        );
    }

    /*//////////////////////////////////////////////////////////////
                        setRewardRecipient TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: recipient is the zero address
     */
    function testCannotSetRewardRecipientRecipientZeroAddress() external {
        address invalidRecipient = address(0);
        ERC20 rewardToken = WETH;

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(invalidRecipient, rewardToken);
    }

    /**
        @notice Test tx reversion: rewardToken is the zero address
     */
    function testCannotSetRewardRecipientRewardTokenZeroAddress() external {
        address recipient = address(this);
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(recipient, invalidRewardToken);
    }

    /**
        @notice Test setting a reward recipient
     */
    function testSetRewardRecipient() external {
        address recipientBeforeSetting = pirexRewards.rewardRecipients(
            address(this),
            WETH
        );
        address recipient = address(this);
        ERC20 rewardToken = WETH;

        assertTrue(recipientBeforeSetting != recipient);

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit SetRewardRecipient(address(this), recipient, rewardToken);

        pirexRewards.setRewardRecipient(recipient, rewardToken);

        assertEq(recipient, pirexRewards.rewardRecipients(address(this), WETH));
    }

    /*//////////////////////////////////////////////////////////////
                        unsetRewardRecipient TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: rewardToken is the zero address
     */
    function testCannotUnsetRewardRecipientRewardTokenZeroAddress() external {
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipient(invalidRewardToken);
    }

    /**
        @notice Test unsetting a reward recipient
     */
    function testUnsetRewardRecipient() external {
        // Set reward recipient in order to unset
        address recipient = address(this);
        ERC20 rewardToken = WETH;

        pirexRewards.setRewardRecipient(recipient, rewardToken);

        assertEq(recipient, pirexRewards.rewardRecipients(address(this), WETH));

        vm.expectEmit(true, true, false, true, address(pirexRewards));

        emit UnsetRewardRecipient(address(this), rewardToken);

        pirexRewards.unsetRewardRecipient(rewardToken);

        assertEq(
            address(0),
            pirexRewards.rewardRecipients(address(this), WETH)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        pushRewardToken TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotPushRewardTokenNotAuthorized() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;

        vm.prank(testAccounts[0]);
        vm.expectRevert("UNAUTHORIZED");

        pirexRewards.pushRewardToken(producerToken, rewardToken);
    }

    /**
        @notice Test tx reversion: producerToken is the zero address
     */
    function testCannotPushRewardTokenProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.pushRewardToken(invalidProducerToken, rewardToken);
    }

    /**
        @notice Test tx reversion: rewardToken is the zero address
     */
    function testCannotPushRewardTokenRewardTokenZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.pushRewardToken(producerToken, invalidRewardToken);
    }

    /**
        @notice Test pushing a reward token
     */
    function testPushRewardToken() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;
        ERC20[] memory rewardTokensBeforePush = pirexRewards.getRewardTokens(
            producerToken
        );

        assertEq(0, rewardTokensBeforePush.length);

        vm.expectEmit(true, true, false, true, address(pirexRewards));

        emit PushRewardToken(producerToken, rewardToken);

        pirexRewards.pushRewardToken(producerToken, rewardToken);

        ERC20[] memory rewardTokensAfterPush = pirexRewards.getRewardTokens(
            producerToken
        );

        assertEq(1, rewardTokensAfterPush.length);
        assertEq(address(rewardToken), address(rewardTokensAfterPush[0]));
    }

    /*//////////////////////////////////////////////////////////////
                        popRewardToken TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotPopRewardTokenNotAuthorized() external {
        ERC20 producerToken = pxGlp;

        vm.prank(testAccounts[0]);
        vm.expectRevert("UNAUTHORIZED");

        pirexRewards.popRewardToken(producerToken);
    }

    /**
        @notice Test tx reversion: producerToken is the zero address
     */
    function testCannotPopRewardTokenProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.popRewardToken(invalidProducerToken);
    }

    /**
        @notice Test popping a reward token
     */
    function testPopRewardToken() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;

        // Add rewardToken element to array to test pop
        pirexRewards.pushRewardToken(producerToken, rewardToken);

        ERC20[] memory rewardTokensBeforePop = pirexRewards.getRewardTokens(
            producerToken
        );

        assertEq(1, rewardTokensBeforePop.length);
        assertEq(address(rewardToken), address(rewardTokensBeforePop[0]));

        vm.expectEmit(true, false, false, true, address(pirexRewards));

        emit PopRewardToken(producerToken);

        pirexRewards.popRewardToken(producerToken);

        ERC20[] memory rewardTokensAfterPop = pirexRewards.getRewardTokens(
            producerToken
        );

        assertEq(0, rewardTokensAfterPop.length);
    }
}
