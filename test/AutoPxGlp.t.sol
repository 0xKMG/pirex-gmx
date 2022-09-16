// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {AutoPxGlp} from "src/vaults/AutoPxGlp.sol";
import {PxGmxReward} from "src/vaults/PxGmxReward.sol";
import {Common} from "src/Common.sol";
import {Helper} from "./Helper.sol";

contract AutoPxGlpTest is Helper {
    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event CompoundIncentiveUpdated(uint256 incentive);
    event PlatformUpdated(address _platform);
    event Compounded(
        address indexed caller,
        uint256 minGlp,
        uint256 wethAmount,
        uint256 pxGmxAmountOut,
        uint256 pxGlpAmountOut,
        uint256 totalPxGlpFee,
        uint256 totalPxGmxFee,
        uint256 pxGlpIncentive,
        uint256 pxGmxIncentive
    );
    event PxGmxClaimed(
        address indexed account,
        address receiver,
        uint256 amount
    );

    /**
        @notice Calculate the global rewards accrued since the last update
        @return uint256  Global rewards
    */
    function _calculateGlobalRewards() internal view returns (uint256) {
        (uint256 lastUpdate, uint256 lastSupply, uint256 rewards) = autoPxGlp
            .globalState();

        return rewards + (block.timestamp - lastUpdate) * lastSupply;
    }

    /**
        @notice Calculate a user's rewards since the last update
        @param  user  address  User
        @return       uint256  User rewards
    */
    function _calculateUserRewards(address user)
        internal
        view
        returns (uint256)
    {
        (uint256 lastUpdate, uint256 lastBalance, uint256 rewards) = autoPxGlp
            .userRewardStates(user);

        return rewards + lastBalance * (block.timestamp - lastUpdate);
    }

    /**
        @notice Perform assertions for global state
        @param  expectedLastUpdate  uint256  Expected last update timestamp
        @param  expectedLastSupply  uint256  Expected last supply
        @param  expectedRewards     uint256  Expected rewards
    */
    function _assertGlobalState(
        uint256 expectedLastUpdate,
        uint256 expectedLastSupply,
        uint256 expectedRewards
    ) internal {
        (uint256 lastUpdate, uint256 lastSupply, uint256 rewards) = autoPxGlp
            .globalState();

        assertEq(expectedLastUpdate, lastUpdate);
        assertEq(expectedLastSupply, lastSupply);
        assertEq(expectedRewards, rewards);
    }

    /**
        @notice Perform assertions for user reward state
        @param  user                 address  User address
        @param  expectedLastUpdate   uint256  Expected last update timestamp
        @param  expectedLastBalance  uint256  Expected last user balance
        @param  expectedRewards      uint256  Expected rewards
    */
    function _assertUserRewardState(
        address user,
        uint256 expectedLastUpdate,
        uint256 expectedLastBalance,
        uint256 expectedRewards
    ) internal {
        (uint256 lastUpdate, uint256 lastBalance, uint256 rewards) = autoPxGlp
            .userRewardStates(user);

        assertEq(expectedLastUpdate, lastUpdate);
        assertEq(expectedLastBalance, lastBalance);
        assertEq(expectedRewards, rewards);
    }

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
        pirexRewards.addRewardToken(pxGmx, WETH);
        pirexRewards.addRewardToken(pxGmx, pxGmx);
        pirexRewards.addRewardToken(pxGlp, WETH);
        pirexRewards.addRewardToken(pxGlp, pxGmx);

        // Mint pxGLP with ETH, then deposit the pxGLP to the vault
        vm.deal(address(this), etherAmount);
        pirexGmx.depositGlpETH{value: etherAmount}(1, 1, receiver);

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
        @notice Compound and perform assertions partially
        @return wethAmount      uint256  WETH amount
        @return pxGmxAmount     uint256  pxGMX amount
        @return pxGlpAmount     uint256  pxGLP amount
        @return pxGlpFee        uint256  pxGLP fee
        @return pxGlpInc        uint256  pxGLP incentive
        @return pxGmxFee        uint256  pxGMX fee
    */
    function _compoundAndAssert()
        internal
        returns (
            uint256 wethAmount,
            uint256 pxGmxAmount,
            uint256 pxGlpAmount,
            uint256 pxGlpFee,
            uint256 pxGlpInc,
            uint256 pxGmxFee
        )
    {
        vm.expectEmit(true, false, false, false, address(autoPxGlp));

        emit Compounded(testAccounts[0], 0, 0, 0, 0, 0, 0, 0, 0);

        // Call as testAccounts[0] to test compound incentive transfer
        vm.prank(testAccounts[0]);

        (
            uint256 wethAmountIn,
            uint256 pxGmxAmountOut,
            uint256 pxGlpAmountOut,
            uint256 totalPxGlpFee,
            uint256 totalPxGmxFee,
            uint256 pxGlpIncentive,
            uint256 pxGmxIncentive
        ) = autoPxGlp.compound(1, 1, false);

        // Assert updated states separately (stack-too-deep issue)
        _assertPostCompoundPxGmxRewardStates(
            pxGmxAmountOut,
            totalPxGmxFee,
            pxGmxIncentive
        );

        wethAmount = wethAmountIn;
        pxGmxAmount = pxGmxAmountOut;
        pxGlpAmount = pxGlpAmountOut;
        pxGlpFee = totalPxGlpFee;
        pxGlpInc = pxGlpIncentive;
        pxGmxFee = totalPxGmxFee;
    }

    /**
        @notice Assert main vault states after performing compound
        @param  pxGlpAmountOut             uint256  pxGLP rewards before fees
        @param  totalPxGlpFee              uint256  Total fees for pxGLP
        @param  pxGlpIncentive             uint256  Incentive for pxGLP
        @param  totalAssetsBeforeCompound  uint256  Total assets before compound
     */
    function _assertPostCompoundVaultStates(
        uint256 pxGlpAmountOut,
        uint256 totalPxGlpFee,
        uint256 pxGlpIncentive,
        uint256 totalAssetsBeforeCompound
    ) internal {
        uint256 userShareBalance = autoPxGlp.balanceOf(address(this));
        uint256 expectedTotalPxGlpFee = (pxGlpAmountOut *
            autoPxGlp.platformFee()) / autoPxGlp.FEE_DENOMINATOR();
        uint256 expectedCompoundIncentive = (totalPxGlpFee *
            autoPxGlp.compoundIncentive()) / autoPxGlp.FEE_DENOMINATOR();
        uint256 expectedTotalAssets = totalAssetsBeforeCompound +
            pxGlpAmountOut -
            totalPxGlpFee;

        assertGt(expectedTotalAssets, totalAssetsBeforeCompound);
        assertEq(expectedTotalAssets, autoPxGlp.totalAssets());
        assertEq(expectedTotalAssets, pxGlp.balanceOf(address(autoPxGlp)));
        assertEq(expectedTotalPxGlpFee, totalPxGlpFee);
        assertEq(expectedCompoundIncentive, pxGlpIncentive);
        assertEq(
            expectedTotalPxGlpFee -
                expectedCompoundIncentive +
                expectedCompoundIncentive,
            totalPxGlpFee
        );

        // Check for vault asset balances of the fee receivers
        assertEq(
            expectedTotalPxGlpFee - expectedCompoundIncentive,
            pxGlp.balanceOf(autoPxGlp.owner())
        );
        assertEq(expectedCompoundIncentive, pxGlp.balanceOf(testAccounts[0]));

        assertEq(userShareBalance, autoPxGlp.balanceOf(address(this)));
        assertEq(
            ((userShareBalance * expectedTotalAssets) /
                autoPxGlp.totalSupply()) - totalAssetsBeforeCompound,
            autoPxGlp.convertToAssets(userShareBalance) -
                totalAssetsBeforeCompound
        );
        assertLt(
            totalAssetsBeforeCompound,
            autoPxGlp.convertToAssets(userShareBalance)
        );
    }

    /**
        @notice Assert pxGMX reward states after performing compound
        @param  pxGmxAmountOut  uint256  pxGMX rewards before fees
        @param  totalPxGmxFee   uint256  Total fees for pxGMX
        @param  pxGmxIncentive  uint256  Incentive for pxGMX
     */
    function _assertPostCompoundPxGmxRewardStates(
        uint256 pxGmxAmountOut,
        uint256 totalPxGmxFee,
        uint256 pxGmxIncentive
    ) internal {
        uint256 expectedTotalPxGmxFee = (pxGmxAmountOut *
            autoPxGlp.platformFee()) / autoPxGlp.FEE_DENOMINATOR();
        uint256 expectedCompoundPxGmxIncentive = (totalPxGmxFee *
            autoPxGlp.compoundIncentive()) / autoPxGlp.FEE_DENOMINATOR();
        assertEq(expectedTotalPxGmxFee, totalPxGmxFee);
        assertEq(expectedCompoundPxGmxIncentive, pxGmxIncentive);

        // Check for pxGMX reward balances of the fee receivers
        assertEq(
            expectedTotalPxGmxFee - expectedCompoundPxGmxIncentive,
            pxGmx.balanceOf(autoPxGlp.owner())
        );
        assertEq(
            expectedCompoundPxGmxIncentive,
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

        vm.expectRevert(PxGmxReward.ZeroAddress.selector);

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
        @notice Test tx reversion: minUsdg is invalid (zero)
     */
    function testCannotCompoundMinUsdgInvalidParam() external {
        uint256 invalidMinUsdg = 0;
        uint256 minGlp = 1;
        bool optOutIncentive = true;

        vm.expectRevert(AutoPxGlp.InvalidParam.selector);

        autoPxGlp.compound(invalidMinUsdg, minGlp, optOutIncentive);
    }

    /**
        @notice Test tx reversion: minGlp is invalid (zero)
     */
    function testCannotCompoundMinGlpInvalidParam() external {
        uint256 minUsdg = 1;
        uint256 invalidMinGlpAmount = 0;
        bool optOutIncentive = true;

        vm.expectRevert(AutoPxGlp.InvalidParam.selector);

        autoPxGlp.compound(minUsdg, invalidMinGlpAmount, optOutIncentive);
    }

    /**
        @notice Test tx success: compound pxGLP rewards into more pxGLP and track pxGMX reward states
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
        uint256 pxGmxBalanceBeforeCompound = pxGmx.balanceOf(
            address(autoPxGlp)
        );
        uint256 expectedGlobalLastSupply = autoPxGlp.totalSupply();
        uint256 expectedGlobalRewards = _calculateGlobalRewards();

        // Confirm current state prior to primary state mutating action
        assertEq(totalAssetsBeforeCompound, autoPxGlp.balanceOf(address(this)));
        assertGt(wethRewardState, 0);

        // Perform compound and assertions partially (stack-too-deep)
        (
            uint256 wethAmountIn,
            uint256 pxGmxAmountOut,
            uint256 pxGlpAmountOut,
            uint256 totalPxGlpFee,
            uint256 pxGlpIncentive,
            uint256 totalPxGmxFee
        ) = _compoundAndAssert();

        // Perform the rest of the assertions (stack-too-deep)
        assertEq(wethRewardState, wethAmountIn);
        assertEq(pxGmxRewardState, pxGmxAmountOut);

        _assertGlobalState(
            block.timestamp,
            expectedGlobalLastSupply,
            expectedGlobalRewards
        );
        _assertPostCompoundVaultStates(
            pxGlpAmountOut,
            totalPxGlpFee,
            pxGlpIncentive,
            totalAssetsBeforeCompound
        );
        assertEq(
            (pxGmxAmountOut - totalPxGmxFee),
            pxGmx.balanceOf(address(autoPxGlp)) - pxGmxBalanceBeforeCompound
        );
    }

    /*//////////////////////////////////////////////////////////////
                        deposit TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: deposit to vault and assert the pxGMX reward states updates
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
        uint256 expectedLastUpdate = block.timestamp;
        uint256 expectedGlobalRewards = _calculateGlobalRewards();
        uint256 expectedUserRewardState = _calculateUserRewards(receiver);
        uint256 pxGmxRewardAfterFees = pxGmxRewardState -
            (pxGmxRewardState * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();
        uint256 initialPxGmxBalance = pxGmx.balanceOf(address(autoPxGlp));

        // Perform another deposit and assert the updated pxGMX reward states
        vm.deal(receiver, etherAmount);
        pirexGmx.depositGlpETH{value: etherAmount}(1, 1, receiver);

        pxGlp.approve(address(autoPxGlp), pxGlp.balanceOf(receiver));
        uint256 newShares = autoPxGlp.deposit(
            pxGlp.balanceOf(receiver),
            receiver
        );

        // Assert pxGMX reward states
        _assertGlobalState(
            expectedLastUpdate,
            autoPxGlp.totalSupply(),
            expectedGlobalRewards
        );
        _assertUserRewardState(
            receiver,
            expectedLastUpdate,
            initialBalance + newShares,
            expectedUserRewardState
        );
        assertEq(autoPxGlp.rewardState(), pxGmxRewardAfterFees);

        // Deposit should still increment the totalSupply and user shares
        assertEq(autoPxGlp.totalSupply(), supply + newShares);
        assertEq(autoPxGlp.balanceOf(receiver), initialBalance + newShares);

        // Also check the updated pxGMX balance updated from compound call
        assertEq(
            pxGmx.balanceOf(address(autoPxGlp)),
            initialPxGmxBalance + pxGmxRewardAfterFees
        );
    }

    /*//////////////////////////////////////////////////////////////
                        mint TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: mint vault shares and assert the pxGMX reward states updates
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
        uint256 expectedLastUpdate = block.timestamp;
        uint256 expectedGlobalRewards = _calculateGlobalRewards();
        uint256 expectedUserRewardState = _calculateUserRewards(receiver);
        uint256 pxGmxRewardAfterFees = pxGmxRewardState -
            (pxGmxRewardState * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();
        uint256 initialPxGmxBalance = pxGmx.balanceOf(address(autoPxGlp));

        // Perform mint instead of deposit and assert the updated pxGMX reward states
        vm.deal(address(this), etherAmount);
        pirexGmx.depositGlpETH{value: etherAmount}(1, 1, receiver);

        pxGlp.approve(address(autoPxGlp), pxGlp.balanceOf(receiver));
        uint256 newShares = autoPxGlp.previewDeposit(
            pxGlp.balanceOf(receiver)
        ) / 2;
        autoPxGlp.mint(newShares, receiver);

        // Assert pxGMX reward states
        _assertGlobalState(
            expectedLastUpdate,
            autoPxGlp.totalSupply(),
            expectedGlobalRewards
        );
        _assertUserRewardState(
            receiver,
            expectedLastUpdate,
            initialBalance + newShares,
            expectedUserRewardState
        );
        assertEq(autoPxGlp.rewardState(), pxGmxRewardAfterFees);

        // Mint should still increment the totalSupply and user shares
        assertEq(autoPxGlp.totalSupply(), supply + newShares);
        assertEq(autoPxGlp.balanceOf(receiver), initialBalance + newShares);

        // Also check the updated pxGMX balance updated from compound call
        assertEq(
            pxGmx.balanceOf(address(autoPxGlp)),
            initialPxGmxBalance + pxGmxRewardAfterFees
        );
    }

    /*//////////////////////////////////////////////////////////////
                        withdraw TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: withdraw from vault and assert the pxGMX reward states updates
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
        uint256 expectedLastUpdate = block.timestamp;
        uint256 expectedGlobalRewards = _calculateGlobalRewards();
        uint256 expectedUserRewardState = _calculateUserRewards(receiver);
        uint256 pxGmxRewardAfterFees = pxGmxRewardState -
            (pxGmxRewardState * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();
        uint256 initialPxGmxBalance = pxGmx.balanceOf(address(autoPxGlp));

        // Withdraw from the vault and assert the updated pxGMX reward states
        uint256 shares = autoPxGlp.withdraw(initialBalance, receiver, receiver);

        // Assert pxGMX reward states
        _assertGlobalState(
            expectedLastUpdate,
            autoPxGlp.totalSupply(),
            expectedGlobalRewards
        );
        _assertUserRewardState(
            receiver,
            expectedLastUpdate,
            initialBalance - shares,
            expectedUserRewardState
        );
        assertEq(autoPxGlp.rewardState(), pxGmxRewardAfterFees);

        // Withdrawal should still decrement the totalSupply and user shares
        assertEq(autoPxGlp.totalSupply(), supply - shares);
        assertEq(autoPxGlp.balanceOf(receiver), initialBalance - shares);

        // Also check the updated pxGMX balance updated from compound call
        assertEq(
            pxGmx.balanceOf(address(autoPxGlp)),
            initialPxGmxBalance + pxGmxRewardAfterFees
        );
    }

    /*//////////////////////////////////////////////////////////////
                        redeem TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: redeem from vault and assert the pxGMX reward states updates
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
        uint256 expectedLastUpdate = block.timestamp;
        uint256 expectedGlobalRewards = _calculateGlobalRewards();
        uint256 expectedUserRewardState = _calculateUserRewards(receiver);
        uint256 pxGmxRewardAfterFees = pxGmxRewardState -
            (pxGmxRewardState * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();
        uint256 initialPxGmxBalance = pxGmx.balanceOf(address(autoPxGlp));

        // Redeem from the vault and assert the updated pxGMX reward states
        autoPxGlp.redeem(initialBalance, receiver, receiver);

        // Assert pxGMX reward states
        _assertGlobalState(
            expectedLastUpdate,
            autoPxGlp.totalSupply(),
            expectedGlobalRewards
        );
        _assertUserRewardState(
            receiver,
            expectedLastUpdate,
            0,
            expectedUserRewardState
        );
        assertEq(autoPxGlp.rewardState(), pxGmxRewardAfterFees);

        // Redemption should still decrement the totalSupply and user shares
        assertEq(autoPxGlp.totalSupply(), supply - initialBalance);
        assertEq(autoPxGlp.balanceOf(receiver), 0);

        // Also check the updated pxGMX balance updated from compound call
        assertEq(
            pxGmx.balanceOf(address(autoPxGlp)),
            initialPxGmxBalance + pxGmxRewardAfterFees
        );
    }

    /*//////////////////////////////////////////////////////////////
                        claim TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotClaimZeroAddress() external {
        address invalidReceiver = address(0);

        vm.expectRevert(PxGmxReward.ZeroAddress.selector);

        autoPxGlp.claim(invalidReceiver);
    }

    /**
        @notice Test tx success: claim pxGMX rewards and assert the reward states updates
        @param  etherAmount     uint96  Amount of ETH to deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testClaim(uint96 etherAmount, uint32 secondsElapsed) external {
        _validateTestArgs(etherAmount, secondsElapsed);

        address account = address(this);
        address receiver = testAccounts[0];

        (, uint256 pxGmxRewardState) = _provisionRewardState(
            etherAmount,
            account,
            secondsElapsed
        );

        uint256 pxGmxBalanceBeforeClaim = pxGmx.balanceOf(receiver);
        uint256 pxGmxRewardAfterFees = pxGmxRewardState -
            (pxGmxRewardState * autoPxGlp.platformFee()) /
            autoPxGlp.FEE_DENOMINATOR();
        uint256 expectedLastBalance = autoPxGlp.balanceOf(account);
        uint256 expectedGlobalLastUpdate = block.timestamp;
        uint256 expectedGlobalRewards = _calculateGlobalRewards();

        uint256 expectedUserRewardState = _calculateUserRewards(account);
        uint256 expectedClaimableReward = (pxGmxRewardAfterFees *
            expectedUserRewardState) / expectedGlobalRewards;

        assertEq(autoPxGlp.rewardState(), 0);

        // Event is only logged when rewards exists (ie. non-zero esGMX yields)
        if (expectedClaimableReward != 0) {
            vm.expectEmit(true, false, false, false, address(autoPxGlp));

            emit PxGmxClaimed(account, receiver, 0);
        }

        // Claim pxGMX reward from the vault and transfer it to the receiver directly
        autoPxGlp.claim(receiver);

        // Claiming should also update the pxGMX balance for the receiver and the reward state
        assertEq(
            pxGmx.balanceOf(receiver),
            expectedClaimableReward + pxGmxBalanceBeforeClaim
        );
        _assertGlobalState(
            expectedGlobalLastUpdate,
            autoPxGlp.totalSupply(),
            expectedGlobalRewards - expectedUserRewardState
        );
        _assertUserRewardState(
            account,
            block.timestamp,
            expectedLastBalance,
            0
        );
    }

    /*//////////////////////////////////////////////////////////////
                        transfer TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: transfer (or transferFrom) to another account and assert the pxGMX reward states
        @param  etherAmount         uint96  Amount of ETH to deposit
        @param  transferPercentage  uint8   Percentage of sender balance to be transferred
        @param  secondsElapsed      uint32  Seconds to forward timestamp
        @param  useTransferFrom     bool    Whether to use transferFrom
     */
    function testTransfer(
        uint96 etherAmount,
        uint8 transferPercentage,
        uint32 secondsElapsed,
        bool useTransferFrom
    ) external {
        _validateTestArgs(etherAmount, secondsElapsed);

        vm.assume(transferPercentage != 0);
        vm.assume(transferPercentage <= 100);

        address account = address(this);
        address receiver = testAccounts[0];

        _provisionRewardState(etherAmount, account, secondsElapsed);

        uint256 initialBalance = autoPxGlp.balanceOf(account);
        uint256 supply = autoPxGlp.totalSupply();
        uint256 expectedLastUpdate = block.timestamp;
        uint256 expectedSenderRewardState = _calculateUserRewards(account);
        uint256 expectedReceiverRewardState = _calculateUserRewards(receiver);

        // Transfer half of the apxGLP holding to the other account
        uint256 transferAmount = (initialBalance * transferPercentage) / 100;
        uint256 expectedSenderBalance = initialBalance - transferAmount;
        uint256 expectedReceiverBalance = transferAmount;

        assertEq(autoPxGlp.balanceOf(receiver), 0);

        // If transferFrom is used, make sure to properly approve the caller
        if (useTransferFrom) {
            autoPxGlp.approve(testAccounts[0], transferAmount);

            vm.prank(testAccounts[0]);

            autoPxGlp.transferFrom(account, receiver, transferAmount);
        } else {
            autoPxGlp.transfer(receiver, transferAmount);
        }

        // Assert pxGMX reward states for both sender and receiver
        _assertUserRewardState(
            account,
            expectedLastUpdate,
            expectedSenderBalance,
            expectedSenderRewardState
        );
        _assertUserRewardState(
            receiver,
            expectedLastUpdate,
            expectedReceiverBalance,
            expectedReceiverRewardState
        );
        assertEq(expectedReceiverRewardState, 0);

        // Transfer should still update the balances and maintain totalSupply
        assertEq(autoPxGlp.totalSupply(), supply);
        assertEq(autoPxGlp.balanceOf(account), expectedSenderBalance);
        assertEq(autoPxGlp.balanceOf(receiver), expectedReceiverBalance);
    }
}
