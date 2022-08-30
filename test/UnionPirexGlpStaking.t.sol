// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {UnionPirexGlpStaking} from "src/vaults/UnionPirexGlpStaking.sol";
import {UnionPirexGlpStrategy} from "src/vaults/UnionPirexGlpStrategy.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {Helper} from "./Helper.t.sol";

contract UnionPirexGlpStakingTest is Helper {
    event SetDistributor(address distributor);
    event Staked(uint256 amount);
    event Withdrawn(uint256 amount);
    event RewardPaid(address token, address receiver, uint256 reward);
    event Recovered(address token, uint256 amount);

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
        @param  etherAmount               uint80  Ether amount for GLP deposit
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
        @param  etherAmount               uint80  Ether amount for GLP deposit
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

        // Expected earned should equal proportionately to the current balance (decimals expanded)
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

    /*//////////////////////////////////////////////////////////////
                            getReward TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test claiming main vault reward
        @param  etherAmount     uint80  Ether amount for GLP deposit
        @param  rewardAmount    uint80  Reward amount (in pxGLP)
        @param  secondsElapsed  uint32  Seconds to forward timestamp after notify reward
     */
    function testGetReward(
        uint80 etherAmount,
        uint80 rewardAmount,
        uint32 secondsElapsed
    ) external {
        vm.assume(etherAmount > 0.001 ether);
        vm.assume(etherAmount < 1_000 ether);
        vm.assume(rewardAmount > 1e10);
        vm.assume(rewardAmount < 10000e18);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);

        // Populate a deposit record so we will have non-zero totalSupply for the staking contract
        vm.deal(address(this), etherAmount);

        pirexGmxGlp.depositGlpWithETH{value: etherAmount}(
            1,
            address(this),
            true
        );

        // Mint and accrue some test rewards then trigger notifyReward
        _mintPx(address(unionPirexGlpStrategy), rewardAmount, false);

        unionPirexGlpStrategy.notifyReward();

        vm.warp(block.timestamp + secondsElapsed);

        address vault = unionPirexGlpStrategy.vault();

        // Expected reward amount should be based on the current rewardPerToken value and total staked supply
        uint256 expectedRewardAmount = (unionPirexGlpStrategy.totalSupply() *
            unionPirexGlpStrategy.rewardPerToken(address(pxGlp))) / 1e18;
        uint256 preClaimPxGlpBalance = pxGlp.balanceOf(vault);

        vm.expectEmit(
            false,
            false,
            false,
            true,
            address(unionPirexGlpStrategy)
        );

        emit RewardPaid(address(pxGlp), vault, expectedRewardAmount);

        unionPirexGlpStrategy.getReward();

        assertGt(expectedRewardAmount, 0);
        assertEq(
            pxGlp.balanceOf(vault),
            preClaimPxGlpBalance + expectedRewardAmount
        );

        // Also assert the update reward state after claiming
        assertEq(unionPirexGlpStrategy.rewards(address(pxGlp), vault), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            getExtraReward TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test claiming extra token reward
        @param  etherAmount               uint80  Ether amount for GLP deposit
        @param  secondsElapsedForDeposit  uint32  Seconds to forward timestamp after deposit
        @param  secondsElapsedForReward   uint32  Seconds to forward timestamp after notify reward
     */
    function testGetExtraReward(
        uint80 etherAmount,
        uint32 secondsElapsedForDeposit,
        uint32 secondsElapsedForReward
    ) external {
        // Testing extra token rewards (pxGMX) requires full setup for actually accruing rewards from GMX
        _setupForRewardAndAccrue(
            etherAmount,
            secondsElapsedForDeposit,
            secondsElapsedForReward,
            true
        );

        vm.warp(block.timestamp + secondsElapsedForReward);

        address account = address(this);

        // Expected reward amount should be based on the current rewardPerToken value and the user's vault shares
        uint256 expectedRewardAmount = (unionPirexGlp.balanceOf(account) *
            unionPirexGlpStrategy.rewardPerToken(address(pxGmx))) / 1e18;
        uint256 preClaimPxGmxBalance = pxGmx.balanceOf(account);

        vm.expectEmit(
            false,
            false,
            false,
            true,
            address(unionPirexGlpStrategy)
        );

        emit RewardPaid(address(pxGmx), account, expectedRewardAmount);

        unionPirexGlpStrategy.getExtraReward();

        assertGt(expectedRewardAmount, 0);
        assertEq(
            pxGmx.balanceOf(account),
            preClaimPxGmxBalance + expectedRewardAmount
        );

        // Also assert the update reward state after claiming
        assertEq(unionPirexGlpStrategy.rewards(address(pxGmx), account), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            recoverERC20 TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to caller not being owner
     */
    function testCannotRecoverERC20Unauthorized() external {
        address tokenAddress = address(this);
        uint256 tokenAmount = 1;

        vm.prank(testAccounts[0]);

        vm.expectRevert("UNAUTHORIZED");

        unionPirexGlpStrategy.recoverERC20(tokenAddress, tokenAmount);
    }

    /**
        @notice Test tx reversion if tokenAddress is zero
     */
    function testCannotRecoverERC20ZeroAddress() external {
        address invalidTokenAddress = address(0);
        uint256 tokenAmount = 1;

        vm.expectRevert(UnionPirexGlpStaking.ZeroAddress.selector);

        unionPirexGlpStrategy.recoverERC20(invalidTokenAddress, tokenAmount);
    }

    /**
        @notice Test tx reversion if tokenAddress is any of the reward tokens
     */
    function testCannotRecoverERC20InvalidToken() external {
        address invalidTokenAddress1 = address(pxGmx);
        address invalidTokenAddress2 = address(pxGlp);
        uint256 tokenAmount = 1;

        vm.expectRevert(UnionPirexGlpStaking.InvalidToken.selector);

        unionPirexGlpStrategy.recoverERC20(invalidTokenAddress1, tokenAmount);

        vm.expectRevert(UnionPirexGlpStaking.InvalidToken.selector);

        unionPirexGlpStrategy.recoverERC20(invalidTokenAddress2, tokenAmount);
    }

    /**
        @notice Test tx reversion if tokenAmount is zero
     */
    function testCannotRecoverERC20ZeroAmount() external {
        address tokenAddress = address(this);
        uint256 invalidTokenAmount = 0;

        vm.expectRevert(UnionPirexGlpStaking.ZeroAmount.selector);

        unionPirexGlpStrategy.recoverERC20(tokenAddress, invalidTokenAmount);
    }

    /**
        @notice Test recovering ERC20 tokens
     */
    function testRecoverERC20() external {
        uint256 tokenAmount = 100e8;
        address tokenAddress = address(GMX);
        address strategy = address(unionPirexGlpStrategy);
        address owner = unionPirexGlpStrategy.owner();

        // Mint test tokens and transfer it to the strategy before attempting to recover it
        _mintGmx(tokenAmount);

        ERC20(address(GMX)).transfer(strategy, tokenAmount);

        uint256 preRecoverGmxBalanceOwner = GMX.balanceOf(owner);
        uint256 preRecoverGmxBalanceStrategy = GMX.balanceOf(strategy);

        vm.expectEmit(
            false,
            false,
            false,
            true,
            address(unionPirexGlpStrategy)
        );

        emit Recovered(tokenAddress, tokenAmount);

        unionPirexGlpStrategy.recoverERC20(tokenAddress, tokenAmount);

        assertEq(GMX.balanceOf(owner), preRecoverGmxBalanceOwner + tokenAmount);
        assertEq(
            GMX.balanceOf(strategy),
            preRecoverGmxBalanceStrategy - tokenAmount
        );
    }
}
