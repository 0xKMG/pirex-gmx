// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {UnionPirexGlpStaking} from "src/vaults/UnionPirexGlpStaking.sol";
import {UnionPirexGlpStrategy} from "src/vaults/UnionPirexGlpStrategy.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {Helper} from "./Helper.t.sol";

contract UnionPirexGlpStakingTest is Helper {
    event SetDistributor(address distributor);

    /*//////////////////////////////////////////////////////////////
                        setDistributor TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion if distributor is zero
     */
    function testCannotSetDistributorZeroAddress() external {
        address invalidDistributor = address(0);

        vm.expectRevert(UnionPirexGlpStaking.ZeroAddress.selector);

        unionPirexGlpStrategy.setDistributor(invalidDistributor);
    }

    /**
        @notice Test setting distributor
     */
    function testSetDistributor() external {
        address strategy = address(unionPirexGlpStrategy);
        address oldDistributor = unionPirexGlpStrategy.distributor();
        address newDistributor = testAccounts[0];

        assertFalse(oldDistributor == newDistributor);

        vm.expectEmit(
            false,
            false,
            false,
            true,
            address(unionPirexGlpStrategy)
        );

        emit SetDistributor(newDistributor);

        unionPirexGlpStrategy.setDistributor(newDistributor);

        assertEq(unionPirexGlpStrategy.distributor(), newDistributor);

        // Also assert for reward recipient in pirexRewards
        assertEq(
            pirexRewards.getRewardRecipient(strategy, ERC20(pxGlp), WETH),
            newDistributor
        );
        assertEq(
            pirexRewards.getRewardRecipient(strategy, ERC20(pxGmx), WETH),
            newDistributor
        );
        assertEq(
            pirexRewards.getRewardRecipient(
                strategy,
                ERC20(pxGlp),
                ERC20(pxGmx)
            ),
            address(0)
        );
        assertEq(
            pirexRewards.getRewardRecipient(
                strategy,
                ERC20(pxGmx),
                ERC20(pxGmx)
            ),
            address(0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        rewardPerToken TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test calculating reward amount per token
        @param  etherAmount               uint80  Ether amount
        @param  secondsElapsedForDeposit  uint32  Seconds to forward timestamp after deposit
        @param  secondsElapsedForReward   uint32  Seconds to forward timestamp after notify reward
     */
    function testRewardPerToken(
        uint80 etherAmount,
        uint32 secondsElapsedForDeposit,
        uint32 secondsElapsedForReward
    ) external {
        vm.assume(etherAmount > 0.001 ether);
        vm.assume(etherAmount < 1_000 ether);
        vm.assume(secondsElapsedForDeposit > 1 hours);
        vm.assume(secondsElapsedForDeposit < 365 days);
        vm.assume(secondsElapsedForReward > 10);
        vm.assume(secondsElapsedForReward < 4 weeks);

        address token = unionPirexGlpStrategy.extraToken();

        // Deposit and setup rewards
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

        vm.warp(block.timestamp + secondsElapsedForDeposit);

        // Trigger notify reward update for extra token
        unionPirexGlpStrategy.claimRewards();

        (
            uint32 periodFinish,
            uint224 rewardRate,
            uint32 lastUpdateTime,
            uint224 rewardPerTokenStored
        ) = unionPirexGlpStrategy.rewardData(token);

        // Time skip for the reward streaming
        vm.warp(block.timestamp + secondsElapsedForReward);

        // Based on the current timestamp and reward state, calculate the expected reward per token
        uint256 supply = token == address(pxGlp)
            ? unionPirexGlpStrategy.totalSupply()
            : unionPirexGlp.totalSupply();
        uint256 lastApplicable = block.timestamp < periodFinish
            ? block.timestamp
            : periodFinish;
        uint256 expectedRewardPerToken = rewardPerTokenStored +
            ((((lastApplicable - lastUpdateTime) * rewardRate) * 1e18) /
                supply);

        assertEq(
            unionPirexGlpStrategy.rewardPerToken(token),
            expectedRewardPerToken
        );
    }
}
