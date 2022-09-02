// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {AutoPxGlp} from "src/vaults/AutoPxGlp.sol";
import {Helper} from "./Helper.t.sol";

contract AutoPxGlpTest is Helper {
    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event PlatformUpdated(address _platform);
    event RewardsModuleUpdated(address _rewardsModule);
    event Compounded(
        address indexed caller,
        uint256 wethAmount,
        uint256 pxGmxAmountOut,
        uint256 pxGlpAmountOut
    );
    event ExtraRewardClaimed(
        address indexed account,
        address receiver,
        uint256 amount
    );

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
        @notice Test tx success: compound pxGLP rewards into more pxGLP and track extra rewards (pxGMX)
        @param  etherAmount     uint96  Amount of ETH to deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testCompound(uint96 etherAmount, uint32 secondsElapsed) external {
        vm.assume(etherAmount > 0.001 ether);
        vm.assume(etherAmount < 1_000 ether);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);

        address receiver = address(this);

        (
            uint256 wethRewardState,
            uint256 pxGmxRewardState
        ) = _provisionRewardState(etherAmount, receiver, secondsElapsed);

        uint256 totalAssetsBeforeCompound = autoPxGlp.totalAssets();
        uint256 userShareBalance = autoPxGlp.balanceOf(receiver);
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

        emit Compounded(receiver, 0, 0, 0);

        (
            uint256 wethAmountIn,
            uint256 pxGmxAmountOut,
            uint256 pxGlpAmountOut
        ) = autoPxGlp.compound();

        uint256 expectedTotalAssets = totalAssetsBeforeCompound +
            pxGlpAmountOut;
        uint256 expectedShareToAssetAmountDifference = ((userShareBalance *
            expectedTotalAssets) / autoPxGlp.totalSupply()) -
            shareToAssetAmountBeforeCompound;

        assertEq(wethRewardState, wethAmountIn);
        assertGt(expectedTotalAssets, totalAssetsBeforeCompound);
        assertEq(expectedTotalAssets, autoPxGlp.totalAssets());
        assertEq(expectedTotalAssets, pxGlp.balanceOf(address(autoPxGlp)));
        assertEq(userShareBalance, autoPxGlp.balanceOf(address(this)));
        assertEq(
            expectedShareToAssetAmountDifference,
            autoPxGlp.convertToAssets(userShareBalance) -
                shareToAssetAmountBeforeCompound
        );
        assertLt(
            shareToAssetAmountBeforeCompound,
            autoPxGlp.convertToAssets(userShareBalance)
        );
        assertEq(pxGmxAmountOut, pxGmxRewardState);
        assertEq(
            pxGmxRewardState,
            pxGmx.balanceOf(address(autoPxGlp)) - pxGmxBalanceBeforeCompound
        );
        assertEq(
            autoPxGlp.extraRewardPerToken(),
            (pxGmxRewardState * autoPxGlp.EXPANDED_DECIMALS()) /
                autoPxGlp.totalSupply()
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
        vm.assume(etherAmount > 0.001 ether);
        vm.assume(etherAmount < 1_000 ether);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);

        address receiver = address(this);

        (, uint256 pxGmxRewardState) = _provisionRewardState(
            etherAmount,
            receiver,
            secondsElapsed
        );

        uint256 initialBalance = autoPxGlp.balanceOf(receiver);
        uint256 supply = autoPxGlp.totalSupply();

        assertEq(autoPxGlp.userExtraRewardPerToken(receiver), 0);

        // Perform another deposit and assert the updated extra reward states
        vm.deal(address(this), etherAmount);
        pirexGmxGlp.depositGlpWithETH{value: etherAmount}(1, receiver);

        pxGlp.approve(address(autoPxGlp), pxGlp.balanceOf(receiver));
        autoPxGlp.deposit(pxGlp.balanceOf(receiver), receiver);

        // Expected reward per token should be using previous supply before the new deposit
        uint256 expectedRewardPerToken = (pxGmxRewardState *
            autoPxGlp.EXPANDED_DECIMALS()) / supply;
        uint256 expectedPendingExtraRewards = (initialBalance *
            expectedRewardPerToken) / autoPxGlp.EXPANDED_DECIMALS();

        // Extra reward state should be updated
        assertEq(
            expectedRewardPerToken,
            autoPxGlp.userExtraRewardPerToken(receiver)
        );
        assertEq(expectedRewardPerToken, autoPxGlp.extraRewardPerToken());

        // The new deposit should update pending claimable extra rewards using previous balance
        assertEq(
            expectedPendingExtraRewards,
            autoPxGlp.pendingExtraRewards(receiver)
        );

        // Deposit should still increment the totalSupply and user shares
        assertGt(autoPxGlp.totalSupply(), supply);
        assertGt(autoPxGlp.balanceOf(receiver), initialBalance);
    }
}
