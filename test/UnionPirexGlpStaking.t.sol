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
    event Staked(uint256 amount);
    event Withdrawn(uint256 amount);

    function _setupForRewardAndAccrue(
        uint80 etherAmount,
        uint32 secondsElapsedForDeposit,
        uint32 secondsElapsedForReward,
        bool isExtraToken
    ) internal {
        vm.assume(etherAmount > 0.001 ether);
        vm.assume(etherAmount < 1_000 ether);
        vm.assume(secondsElapsedForDeposit > 1 hours);
        vm.assume(secondsElapsedForDeposit < 365 days);
        vm.assume(secondsElapsedForReward > 10);
        vm.assume(secondsElapsedForReward < 4 weeks);

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

        // Would also trigger notifyReward update for extra token
        unionPirexGlpStrategy.claimRewards();

        if (!isExtraToken) {
            // For main vault token, we need to simulate transfer of pxGlp back into the strategy
            // then trigger notifyReward
            _mintPx(address(this), etherAmount, false);

            pxGlp.transfer(address(unionPirexGlpStrategy), etherAmount);

            unionPirexGlpStrategy.notifyReward();
        }
    }

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
        @param  isExtraToken              bool    Whether to calculate for the extra token reward
     */
    function testRewardPerToken(
        uint80 etherAmount,
        uint32 secondsElapsedForDeposit,
        uint32 secondsElapsedForReward,
        bool isExtraToken
    ) external {
        _setupForRewardAndAccrue(
            etherAmount,
            secondsElapsedForDeposit,
            secondsElapsedForReward,
            isExtraToken
        );

        address token = isExtraToken
            ? unionPirexGlpStrategy.token()
            : unionPirexGlpStrategy.extraToken();

        (
            uint32 periodFinish,
            uint224 rewardRate,
            uint32 lastUpdateTime,
            uint224 rewardPerTokenStored
        ) = unionPirexGlpStrategy.rewardData(token);

        // Time skip for the reward streaming
        vm.warp(block.timestamp + secondsElapsedForReward);

        // Based on the current timestamp and reward state, calculate the expected reward per token
        uint256 supply = !isExtraToken
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

    /*//////////////////////////////////////////////////////////////
                        earned TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test calculating earned reward amount
        @param  etherAmount               uint80  Ether amount
        @param  secondsElapsedForDeposit  uint32  Seconds to forward timestamp after deposit
        @param  secondsElapsedForReward   uint32  Seconds to forward timestamp after notify reward
        @param  isExtraToken              bool    Whether to calculate for the extra token reward
     */
    function testEarned(
        uint80 etherAmount,
        uint32 secondsElapsedForDeposit,
        uint32 secondsElapsedForReward,
        bool isExtraToken
    ) external {
        _setupForRewardAndAccrue(
            etherAmount,
            secondsElapsedForDeposit,
            secondsElapsedForReward,
            isExtraToken
        );

        address token = isExtraToken
            ? unionPirexGlpStrategy.token()
            : unionPirexGlpStrategy.extraToken();

        // Time skip for the reward streaming
        vm.warp(block.timestamp + secondsElapsedForReward);

        // Calculate expected earned amount based on the current timestamp and reward state
        address account = isExtraToken
            ? address(this)
            : unionPirexGlpStrategy.vault();
        uint256 balance = isExtraToken
            ? unionPirexGlp.balanceOf(account)
            : unionPirexGlpStrategy.totalSupply();

        // Expected earned should equal proportionately to the current balance (decimals normalised)
        // as no claim has been done, with no pending reward has been calculated and stored
        uint256 expectedEarned = (balance *
            unionPirexGlpStrategy.rewardPerToken(token)) / 1e18;

        assertEq(
            expectedEarned,
            unionPirexGlpStrategy.earned(account, token, balance)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            stake TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to caller not being the vault
     */
    function testCannotStakeNotVault() external {
        address account = address(this);
        uint256 stakeAmount = 1;

        vm.expectRevert(UnionPirexGlpStaking.NotVault.selector);

        unionPirexGlpStrategy.stake(account, stakeAmount);
    }

    /**
        @notice Test tx reversion due to stake amount being zero
     */
    function testCannotStakeZeroAmount() external {
        address vault = unionPirexGlpStrategy.vault();
        address account = address(this);
        uint256 invalidStakeAmount = 0;

        vm.expectRevert(UnionPirexGlpStaking.ZeroAmount.selector);

        vm.prank(vault);

        unionPirexGlpStrategy.stake(account, invalidStakeAmount);
    }

    /**
        @notice Test staking
        @param  tokenAmount  uint80  pxGLP amount
     */
    function testStake(uint80 tokenAmount) external {
        vm.assume(tokenAmount > 1e10);
        vm.assume(tokenAmount < 10000e18);

        address account = address(this);

        // Simulate minting for direct test then transfer directly to the vault
        _mintPx(account, tokenAmount, false);
        pxGlp.transfer(address(unionPirexGlp), tokenAmount);

        address vault = unionPirexGlpStrategy.vault();
        uint256 preStakeTotalSupply = unionPirexGlpStrategy.totalSupply();

        // Perform direct deposit as the vault
        vm.prank(vault);

        vm.expectEmit(
            false,
            false,
            false,
            true,
            address(unionPirexGlpStrategy)
        );

        emit Staked(tokenAmount);

        unionPirexGlpStrategy.stake(account, tokenAmount);

        assertEq(
            unionPirexGlpStrategy.totalSupply(),
            preStakeTotalSupply + tokenAmount
        );
    }

    /*//////////////////////////////////////////////////////////////
                            withdraw TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to caller not being the vault
     */
    function testCannotWithdrawNotVault() external {
        address account = address(this);
        uint256 withdrawAmount = 1;

        vm.expectRevert(UnionPirexGlpStaking.NotVault.selector);

        unionPirexGlpStrategy.withdraw(account, withdrawAmount);
    }

    /**
        @notice Test tx reversion due to withdraw amount being zero
     */
    function testCannotWithdrawZeroAmount() external {
        address vault = unionPirexGlpStrategy.vault();
        address account = address(this);
        uint256 invalidWithdrawAmount = 0;

        vm.expectRevert(UnionPirexGlpStaking.ZeroAmount.selector);

        vm.prank(vault);

        unionPirexGlpStrategy.withdraw(account, invalidWithdrawAmount);
    }

    /**
        @notice Test withdrawal
        @param  tokenAmount  uint80  pxGLP amount
     */
    function testWithdraw(uint80 tokenAmount) external {
        vm.assume(tokenAmount > 1e10);
        vm.assume(tokenAmount < 10000e18);

        address account = address(this);

        // Simulate mint and deposit first before attempting to withdraw
        _mintPx(account, tokenAmount, false);
        pxGlp.transfer(address(unionPirexGlp), tokenAmount);

        address vault = unionPirexGlpStrategy.vault();
        uint256 preStakeTotalSupply = unionPirexGlpStrategy.totalSupply();

        vm.prank(vault);

        unionPirexGlpStrategy.stake(account, tokenAmount);

        uint256 postStakeTotalSupply = unionPirexGlpStrategy.totalSupply();

        assertEq(postStakeTotalSupply, preStakeTotalSupply + tokenAmount);

        // Withdraw and then asserts
        vm.prank(vault);

        vm.expectEmit(
            false,
            false,
            false,
            true,
            address(unionPirexGlpStrategy)
        );

        emit Withdrawn(tokenAmount);

        unionPirexGlpStrategy.withdraw(account, tokenAmount);

        assertEq(
            unionPirexGlpStrategy.totalSupply(),
            postStakeTotalSupply - tokenAmount
        );
    }
}
