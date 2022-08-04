// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {RewardsCoordinator} from "src/rewards/RewardsCoordinator.sol";
import {Helper} from "./Helper.t.sol";

contract RewardsCoordinatorTest is Helper {
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
        ) = rewardsCoordinator.globalStates(producerToken);

        return rewards + (block.timestamp - lastUpdate) * lastSupply;
    }

    /*//////////////////////////////////////////////////////////////
                        globalAccrue TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to producerToken being the zero address
     */
    function testCannotGlobalAccrue() external {
        ERC20 invalidProducerToken = ERC20(address(0));

        vm.expectRevert(RewardsCoordinator.ZeroAddress.selector);

        rewardsCoordinator.globalAccrue(invalidProducerToken);
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
        ) = rewardsCoordinator.globalStates(producerToken);

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
        ) = rewardsCoordinator.globalStates(producerToken);

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
        ) = rewardsCoordinator.globalStates(producerToken);

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

        (, , uint256 rewards) = rewardsCoordinator.globalStates(producerToken);
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

        rewardsCoordinator.globalAccrue(producerToken);

        (, , uint256 rewardsAfterBurn) = rewardsCoordinator.globalStates(
            producerToken
        );

        assertEq(expectedRewardsAfterBurn, rewardsAfterBurn);
        assertEq(
            noBurnRewards - expectedAndNoBurnRewardDelta,
            expectedRewardsAfterBurn
        );
    }
}
