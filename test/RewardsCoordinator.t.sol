// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {RewardsCoordinator} from "src/rewards/RewardsCoordinator.sol";
import {Helper} from "./Helper.t.sol";

contract RewardsCoordinatorTest is Helper {
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
        @notice Test global rewards accrual
        @param  secondsElapsed  uint32  Seconds to forward timestamp (affects rewards accrued)
        @param  mintAmount      uint96  Amount of pxGLP to mint
     */
    function testGlobalAccrue(uint32 secondsElapsed, uint96 mintAmount)
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
}
