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
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken,
        address recipient
    );
    event UnsetRewardRecipient(
        address indexed user,
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken
    );
    event AddRewardToken(
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken
    );
    event RemoveRewardToken(ERC20 indexed producerToken, uint256 removalIndex);
    event SetRewardRecipientPrivileged(
        address indexed lpContract,
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken,
        address recipient
    );
    event UnsetRewardRecipientPrivileged(
        address indexed lpContract,
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken
    );
    event Harvest(
        ERC20[] producerTokens,
        ERC20[] rewardTokens,
        uint256[] rewardAmounts
    );

    /**
        @notice Getter for a producer token's global state
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
        @notice Calculate the global rewards accrued since the last update
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
        @notice Calculate a user's rewards since the last update
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
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotSetProducerNotAuthorized() external {
        address _producer = address(this);

        vm.prank(testAccounts[0]);
        vm.expectRevert("UNAUTHORIZED");

        pirexRewards.setProducer(_producer);
    }

    /**
        @notice Test tx reversion: _producer is the zero address
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
        @notice Test tx reversion: producerToken is the zero address
     */
    function testCannotGlobalAccrueProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.globalAccrue(invalidProducerToken);
    }

    /**
        @notice Test global rewards accrual for minting
        @param  secondsElapsed  uint32  Seconds to forward timestamp (affects rewards accrued)
        @param  mintAmount      uint96  Amount of pxGMX or pxGLP to mint
        @param  useGmx          bool    Whether to use pxGMX
     */
    function testGlobalAccrueMint(
        uint32 secondsElapsed,
        uint96 mintAmount,
        bool useGmx
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(mintAmount != 0);
        vm.assume(mintAmount < 100000e18);

        ERC20 producerToken = useGmx
            ? ERC20(address(pxGmx))
            : ERC20(address(pxGlp));
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
        _mintPx(address(this), mintAmount, useGmx);

        uint256 totalSupplyAfterMint = producerToken.totalSupply();
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
        _mintPx(address(this), mintAmount, useGmx);

        (
            uint256 lastUpdate,
            uint256 lastSupply,
            uint256 rewards
        ) = _getGlobalState(producerToken);

        assertEq(expectedLastUpdate, lastUpdate);
        assertEq(producerToken.totalSupply(), lastSupply);

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

        _mintPx(user, mintAmount, false);

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
        @notice Test tx reversion: producerToken is the zero address
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
        @param  useGmx            bool    Whether to use pxGMX
     */
    function testUserAccrue(
        uint32 secondsElapsed,
        uint8 multiplier,
        bool useETH,
        uint8 testAccountIndex,
        bool useGmx
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);
        vm.assume(testAccountIndex < 3);

        ERC20 producerToken = useGmx
            ? ERC20(address(pxGmx))
            : ERC20(address(pxGlp));

        _depositForTestAccounts(useGmx, multiplier, useETH);

        address user = testAccounts[testAccountIndex];
        uint256 pxBalance = producerToken.balanceOf(user);
        (
            uint256 lastUpdateBefore,
            uint256 lastBalanceBefore,
            uint256 rewardsBefore
        ) = pirexRewards.getUserState(producerToken, user);
        uint256 warpTimestamp = block.timestamp + secondsElapsed;

        // GMX minting warps timestamp (timelock) so we will test for a non-zero value
        assertTrue(lastUpdateBefore != 0);

        // The recently minted balance amount should be what is stored in state
        assertEq(lastBalanceBefore, pxBalance);

        // User should not accrue rewards until time has passed
        assertEq(rewardsBefore, 0);

        vm.warp(warpTimestamp);

        uint256 expectedUserRewards = _calculateUserRewards(
            producerToken,
            user
        );

        pirexRewards.userAccrue(producerToken, user);

        (
            uint256 lastUpdateAfter,
            uint256 lastBalanceAfter,
            uint256 rewardsAfter
        ) = pirexRewards.getUserState(producerToken, user);

        assertEq(lastUpdateAfter, warpTimestamp);
        assertEq(lastBalanceAfter, pxBalance);
        assertEq(rewardsAfter, expectedUserRewards);
        assertTrue(rewardsAfter != 0);
    }

    /*//////////////////////////////////////////////////////////////
                globalAccrue/userAccrue integration TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test minting px token and reward point accrual for multiple users
        @param  secondsElapsed  uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  useETH          bool    Whether or not to use ETH as the source asset for minting GLP
        @param  accrueGlobal    bool    Whether or not to update global reward accrual state
        @param  useGmx          bool    Whether to use pxGMX
     */
    function testAccrue(
        uint32 secondsElapsed,
        uint8 multiplier,
        bool useETH,
        bool accrueGlobal,
        bool useGmx
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        ERC20 producerToken = useGmx
            ? ERC20(address(pxGmx))
            : ERC20(address(pxGlp));

        _depositForTestAccounts(useGmx, multiplier, useETH);

        // Forward timestamp by X seconds which will determine the total amount of rewards accrued
        vm.warp(block.timestamp + secondsElapsed);

        uint256 timestampBeforeAccrue = block.timestamp;
        uint256 expectedGlobalRewards = _calculateGlobalRewards(producerToken);

        if (accrueGlobal) {
            uint256 totalSupplyBeforeAccrue = producerToken.totalSupply();

            pirexRewards.globalAccrue(producerToken);

            (
                uint256 lastUpdate,
                uint256 lastSupply,
                uint256 rewards
            ) = _getGlobalState(producerToken);

            assertEq(lastUpdate, timestampBeforeAccrue);
            assertEq(lastSupply, totalSupplyBeforeAccrue);
            assertEq(rewards, expectedGlobalRewards);
        }

        // The sum of all user rewards accrued for comparison against the expected global amount
        uint256 totalRewards;

        // Iterate over test accounts and check that reward accrual amount is correct for each one
        for (uint256 i; i < testAccounts.length; ++i) {
            address testAccount = testAccounts[i];
            uint256 balanceBeforeAccrue = producerToken.balanceOf(testAccount);
            uint256 expectedRewards = _calculateUserRewards(
                producerToken,
                testAccount
            );

            assertGt(expectedRewards, 0);

            pirexRewards.userAccrue(producerToken, testAccount);

            (
                uint256 lastUpdate,
                uint256 lastBalance,
                uint256 rewards
            ) = pirexRewards.getUserState(producerToken, testAccount);

            // Total rewards accrued by all users should add up to the global rewards
            totalRewards += rewards;

            assertEq(timestampBeforeAccrue, lastUpdate);
            assertEq(balanceBeforeAccrue, lastBalance);
            assertEq(expectedRewards, rewards);
        }

        assertEq(expectedGlobalRewards, totalRewards);
    }

    /**
        @notice Test minting px tokens and reward point accrual for multiple users with one who accrues asynchronously
        @param  secondsElapsed       uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  rounds               uint8   Number of rounds to fast forward time and accrue rewards
        @param  multiplier           uint8   Multiplied with fixed token amounts for randomness
        @param  useETH               bool    Whether or not to use ETH as the source asset for minting GLP
        @param  delayedAccountIndex  uint8   Test account index that will delay reward accrual until the end
        @param  useGmx               bool    Whether to use pxGMX
     */
    function testAccrueAsync(
        uint32 secondsElapsed,
        uint8 rounds,
        uint8 multiplier,
        bool useETH,
        uint8 delayedAccountIndex,
        bool useGmx
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(rounds != 0);
        vm.assume(rounds < 10);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);
        vm.assume(delayedAccountIndex < 3);

        ERC20 producerToken = useGmx
            ? ERC20(address(pxGmx))
            : ERC20(address(pxGlp));

        _depositForTestAccounts(useGmx, multiplier, useETH);

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
                        producerToken,
                        testAccounts[j]
                    );

                    pirexRewards.userAccrue(producerToken, testAccounts[j]);

                    (, , uint256 rewardsAfter) = pirexRewards.getUserState(
                        producerToken,
                        testAccounts[j]
                    );

                    nonDelayedTotalRewards += rewardsAfter - rewardsBefore;
                }
            }
        }

        // Calculate the rewards which should be accrued by the delayed account
        address delayedAccount = testAccounts[delayedAccountIndex];
        uint256 expectedDelayedRewards = _calculateUserRewards(
            producerToken,
            delayedAccount
        );
        uint256 expectedGlobalRewards = _calculateGlobalRewards(producerToken);

        // Accrue rewards and check that the actual amount matches the expected
        pirexRewards.userAccrue(producerToken, delayedAccount);

        (, , uint256 rewardsAfterAccrue) = pirexRewards.getUserState(
            producerToken,
            delayedAccount
        );

        assertEq(rewardsAfterAccrue, expectedDelayedRewards);
        assertEq(
            nonDelayedTotalRewards + rewardsAfterAccrue,
            expectedGlobalRewards
        );
    }

    /**
        @notice Test correctness of reward accruals in the case of px token transfers
        @param  tokenAmount      uin80   Amount of tokens to mint the sender
        @param  secondsElapsed   uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  transferPercent  uint8   Percent for testing partial balance transfers
        @param  useTransfer      bool    Whether or not to use the transfer method
        @param  useGmx           bool    Whether to use pxGMX
     */
    function testAccrueTransfer(
        uint80 tokenAmount,
        uint32 secondsElapsed,
        uint8 transferPercent,
        bool useTransfer,
        bool useGmx
    ) external {
        vm.assume(tokenAmount > 1e10);
        vm.assume(tokenAmount < 10000e18);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(transferPercent != 0);
        vm.assume(transferPercent <= 100);

        ERC20 producerToken = useGmx
            ? ERC20(address(pxGmx))
            : ERC20(address(pxGlp));
        address sender = testAccounts[0];
        address receiver = testAccounts[1];

        if (useGmx) {
            _mintGmx(tokenAmount);
            GMX.approve(address(pirexGmxGlp), tokenAmount);
            pirexGmxGlp.depositGmx(tokenAmount, sender);
        } else {
            vm.deal(address(this), tokenAmount);

            pirexGmxGlp.depositGlpWithETH{value: tokenAmount}(1, sender);
        }

        // Forward time in order to accrue rewards for sender
        vm.warp(block.timestamp + secondsElapsed);

        // Test sender reward accrual before transfer
        uint256 transferAmount = (producerToken.balanceOf(sender) *
            transferPercent) / 100;
        uint256 expectedSenderRewardsAfterTransfer = _calculateUserRewards(
            producerToken,
            sender
        );

        // Test both of the ERC20 transfer methods for correctness of reward accrual
        if (useTransfer) {
            vm.prank(sender);

            producerToken.transfer(receiver, transferAmount);
        } else {
            vm.prank(sender);

            // Need to increase allowance of the caller if using transferFrom
            producerToken.approve(address(this), transferAmount);

            producerToken.transferFrom(sender, receiver, transferAmount);
        }

        (, , uint256 senderRewardsAfterTransfer) = pirexRewards.getUserState(
            producerToken,
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
            producerToken,
            receiver
        );
        uint256 expectedSenderRewardsAfterTransferAndWarp = _calculateUserRewards(
                producerToken,
                sender
            );

        // Accrue rewards for both sender and receiver
        pirexRewards.userAccrue(producerToken, sender);
        pirexRewards.userAccrue(producerToken, receiver);

        // Retrieve actual user reward accrual states
        (, , uint256 receiverRewards) = pirexRewards.getUserState(
            producerToken,
            receiver
        );
        (, , uint256 senderRewardsAfterTransferAndWarp) = pirexRewards
            .getUserState(producerToken, sender);

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

        pirexGmxGlp.depositGlpWithETH{value: tokenAmount}(1, user);

        // Forward time in order to accrue rewards for user
        vm.warp(block.timestamp + secondsElapsed);

        uint256 preBurnBalance = pxGlp.balanceOf(user);
        uint256 burnAmount = (preBurnBalance * burnPercent) / 100;
        uint256 expectedRewardsAfterBurn = _calculateUserRewards(pxGlp, user);

        vm.prank(address(pirexGmxGlp));

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

        pirexGmxGlp.depositGlpWithETH{value: ethAmount}(1, user);

        vm.warp(block.timestamp + secondsElapsed);

        uint256 wethBalanceBeforeHarvest = WETH.balanceOf(
            address(pirexRewards)
        );
        uint256 expectedGlobalLastUpdate = block.timestamp;
        uint256 expectedGlobalLastSupply = pxGlp.totalSupply();
        uint256 expectedGlobalRewards = _calculateGlobalRewards(pxGlp);
        ERC20[] memory expectedProducerTokens = new ERC20[](2);
        ERC20[] memory expectedRewardTokens = new ERC20[](2);
        uint256[] memory expectedRewardAmounts = new uint256[](2);

        expectedProducerTokens[0] = pxGmx;
        expectedProducerTokens[1] = pxGlp;
        expectedRewardTokens[0] = WETH;
        expectedRewardTokens[1] = WETH;
        expectedRewardAmounts[0] = pirexGmxGlp.calculateRewards(true, true);
        expectedRewardAmounts[1] = pirexGmxGlp.calculateRewards(true, false);

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit Harvest(
            expectedProducerTokens,
            expectedRewardTokens,
            expectedRewardAmounts
        );

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
        @notice Test tx reversion: producerToken is the zero address
     */
    function testCannotSetRewardRecipientProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = WETH;
        address recipient = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(
            invalidProducerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: rewardToken is the zero address
     */
    function testCannotSetRewardRecipientRewardTokenZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));
        address recipient = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(
            producerToken,
            invalidRewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: recipient is the zero address
     */
    function testCannotSetRewardRecipientRecipientZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;
        address invalidRecipient = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(
            producerToken,
            rewardToken,
            invalidRecipient
        );
    }

    /**
        @notice Test setting a reward recipient
     */
    function testSetRewardRecipient() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;
        address recipient = address(this);

        assertTrue(
            recipient !=
                pirexRewards.getRewardRecipient(
                    address(this),
                    producerToken,
                    rewardToken
                )
        );

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit SetRewardRecipient(
            address(this),
            producerToken,
            rewardToken,
            recipient
        );

        pirexRewards.setRewardRecipient(producerToken, rewardToken, recipient);

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(
                address(this),
                producerToken,
                rewardToken
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        unsetRewardRecipient TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is the zero address
     */
    function testCannotUnsetRewardRecipientProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = WETH;

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipient(invalidProducerToken, rewardToken);
    }

    /**
        @notice Test tx reversion: rewardToken is the zero address
     */
    function testCannotUnsetRewardRecipientRewardTokenZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipient(producerToken, invalidRewardToken);
    }

    /**
        @notice Test unsetting a reward recipient
     */
    function testUnsetRewardRecipient() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;
        address recipient = address(this);

        // Set reward recipient in order to unset
        pirexRewards.setRewardRecipient(pxGlp, rewardToken, recipient);

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(
                address(this),
                producerToken,
                rewardToken
            )
        );

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit UnsetRewardRecipient(address(this), producerToken, rewardToken);

        pirexRewards.unsetRewardRecipient(producerToken, rewardToken);

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                address(this),
                producerToken,
                rewardToken
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        addRewardToken TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotAddRewardTokenNotAuthorized() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;

        vm.prank(testAccounts[0]);
        vm.expectRevert("UNAUTHORIZED");

        pirexRewards.addRewardToken(producerToken, rewardToken);
    }

    /**
        @notice Test tx reversion: producerToken is the zero address
     */
    function testCannotAddRewardTokenProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.addRewardToken(invalidProducerToken, rewardToken);
    }

    /**
        @notice Test tx reversion: rewardToken is the zero address
     */
    function testCannotAddRewardTokenRewardTokenZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.addRewardToken(producerToken, invalidRewardToken);
    }

    /**
        @notice Test adding a reward token
     */
    function testAddRewardToken() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;
        ERC20[] memory rewardTokensBeforePush = pirexRewards.getRewardTokens(
            producerToken
        );

        assertEq(0, rewardTokensBeforePush.length);

        vm.expectEmit(true, true, false, true, address(pirexRewards));

        emit AddRewardToken(producerToken, rewardToken);

        pirexRewards.addRewardToken(producerToken, rewardToken);

        ERC20[] memory rewardTokensAfterPush = pirexRewards.getRewardTokens(
            producerToken
        );

        assertEq(1, rewardTokensAfterPush.length);
        assertEq(address(rewardToken), address(rewardTokensAfterPush[0]));
    }

    /*//////////////////////////////////////////////////////////////
                        removeRewardToken TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotRemoveRewardTokenNotAuthorized() external {
        ERC20 producerToken = pxGlp;
        uint256 removalIndex = 0;

        vm.prank(testAccounts[0]);
        vm.expectRevert("UNAUTHORIZED");

        pirexRewards.removeRewardToken(producerToken, removalIndex);
    }

    /**
        @notice Test tx reversion: producerToken is the zero address
     */
    function testCannotRemoveRewardTokenProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        uint256 removalIndex = 0;

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.removeRewardToken(invalidProducerToken, removalIndex);
    }

    /**
        @notice Test removing a reward token at a random index
        @param  removalIndex  uint8  Index of the element to be removed
     */
    function testRemoveRewardToken(uint8 removalIndex) external {
        vm.assume(removalIndex < 2);

        ERC20 producerToken = pxGlp;
        address rewardToken1 = address(WETH);
        address rewardToken2 = address(WBTC);

        // Add rewardTokens to array to test proper removal
        pirexRewards.addRewardToken(producerToken, ERC20(rewardToken1));
        pirexRewards.addRewardToken(producerToken, ERC20(rewardToken2));

        ERC20[] memory rewardTokensBeforeRemoval = pirexRewards.getRewardTokens(
            producerToken
        );

        assertEq(2, rewardTokensBeforeRemoval.length);
        assertEq(rewardToken1, address(rewardTokensBeforeRemoval[0]));
        assertEq(rewardToken2, address(rewardTokensBeforeRemoval[1]));

        vm.expectEmit(true, false, false, true, address(pirexRewards));

        emit RemoveRewardToken(producerToken, removalIndex);

        pirexRewards.removeRewardToken(producerToken, removalIndex);

        ERC20[] memory rewardTokensAfterRemoval = pirexRewards.getRewardTokens(
            producerToken
        );
        address remainingToken = removalIndex == 0
            ? rewardToken2
            : rewardToken1;

        assertEq(1, rewardTokensAfterRemoval.length);
        assertEq(remainingToken, address(rewardTokensAfterRemoval[0]));
    }

    /*//////////////////////////////////////////////////////////////
                            claim TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is the zero address
     */
    function testCannotClaimProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        address user = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.claim(invalidProducerToken, user);
    }

    /**
        @notice Test tx reversion: producerToken is the zero address
     */
    function testCannotClaimUserZeroAddress() external {
        ERC20 producerToken = pxGlp;
        address invalidUser = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.claim(producerToken, invalidUser);
    }

    /**
        @notice Test claim
        @param  secondsElapsed  uint32  Seconds to forward timestamp
        @param  ethAmount       uint80  ETH amount used to mint pxGLP
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  useETH          bool    Whether to use ETH when minting
        @param  forwardRewards  bool    Whether to forward rewards
     */
    function testClaim(
        uint32 secondsElapsed,
        uint80 ethAmount,
        uint8 multiplier,
        bool useETH,
        bool forwardRewards
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(ethAmount > 0.001 ether);
        vm.assume(ethAmount < 10000 ether);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        _depositForTestAccountsPxGmx(multiplier);
        _depositForTestAccountsPxGlp(multiplier, useETH);

        vm.warp(block.timestamp + secondsElapsed);

        // Add reward token and harvest rewards from Pirex contract
        pirexRewards.addRewardToken(pxGmx, WETH);
        pirexRewards.addRewardToken(pxGlp, WETH);
        pirexRewards.harvest();

        for (uint256 i; i < testAccounts.length; ++i) {
            address recipient = forwardRewards
                ? address(this)
                : testAccounts[i];

            if (forwardRewards) {
                vm.startPrank(testAccounts[i]);

                pirexRewards.setRewardRecipient(pxGmx, WETH, address(this));
                pirexRewards.setRewardRecipient(pxGlp, WETH, address(this));

                vm.stopPrank();
            } else {
                assertEq(0, WETH.balanceOf(testAccounts[i]));
            }

            pirexRewards.userAccrue(pxGmx, testAccounts[i]);
            pirexRewards.userAccrue(pxGlp, testAccounts[i]);

            (, , uint256 globalRewardsBeforeClaimPxGmx) = _getGlobalState(
                pxGmx
            );
            (, , uint256 globalRewardsBeforeClaimPxGlp) = _getGlobalState(
                pxGlp
            );
            (, , uint256 userRewardsBeforeClaimPxGmx) = pirexRewards
                .getUserState(pxGmx, testAccounts[i]);
            (, , uint256 userRewardsBeforeClaimPxGlp) = pirexRewards
                .getUserState(pxGlp, testAccounts[i]);

            // Sum of reward amounts that the user/recipient is entitled to
            uint256 expectedClaimAmount = ((pirexRewards.getRewardState(
                pxGmx,
                WETH
            ) * _calculateUserRewards(pxGmx, testAccounts[i])) /
                _calculateGlobalRewards(pxGmx)) +
                ((pirexRewards.getRewardState(pxGlp, WETH) *
                    _calculateUserRewards(pxGlp, testAccounts[i])) /
                    _calculateGlobalRewards(pxGlp));

            // Deduct previous balance if rewards are forwarded
            uint256 recipientBalanceDeduction = forwardRewards
                ? WETH.balanceOf(recipient)
                : 0;

            pirexRewards.claim(pxGmx, testAccounts[i]);
            pirexRewards.claim(pxGlp, testAccounts[i]);

            (, , uint256 globalRewardsAfterClaimPxGmx) = _getGlobalState(pxGmx);
            (, , uint256 globalRewardsAfterClaimPxGlp) = _getGlobalState(pxGlp);
            (, , uint256 userRewardsAfterClaimPxGmx) = pirexRewards
                .getUserState(pxGmx, testAccounts[i]);
            (, , uint256 userRewardsAfterClaimPxGlp) = pirexRewards
                .getUserState(pxGlp, testAccounts[i]);

            assertEq(
                globalRewardsBeforeClaimPxGmx - userRewardsBeforeClaimPxGmx,
                globalRewardsAfterClaimPxGmx
            );
            assertEq(
                globalRewardsBeforeClaimPxGlp - userRewardsBeforeClaimPxGlp,
                globalRewardsAfterClaimPxGlp
            );
            assertEq(0, userRewardsAfterClaimPxGmx);
            assertEq(0, userRewardsAfterClaimPxGlp);
            assertEq(
                expectedClaimAmount,
                WETH.balanceOf(recipient) - recipientBalanceDeduction
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                    setRewardRecipientPrivileged TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotSetRewardRecipientPrivilegedNotAuthorized() external {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;
        address recipient = address(this);

        vm.prank(testAccounts[0]);
        vm.expectRevert("UNAUTHORIZED");

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: lpContract is not a contract
     */
    function testCannotSetRewardRecipientPrivilegedLpContractNotContract()
        external
    {
        // Any address w/o code works (even non-EOA, contract addresses not on Arbi)
        address invalidLpContract = testAccounts[0];

        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;
        address recipient = address(this);

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.setRewardRecipientPrivileged(
            invalidLpContract,
            producerToken,
            rewardToken,
            recipient
        );

        // Covers zero addresses
        invalidLpContract = address(0);

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.setRewardRecipientPrivileged(
            invalidLpContract,
            producerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: producerToken is the zero address
     */
    function testCannotSetRewardRecipientPrivilegedProducerTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = WETH;
        address recipient = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            invalidProducerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: rewardToken is the zero address
     */
    function testCannotSetRewardRecipientPrivilegedRewardTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));
        address recipient = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            invalidRewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: recipient is the zero address
     */
    function testCannotSetRewardRecipientPrivilegedRecipientZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;
        address invalidRecipient = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            invalidRecipient
        );
    }

    /**
        @notice Test setting the reward recipient as the contract owner
     */
    function testSetRewardRecipientPrivileged() external {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;
        address recipient = address(this);

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
        );

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit SetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                    unsetRewardRecipientPrivileged TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotUnsetRewardRecipientPrivilegedNotAuthorized() external {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;

        vm.prank(testAccounts[0]);
        vm.expectRevert("UNAUTHORIZED");

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken
        );
    }

    /**
        @notice Test tx reversion: lpContract is not a contract
     */
    function testCannotUnsetRewardRecipientPrivilegedLpContractNotContract()
        external
    {
        address invalidLpContract = testAccounts[0];
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            invalidLpContract,
            producerToken,
            rewardToken
        );

        invalidLpContract = address(0);

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            invalidLpContract,
            producerToken,
            rewardToken
        );
    }

    /**
        @notice Test tx reversion: producerToken is the zero address
     */
    function testCannotUnsetRewardRecipientPrivilegedProducerTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = WETH;

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            invalidProducerToken,
            rewardToken
        );
    }

    /**
        @notice Test tx reversion: rewardToken is the zero address
     */
    function testCannotUnsetRewardRecipientPrivilegedRewardTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            invalidRewardToken
        );
    }

    /**
        @notice Test unsetting a reward recipient as the contract owner
     */
    function testUnsetRewardRecipientPrivileged() external {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;

        // Set reward recipient in order to unset
        address recipient = address(this);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
        );

        vm.expectEmit(true, true, false, true, address(pirexRewards));

        emit UnsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken
        );

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken
        );

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
        );
    }
}
