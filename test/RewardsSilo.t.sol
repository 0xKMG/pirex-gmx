// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {RewardsSilo} from "src/rewards/RewardsSilo.sol";
import {Helper} from "./Helper.t.sol";

contract RewardsSiloTest is Helper {
    /*//////////////////////////////////////////////////////////////
                        rewardAccrue TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to caller not being authorized
     */
    function testCannotRewardAccrueNotAuthorized() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;
        uint256 rewardAmount = 1;

        vm.expectRevert(RewardsSilo.NotAuthorized.selector);

        rewardsSilo.rewardAccrue(producerToken, rewardToken, rewardAmount);
    }

    /**
        @notice Test tx reversion due to producerToken having the zero address
     */
    function testCannotRewardAccrueProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = WETH;
        uint256 rewardAmount = 1;

        vm.prank(address(rewardsHarvester));
        vm.expectRevert(RewardsSilo.ZeroAddress.selector);

        rewardsSilo.rewardAccrue(
            invalidProducerToken,
            rewardToken,
            rewardAmount
        );
    }

    /**
        @notice Test tx reversion due to rewardToken having the zero address
     */
    function testCannotRewardAccrueRewardTokenZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));
        uint256 rewardAmount = 1;

        vm.prank(address(rewardsHarvester));
        vm.expectRevert(RewardsSilo.ZeroAddress.selector);

        rewardsSilo.rewardAccrue(
            producerToken,
            invalidRewardToken,
            rewardAmount
        );
    }

    /**
        @notice Test tx reversion due to rewardAmount being zero
     */
    function testCannotRewardAccrueRewardAmountZeroAmount() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = WETH;
        uint256 invalidRewardAmount = 0;

        vm.prank(address(rewardsHarvester));
        vm.expectRevert(RewardsSilo.ZeroAmount.selector);

        rewardsSilo.rewardAccrue(
            producerToken,
            rewardToken,
            invalidRewardAmount
        );
    }
}
