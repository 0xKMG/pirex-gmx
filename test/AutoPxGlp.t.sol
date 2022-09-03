// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {AutoPxGlp} from "src/vaults/AutoPxGlp.sol";
import {Helper} from "./Helper.t.sol";

contract AutoPxGlpTest is Helper {
    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event CompoundIncentiveUpdated(uint256 incentive);
    event PlatformUpdated(address _platform);
    event RewardsModuleUpdated(address _rewardsModule);
    event Compounded(
        address indexed caller,
        uint256 wethAmount,
        uint256 pxGmxAmountOut,
        uint256 pxGlpAmountOut,
        uint256 totalFee,
        uint256 totalExtraFee,
        uint256 incentive,
        uint256 extraIncentive
    );
    event ExtraRewardClaimed(
        address indexed account,
        address receiver,
        uint256 amount
    );

    /**
        @notice Validate common parameters used for deposits in the tests
        @param  etherAmount     uint96  Amount of ETH for deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function _validateTestArgs(uint96 etherAmount, uint32 secondsElapsed)
        internal
    {
        vm.assume(etherAmount > 0.001 ether);
        vm.assume(etherAmount < 1_000 ether);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
    }

    /**
        @notice Provision reward state to test compounding of rewards
        @param  etherAmount       uint256  Amount of ETH for deposit
        @param  receiver          address  Receiver of the GLP and pxGLP tokens
        @param  secondsElapsed    uint256  Seconds to forward timestamp
        @return wethRewardState   uint256  WETH reward state
        @return pxGmxRewardState  uint256  pxGMX reward state
     */
    function _provisionRewardState(
        uint256 etherAmount,
        address receiver,
        uint256 secondsElapsed
    ) internal returns (uint256 wethRewardState, uint256 pxGmxRewardState) {
        // Setup pirexRewards for the vault
        autoPxGlp.setRewardsModule(address(pirexRewards));

        pirexRewards.addRewardToken(pxGmx, WETH);
        pirexRewards.addRewardToken(pxGmx, pxGmx);
        pirexRewards.addRewardToken(pxGlp, WETH);
        pirexRewards.addRewardToken(pxGlp, pxGmx);

        // Mint pxGLP with ETH, then deposit the pxGLP to the vault
        vm.deal(address(this), etherAmount);
        pirexGmxGlp.depositGlpWithETH{value: etherAmount}(1, receiver);

        pxGlp.approve(address(autoPxGlp), pxGlp.balanceOf(receiver));
        autoPxGlp.deposit(pxGlp.balanceOf(receiver), receiver);

        // Time skip to accrue rewards then return the latest reward states
        vm.warp(block.timestamp + secondsElapsed);

        pirexRewards.harvest();

        // Take into account rewards from both pxGMX and pxGLP
        wethRewardState =
            pirexRewards.getRewardState(pxGmx, WETH) +
            pirexRewards.getRewardState(pxGlp, WETH);
        pxGmxRewardState =
            pirexRewards.getRewardState(pxGmx, pxGmx) +
            pirexRewards.getRewardState(pxGlp, pxGmx);
    }

    /**
        @notice Assert extra reward states after performing mutative actions
        @param  pxGmxRewardAfterFees  uint256  pxGMX rewards after fees
        @param  supply                uint256  Total supply
        @param  initialBalance        uint256  Initial balance
        @param  account               address  Account address
        @param  claim                 bool     Whether to check for claim related tests
     */
    function _assertExtraRewardStates(
        uint256 pxGmxRewardAfterFees,
        uint256 supply,
        uint256 initialBalance,
        address account,
        bool claim
    )
        internal
        returns (
            uint256 expectedRewardPerToken,
            uint256 expectedPendingExtraRewards
        )
    {
        // Expected reward per token should be using previous supply before the method being tested
        expectedRewardPerToken =
            (pxGmxRewardAfterFees * autoPxGlp.EXPANDED_DECIMALS()) /
            supply;
        expectedPendingExtraRewards =
            (initialBalance * expectedRewardPerToken) /
            autoPxGlp.EXPANDED_DECIMALS();

        // Extra reward state should be updated
        assertEq(
            expectedRewardPerToken,
            autoPxGlp.userExtraRewardPerToken(account)
        );
        assertEq(expectedRewardPerToken, autoPxGlp.extraRewardPerToken());

        if (claim) {
            // After claiming, the pending claimable should be back to 0
            assertEq(0, autoPxGlp.pendingExtraRewards(account));
        } else {
            // Otherwise, pending claimable should be updated using previous balance
            assertEq(
                expectedPendingExtraRewards,
                autoPxGlp.pendingExtraRewards(account)
            );
        }
    }

    /**
        @notice Assert main vault states after performing compound
        @param  pxGlpAmountOut                    uint256  pxGLP rewards before fees
        @param  totalFee                          uint256  Total fees fo pxGLP
        @param  incentive                         uint256  Incentive for pxGLP
        @param  totalAssetsBeforeCompound         uint256  Total assets before compound
        @param  shareToAssetAmountBeforeCompound  uint256  Share to asset ratio before compound
        @param  userShareBalance                  uint256  User shares amount
     */
    function _assertPostCompoundVaultStates(
        uint256 pxGlpAmountOut,
        uint256 totalFee,
        uint256 incentive,
        uint256 totalAssetsBeforeCompound,
        uint256 shareToAssetAmountBeforeCompound,
        uint256 userShareBalance
    ) internal {
        uint256 expectedTotalFee = (pxGlpAmountOut * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();
        uint256 expectedCompoundIncentive = (totalFee *
            autoPxGlp.compoundIncentive()) / autoPxGlp.FEE_DENOMINATOR();
        uint256 expectedTotalAssets = totalAssetsBeforeCompound +
            pxGlpAmountOut -
            totalFee;

        assertGt(expectedTotalAssets, totalAssetsBeforeCompound);
        assertEq(expectedTotalAssets, autoPxGlp.totalAssets());
        assertEq(expectedTotalAssets, pxGlp.balanceOf(address(autoPxGlp)));
        assertEq(expectedTotalFee, totalFee);
        assertEq(expectedCompoundIncentive, incentive);
        assertEq(
            expectedTotalFee -
                expectedCompoundIncentive +
                expectedCompoundIncentive,
            totalFee
        );

        // Check for vault asset balances of the fee receivers
        assertEq(
            expectedTotalFee - expectedCompoundIncentive,
            pxGlp.balanceOf(autoPxGlp.owner())
        );
        assertEq(expectedCompoundIncentive, pxGlp.balanceOf(testAccounts[0]));

        assertEq(userShareBalance, autoPxGlp.balanceOf(address(this)));
        assertEq(
            ((userShareBalance * expectedTotalAssets) /
                autoPxGlp.totalSupply()) - shareToAssetAmountBeforeCompound,
            autoPxGlp.convertToAssets(userShareBalance) -
                shareToAssetAmountBeforeCompound
        );
        assertLt(
            shareToAssetAmountBeforeCompound,
            autoPxGlp.convertToAssets(userShareBalance)
        );
    }

    /**
        @notice Assert extra reward states after performing compound
        @param  pxGmxAmountOut              uint256  pGMX rewards before fees
        @param  totalExtraFee               uint256  Total extra fees fo pxGMX
        @param  extraIncentive              uint256  Extra incentive for pxGMX
        @param  pxGmxBalanceBeforeCompound  uint256  pxGMX balance before compound
     */
    function _assertPostCompoundExtraRewardStates(
        uint256 pxGmxAmountOut,
        uint256 totalExtraFee,
        uint256 extraIncentive,
        uint256 pxGmxBalanceBeforeCompound
    ) internal {
        uint256 expectedTotalExtraFee = (pxGmxAmountOut *
            autoPxGlp.platformFee()) / autoPxGlp.FEE_DENOMINATOR();
        uint256 expectedCompoundExtraIncentive = (totalExtraFee *
            autoPxGlp.compoundIncentive()) / autoPxGlp.FEE_DENOMINATOR();

        assertEq(expectedTotalExtraFee, totalExtraFee);
        assertEq(expectedCompoundExtraIncentive, extraIncentive);
        assertEq(
            (pxGmxAmountOut - totalExtraFee),
            pxGmx.balanceOf(address(autoPxGlp)) - pxGmxBalanceBeforeCompound
        );
        assertEq(
            autoPxGlp.extraRewardPerToken(),
            ((pxGmxAmountOut - totalExtraFee) * autoPxGlp.EXPANDED_DECIMALS()) /
                autoPxGlp.totalSupply()
        );

        // Check for extra reward balances of the fee receivers
        assertEq(
            expectedTotalExtraFee - expectedCompoundExtraIncentive,
            pxGmx.balanceOf(autoPxGlp.owner())
        );
        assertEq(
            expectedCompoundExtraIncentive,
            pxGmx.balanceOf(testAccounts[0])
        );
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

        autoPxGlp.setWithdrawalPenalty(penalty);
    }

    /**
        @notice Test tx reversion: penalty exceeds max
     */
    function testCannotSetWithdrawalPenaltyExceedsMax() external {
        uint256 invalidPenalty = autoPxGlp.MAX_WITHDRAWAL_PENALTY() + 1;

        vm.expectRevert(AutoPxGlp.ExceedsMax.selector);

        autoPxGlp.setWithdrawalPenalty(invalidPenalty);
    }

    /**
        @notice Test tx success: set withdrawal penalty
     */
    function testSetWithdrawalPenalty() external {
        uint256 initialWithdrawalPenalty = autoPxGlp.withdrawalPenalty();
        uint256 penalty = 1;
        uint256 expectedWithdrawalPenalty = penalty;

        vm.expectEmit(false, false, false, true, address(autoPxGlp));

        emit WithdrawalPenaltyUpdated(expectedWithdrawalPenalty);

        autoPxGlp.setWithdrawalPenalty(penalty);

        assertEq(expectedWithdrawalPenalty, autoPxGlp.withdrawalPenalty());
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

        autoPxGlp.setPlatformFee(fee);
    }

    /**
        @notice Test tx reversion: fee exceeds max
     */
    function testCannotSetPlatformFeeExceedsMax() external {
        uint256 invalidFee = autoPxGlp.MAX_PLATFORM_FEE() + 1;

        vm.expectRevert(AutoPxGlp.ExceedsMax.selector);

        autoPxGlp.setPlatformFee(invalidFee);
    }

    /**
        @notice Test tx success: set platform fee
     */
    function testSetPlatformFee() external {
        uint256 initialPlatformFee = autoPxGlp.platformFee();
        uint256 fee = 1;
        uint256 expectedPlatformFee = fee;

        vm.expectEmit(false, false, false, true, address(autoPxGlp));

        emit PlatformFeeUpdated(expectedPlatformFee);

        autoPxGlp.setPlatformFee(fee);

        assertEq(expectedPlatformFee, autoPxGlp.platformFee());
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

        autoPxGlp.setCompoundIncentive(incentive);
    }

    /**
        @notice Test tx reversion: incentive exceeds max
     */
    function testCannotSetCompoundIncentiveExceedsMax() external {
        uint256 invalidIncentive = autoPxGlp.MAX_COMPOUND_INCENTIVE() + 1;

        vm.expectRevert(AutoPxGlp.ExceedsMax.selector);

        autoPxGlp.setCompoundIncentive(invalidIncentive);
    }

    /**
        @notice Test tx success: set compound incentive percent
     */
    function testSetCompoundIncentive() external {
        uint256 initialCompoundIncentive = autoPxGlp.compoundIncentive();
        uint256 incentive = 1;
        uint256 expectedCompoundIncentive = incentive;

        vm.expectEmit(false, false, false, true, address(autoPxGlp));

        emit CompoundIncentiveUpdated(expectedCompoundIncentive);

        autoPxGlp.setCompoundIncentive(incentive);

        assertEq(expectedCompoundIncentive, autoPxGlp.compoundIncentive());
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

        autoPxGlp.setPlatform(platform);
    }

    /**
        @notice Test tx reversion: platform is zero address
     */
    function testCannotSetPlatformZeroAddress() external {
        address invalidPlatform = address(0);

        vm.expectRevert(AutoPxGlp.ZeroAddress.selector);

        autoPxGlp.setPlatform(invalidPlatform);
    }

    /**
        @notice Test tx success: set platform
     */
    function testSetPlatform() external {
        address initialPlatform = autoPxGlp.platform();
        address platform = address(this);
        address expectedPlatform = platform;

        vm.expectEmit(false, false, false, true, address(autoPxGlp));

        emit PlatformUpdated(expectedPlatform);

        autoPxGlp.setPlatform(platform);

        assertEq(expectedPlatform, autoPxGlp.platform());
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

        autoPxGlp.setRewardsModule(rewardsModule);
    }

    /**
        @notice Test tx reversion: rewardsModule is zero address
     */
    function testCannotSetRewardsModuleZeroAddress() external {
        address invalidRewardsModule = address(0);

        vm.expectRevert(AutoPxGlp.ZeroAddress.selector);

        autoPxGlp.setRewardsModule(invalidRewardsModule);
    }

    /**
        @notice Test tx success: set rewardsModule
     */
    function testSetRewardsModule() external {
        address initialRewardsModule = autoPxGlp.rewardsModule();
        address rewardsModule = address(this);
        address expectedRewardsModule = rewardsModule;

        vm.expectEmit(false, false, false, true, address(autoPxGlp));

        emit RewardsModuleUpdated(expectedRewardsModule);

        autoPxGlp.setRewardsModule(rewardsModule);

        assertEq(expectedRewardsModule, autoPxGlp.rewardsModule());
        assertTrue(expectedRewardsModule != initialRewardsModule);
    }

    /*//////////////////////////////////////////////////////////////
                        totalAssets TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice  Test tx success: return the total assets
    */
    function testTotalAssets() external {
        uint256 initialTotalAssets = autoPxGlp.totalAssets();
        uint256 etherAmount = 1 ether;
        uint256 secondsElapsed = 1 hours;
        address receiver = address(this);

        _provisionRewardState(etherAmount, receiver, secondsElapsed);

        uint256 assets = pxGlp.balanceOf(address(autoPxGlp));

        assertEq(assets, autoPxGlp.totalAssets());
        assertTrue(assets != initialTotalAssets);
    }

    /*//////////////////////////////////////////////////////////////
                        compound TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: minGlpAmount is invalid (zero)
     */
    function testCannotCompoundMinAmountInvalidParam() external {
        uint256 invalidMinGlpAmount = 0;
        bool optOutIncentive = true;

        vm.expectRevert(AutoPxGlp.InvalidParam.selector);

        autoPxGlp.compound(invalidMinGlpAmount, optOutIncentive);
    }

    /**
        @notice Test tx success: compound pxGLP rewards into more pxGLP and track extra rewards (pxGMX)
        @param  etherAmount     uint96  Amount of ETH to deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testCompound(uint96 etherAmount, uint32 secondsElapsed) external {
        _validateTestArgs(etherAmount, secondsElapsed);

        (
            uint256 wethRewardState,
            uint256 pxGmxRewardState
        ) = _provisionRewardState(etherAmount, address(this), secondsElapsed);

        uint256 totalAssetsBeforeCompound = autoPxGlp.totalAssets();
        uint256 userShareBalance = autoPxGlp.balanceOf(address(this));
        uint256 shareToAssetAmountBeforeCompound = autoPxGlp.convertToAssets(
            userShareBalance
        );
        uint256 pxGmxBalanceBeforeCompound = pxGmx.balanceOf(
            address(autoPxGlp)
        );

        // Confirm current state prior to primary state mutating action
        assertEq(totalAssetsBeforeCompound, userShareBalance);
        assertGt(wethRewardState, 0);
        assertGt(pxGmxRewardState, 0);
        assertEq(autoPxGlp.extraRewardPerToken(), 0);

        vm.expectEmit(true, false, false, false, address(autoPxGlp));

        emit Compounded(testAccounts[0], 0, 0, 0, 0, 0, 0, 0);

        // Call as testAccounts[0] to test compound incentive transfer
        vm.prank(testAccounts[0]);

        (
            uint256 wethAmountIn,
            uint256 pxGmxAmountOut,
            uint256 pxGlpAmountOut,
            uint256 totalFee,
            uint256 totalExtraFee,
            uint256 incentive,
            uint256 extraIncentive
        ) = autoPxGlp.compound(1, false);

        assertEq(wethRewardState, wethAmountIn);
        assertEq(pxGmxAmountOut, pxGmxRewardState);

        // Assert updated states separately (stack-too-deep issue)
        _assertPostCompoundExtraRewardStates(
            pxGmxAmountOut,
            totalExtraFee,
            extraIncentive,
            pxGmxBalanceBeforeCompound
        );

        // Assert updated states separately (stack-too-deep issue)
        _assertPostCompoundVaultStates(
            pxGlpAmountOut,
            totalFee,
            incentive,
            totalAssetsBeforeCompound,
            shareToAssetAmountBeforeCompound,
            userShareBalance
        );
    }

    /*//////////////////////////////////////////////////////////////
                        deposit TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: deposit to vault and assert the extra reward states updates
        @param  etherAmount     uint96  Amount of ETH to deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testDeposit(uint96 etherAmount, uint32 secondsElapsed) external {
        _validateTestArgs(etherAmount, secondsElapsed);

        address receiver = address(this);

        (, uint256 pxGmxRewardState) = _provisionRewardState(
            etherAmount,
            receiver,
            secondsElapsed
        );

        uint256 initialBalance = autoPxGlp.balanceOf(receiver);
        uint256 supply = autoPxGlp.totalSupply();
        uint256 pxGmxRewardAfterFees = pxGmxRewardState -
            (pxGmxRewardState * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();

        assertEq(0, autoPxGlp.userExtraRewardPerToken(receiver));

        // Perform another deposit and assert the updated extra reward states
        vm.deal(address(this), etherAmount);
        pirexGmxGlp.depositGlpWithETH{value: etherAmount}(1, receiver);

        pxGlp.approve(address(autoPxGlp), pxGlp.balanceOf(receiver));
        uint256 newShares = autoPxGlp.deposit(
            pxGlp.balanceOf(receiver),
            receiver
        );

        // Assert extra reward states, which should be based on previous supply before the new deposit
        _assertExtraRewardStates(
            pxGmxRewardAfterFees,
            supply,
            initialBalance,
            receiver,
            false
        );

        // Deposit should still increment the totalSupply and user shares
        assertEq(autoPxGlp.totalSupply(), supply + newShares);
        assertEq(autoPxGlp.balanceOf(receiver), initialBalance + newShares);
    }

    /*//////////////////////////////////////////////////////////////
                        mint TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: mint vault shares and assert the extra reward states updates
        @param  etherAmount     uint96  Amount of ETH to deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testMint(uint96 etherAmount, uint32 secondsElapsed) external {
        _validateTestArgs(etherAmount, secondsElapsed);

        address receiver = address(this);

        (, uint256 pxGmxRewardState) = _provisionRewardState(
            etherAmount,
            receiver,
            secondsElapsed
        );

        uint256 initialBalance = autoPxGlp.balanceOf(receiver);
        uint256 supply = autoPxGlp.totalSupply();
        uint256 pxGmxRewardAfterFees = pxGmxRewardState -
            (pxGmxRewardState * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();

        assertEq(0, autoPxGlp.userExtraRewardPerToken(receiver));

        // Perform mint instead of deposit and assert the updated extra reward states
        vm.deal(address(this), etherAmount);
        pirexGmxGlp.depositGlpWithETH{value: etherAmount}(1, receiver);

        pxGlp.approve(address(autoPxGlp), pxGlp.balanceOf(receiver));
        uint256 newShares = autoPxGlp.previewDeposit(
            pxGlp.balanceOf(receiver)
        ) / 2;
        autoPxGlp.mint(newShares, receiver);

        // Assert extra reward states, which should be based on previous supply before the new deposit
        _assertExtraRewardStates(
            pxGmxRewardAfterFees,
            supply,
            initialBalance,
            receiver,
            false
        );

        // Mint should still increment the totalSupply and user shares
        assertEq(autoPxGlp.totalSupply(), supply + newShares);
        assertEq(autoPxGlp.balanceOf(receiver), initialBalance + newShares);
    }

    /*//////////////////////////////////////////////////////////////
                        withdraw TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: withdraw from vault and assert the extra reward states updates
        @param  etherAmount     uint96  Amount of ETH to deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testWithdraw(uint96 etherAmount, uint32 secondsElapsed) external {
        _validateTestArgs(etherAmount, secondsElapsed);

        address receiver = address(this);

        (, uint256 pxGmxRewardState) = _provisionRewardState(
            etherAmount,
            receiver,
            secondsElapsed
        );

        uint256 initialBalance = autoPxGlp.balanceOf(receiver);
        uint256 supply = autoPxGlp.totalSupply();
        uint256 pxGmxRewardAfterFees = pxGmxRewardState -
            (pxGmxRewardState * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();

        assertEq(0, autoPxGlp.userExtraRewardPerToken(receiver));

        // Withdraw from the vault and assert the updated extra reward states
        uint256 shares = autoPxGlp.withdraw(initialBalance, receiver, receiver);

        // Assert extra reward states, which should be based on previous supply before the withdrawal
        _assertExtraRewardStates(
            pxGmxRewardAfterFees,
            supply,
            initialBalance,
            receiver,
            false
        );

        // Withdrawal should still decrement the totalSupply and user shares
        assertEq(autoPxGlp.totalSupply(), supply - shares);
        assertEq(autoPxGlp.balanceOf(receiver), initialBalance - shares);
    }

    /*//////////////////////////////////////////////////////////////
                        redeem TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: redeem from vault and assert the extra reward states updates
        @param  etherAmount     uint96  Amount of ETH to deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testRedeem(uint96 etherAmount, uint32 secondsElapsed) external {
        _validateTestArgs(etherAmount, secondsElapsed);

        address receiver = address(this);

        (, uint256 pxGmxRewardState) = _provisionRewardState(
            etherAmount,
            receiver,
            secondsElapsed
        );

        uint256 initialBalance = autoPxGlp.balanceOf(receiver);
        uint256 supply = autoPxGlp.totalSupply();
        uint256 pxGmxRewardAfterFees = pxGmxRewardState -
            (pxGmxRewardState * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();

        assertEq(0, autoPxGlp.userExtraRewardPerToken(receiver));

        // Redeem from the vault and assert the updated extra reward states
        autoPxGlp.redeem(initialBalance, receiver, receiver);

        // Assert extra reward states, which should be based on previous supply before the redemption
        _assertExtraRewardStates(
            pxGmxRewardAfterFees,
            supply,
            initialBalance,
            receiver,
            false
        );

        // Redemption should still decrement the totalSupply and user shares
        assertEq(autoPxGlp.totalSupply(), supply - initialBalance);
        assertEq(autoPxGlp.balanceOf(receiver), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        claimExtraReward TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotClaimExtraRewardsZeroAddress() external {
        address invalidReceiver = address(0);

        vm.expectRevert(AutoPxGlp.ZeroAddress.selector);

        autoPxGlp.claimExtraReward(invalidReceiver);
    }

    /**
        @notice Test tx success: claim extra rewards and assert the extra reward states updates
        @param  etherAmount     uint96  Amount of ETH to deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testClaimExtraReward(uint96 etherAmount, uint32 secondsElapsed)
        external
    {
        _validateTestArgs(etherAmount, secondsElapsed);

        address account = address(this);
        address receiver = testAccounts[0];

        (, uint256 pxGmxRewardState) = _provisionRewardState(
            etherAmount,
            account,
            secondsElapsed
        );

        uint256 initialBalance = autoPxGlp.balanceOf(account);
        uint256 pxGmxBalanceBeforeClaim = pxGmx.balanceOf(receiver);
        uint256 supply = autoPxGlp.totalSupply();
        uint256 pxGmxRewardAfterFees = pxGmxRewardState -
            (pxGmxRewardState * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();

        assertEq(0, autoPxGlp.userExtraRewardPerToken(account));

        // Claim extra rewards (pxGMX) from the vault and transfer it to the receiver directly
        autoPxGlp.claimExtraReward(receiver);

        // Assert extra reward states, which should be based on previous supply before the claim
        (, uint256 expectedPendingExtraRewards) = _assertExtraRewardStates(
            pxGmxRewardAfterFees,
            supply,
            initialBalance,
            account,
            true
        );

        // Claiming should also update the extra rewards (pxGMX) balance for the receiver
        assertEq(
            expectedPendingExtraRewards,
            pxGmx.balanceOf(receiver) - pxGmxBalanceBeforeClaim
        );
    }

    /*//////////////////////////////////////////////////////////////
                        transfer TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: transfer to another account and assert the extra reward states updates
        @param  etherAmount     uint96  Amount of ETH to deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testTransfer(uint96 etherAmount, uint32 secondsElapsed) external {
        _validateTestArgs(etherAmount, secondsElapsed);

        address account = address(this);
        address receiver = testAccounts[0];

        (, uint256 pxGmxRewardState) = _provisionRewardState(
            etherAmount,
            account,
            secondsElapsed
        );

        uint256 initialBalance = autoPxGlp.balanceOf(account);
        uint256 supply = autoPxGlp.totalSupply();
        uint256 pxGmxRewardAfterFees = pxGmxRewardState -
            (pxGmxRewardState * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();

        assertEq(0, autoPxGlp.userExtraRewardPerToken(account));
        assertEq(0, autoPxGlp.userExtraRewardPerToken(receiver));

        // Transfer half of the apxGLP holding to another account
        uint256 transferAmount = initialBalance / 2;
        autoPxGlp.transfer(receiver, transferAmount);

        // Assert extra reward states, which should be based on previous supply before the transfer
        (uint256 expectedRewardPerToken, ) = _assertExtraRewardStates(
            pxGmxRewardAfterFees,
            supply,
            initialBalance,
            account,
            false
        );

        // Should also check for the receiver's
        assertEq(
            expectedRewardPerToken,
            autoPxGlp.userExtraRewardPerToken(receiver)
        );
        assertEq(0, autoPxGlp.pendingExtraRewards(receiver));

        // Transfer should still update the balances and maintain totalSupply
        assertEq(autoPxGlp.totalSupply(), supply);
        assertEq(autoPxGlp.balanceOf(account), initialBalance - transferAmount);
        assertEq(autoPxGlp.balanceOf(receiver), transferAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        transferFrom TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: transfer from one to another account and assert the extra reward states updates
        @param  etherAmount     uint96  Amount of ETH to deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testTransferFrom(uint96 etherAmount, uint32 secondsElapsed)
        external
    {
        _validateTestArgs(etherAmount, secondsElapsed);

        address account = address(this);
        address receiver = testAccounts[0];

        (, uint256 pxGmxRewardState) = _provisionRewardState(
            etherAmount,
            account,
            secondsElapsed
        );

        uint256 initialBalance = autoPxGlp.balanceOf(account);
        uint256 supply = autoPxGlp.totalSupply();
        uint256 pxGmxRewardAfterFees = pxGmxRewardState -
            (pxGmxRewardState * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();

        assertEq(0, autoPxGlp.userExtraRewardPerToken(account));
        assertEq(0, autoPxGlp.userExtraRewardPerToken(receiver));

        // Transfer half of the apxGLP holding to another account using `transferFrom`
        uint256 transferAmount = initialBalance / 2;
        autoPxGlp.approve(address(this), transferAmount);
        autoPxGlp.transferFrom(account, receiver, transferAmount);

        // Assert extra reward states, which should be based on previous supply before the transfer
        (uint256 expectedRewardPerToken, ) = _assertExtraRewardStates(
            pxGmxRewardAfterFees,
            supply,
            initialBalance,
            account,
            false
        );

        // Should also check for the receiver's
        assertEq(
            expectedRewardPerToken,
            autoPxGlp.userExtraRewardPerToken(receiver)
        );
        assertEq(0, autoPxGlp.pendingExtraRewards(receiver));

        // Transfer should still update the balances and maintain totalSupply
        assertEq(autoPxGlp.totalSupply(), supply);
        assertEq(autoPxGlp.balanceOf(account), initialBalance - transferAmount);
        assertEq(autoPxGlp.balanceOf(receiver), transferAmount);
    }
}
