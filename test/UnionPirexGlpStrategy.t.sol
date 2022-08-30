// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {UnionPirexGlpStrategy} from "src/vaults/UnionPirexGlpStrategy.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {Helper} from "./Helper.t.sol";

contract UnionPirexGlpStrategyTest is Helper {
    /**
        @notice Assert extra token reward states
        @param  rewardAmount  uint256  Reward amount
     */
    function _assertExtraReward(uint256 rewardAmount) internal {
        uint256 rewardsDuration = unionPirexGlpStrategy.rewardsDuration();
        (
            uint32 periodFinish,
            uint224 rewardRate,
            uint32 lastUpdateTime,
            uint224 rewardPerTokenStored
        ) = unionPirexGlpStrategy.rewardData(address(pxGmx));

        assertEq(periodFinish, block.timestamp + rewardsDuration);
        assertEq(rewardRate, rewardAmount / rewardsDuration);
        assertEq(lastUpdateTime, block.timestamp);
        assertEq(rewardPerTokenStored, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        claimRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test claiming rewards for union strategy
        @param  etherAmount     uint80  Ether amount
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testClaimRewards(uint80 etherAmount, uint32 secondsElapsed)
        external
    {
        vm.assume(etherAmount > 0.001 ether);
        vm.assume(etherAmount < 1_000 ether);
        vm.assume(secondsElapsed > 1 hours);
        vm.assume(secondsElapsed < 365 days);

        // Deposit and setup rewards
        address strategy = address(unionPirexGlpStrategy);

        vm.deal(address(this), etherAmount);

        pirexRewards.addRewardToken(pxGmx, WETH);
        pirexRewards.addRewardToken(pxGmx, ERC20(pxGmx));
        pirexRewards.addRewardToken(pxGlp, WETH);
        pirexRewards.addRewardToken(pxGlp, ERC20(pxGmx));

        pirexRewards.harvest();

        pirexGmxGlp.depositGlpWithETH{value: etherAmount}(
            1,
            address(this),
            true
        );

        vm.warp(block.timestamp + secondsElapsed);

        // Attempt to claim and assert updated states
        uint256 preClaimPxGmxBalance = pxGmx.balanceOf(strategy);
        uint256 preClaimWethBalance = WETH.balanceOf(address(this));
        (
            uint32 periodFinish,
            uint224 rewardRate,
            uint32 lastUpdateTime,
            uint224 rewardPerTokenStored
        ) = unionPirexGlpStrategy.rewardData(address(pxGmx));

        assertEq(periodFinish, 0);
        assertEq(rewardRate, 0);
        assertEq(lastUpdateTime, 0);
        assertEq(rewardPerTokenStored, 0);

        unionPirexGlpStrategy.claimRewards();

        // pxGMX rewards should be sent to the strategy contract itself
        // while WETH rewards should be sent to the distributor
        assertGt(pxGmx.balanceOf(strategy), preClaimPxGmxBalance);
        assertGt(WETH.balanceOf(address(this)), preClaimWethBalance);
        assertEq(pxGmx.balanceOf(address(this)), 0);
        assertEq(WETH.balanceOf(strategy), 0);

        // Assert the reward states separately (stack-too-deep)
        _assertExtraReward(
            pxGmx.balanceOf(address(unionPirexGlpStrategy)) -
                preClaimPxGmxBalance
        );
    }
}
