// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {UnionPirexGlp} from "src/vaults/UnionPirexGlp.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {Helper} from "./Helper.t.sol";

contract UnionPirexGlpTest is Helper {
    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event PlatformUpdated(address indexed platform);
    event StrategySet(address indexed strategy);

    /**
        @notice Common setup for deposit and accruing reward
     */
    function _setupForReward(
        uint80 etherAmount,
        uint80 rewardAmount,
        uint32 secondsElapsed
    ) internal returns (uint256) {
        // Deposit into the UnionPirex to populate the assets
        vm.assume(etherAmount > 0.001 ether);
        vm.assume(etherAmount < 1_000 ether);
        vm.assume(rewardAmount > 1e10);
        vm.assume(rewardAmount < 10000e18);
        vm.assume(secondsElapsed > 1 hours);
        vm.assume(secondsElapsed < 365 days);

        vm.deal(address(this), etherAmount);

        uint256 assets = pirexGmxGlp.depositGlpWithETH{value: etherAmount}(
            1,
            address(this),
            true
        );

        // Mint and accrue some test rewards before testing totalAssets
        _mintPx(address(unionPirexGlpStrategy), rewardAmount, false);

        unionPirexGlpStrategy.notifyReward();

        vm.warp(block.timestamp + secondsElapsed);

        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                        setWithdrawalPenalty TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to penalty exceeding the max limit
     */
    function testCannotSetWithdrawalPenaltyExceedsMax() external {
        uint256 invalidPenalty = unionPirexGlp.MAX_WITHDRAWAL_PENALTY() + 1;

        vm.expectRevert(UnionPirexGlp.ExceedsMax.selector);

        unionPirexGlp.setWithdrawalPenalty(invalidPenalty);
    }

    /**
        @notice Test setting withdrawal penalty
        @param  penalty  uint256  Withdrawal penalty
     */
    function testSetWithdrawalPenalty(uint256 penalty) external {
        vm.assume(penalty <= unionPirexGlp.MAX_WITHDRAWAL_PENALTY());

        vm.expectEmit(false, false, false, true, address(unionPirexGlp));

        emit WithdrawalPenaltyUpdated(penalty);

        unionPirexGlp.setWithdrawalPenalty(penalty);

        assertEq(unionPirexGlp.withdrawalPenalty(), penalty);
    }

    /*//////////////////////////////////////////////////////////////
                        setPlatformFee TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to platform fee exceeding the max limit
     */
    function testCannotSetPlatformFeeExceedsMax() external {
        uint256 invalidFee = unionPirexGlp.MAX_PLATFORM_FEE() + 1;

        vm.expectRevert(UnionPirexGlp.ExceedsMax.selector);

        unionPirexGlp.setPlatformFee(invalidFee);
    }

    /**
        @notice Test setting platform fee
        @param  platformFee  uint256  Platform fee
     */
    function testSetPlatformFee(uint256 platformFee) external {
        vm.assume(platformFee <= unionPirexGlp.MAX_PLATFORM_FEE());

        vm.expectEmit(false, false, false, true, address(unionPirexGlp));

        emit PlatformFeeUpdated(platformFee);

        unionPirexGlp.setPlatformFee(platformFee);

        assertEq(unionPirexGlp.platformFee(), platformFee);
    }

    /*//////////////////////////////////////////////////////////////
                        setPlatform TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to platform being zero address
     */
    function testCannotSetPlatformZeroAddress() external {
        address invalidPlatform = address(0);

        vm.expectRevert(UnionPirexGlp.ZeroAddress.selector);

        unionPirexGlp.setPlatform(invalidPlatform);
    }

    /**
        @notice Test setting platform
     */
    function testSetPlatform() external {
        address platform = address(this);

        vm.expectEmit(false, false, false, true, address(unionPirexGlp));

        emit PlatformUpdated(platform);

        unionPirexGlp.setPlatform(platform);

        assertEq(unionPirexGlp.platform(), platform);
    }

    /*//////////////////////////////////////////////////////////////
                        setStrategy TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to strategy being zero address
     */
    function testCannotSetStrategyZeroAddress() external {
        address invalidStrategy = address(0);

        vm.expectRevert(UnionPirexGlp.ZeroAddress.selector);

        unionPirexGlp.setStrategy(invalidStrategy);
    }

    /**
        @notice Test tx reversion after strategy has already been set once
     */
    function testCannotSetStrategyAlreadySet() external {
        // Need a newly deployed version to test setStrategy
        UnionPirexGlp mockUnionPirexGlp = new UnionPirexGlp(address(pxGlp));

        address strategy = address(this);
        address newStrategy = address(this);

        mockUnionPirexGlp.setStrategy(strategy);

        assertEq(address(mockUnionPirexGlp.strategy()), strategy);

        vm.expectRevert(UnionPirexGlp.AlreadySet.selector);

        mockUnionPirexGlp.setStrategy(newStrategy);
    }

    /**
        @notice Test setting strategy
     */
    function testSetStrategy() external {
        // Need a newly deployed version to test setStrategy
        UnionPirexGlp mockUnionPirexGlp = new UnionPirexGlp(address(pxGlp));

        assertEq(address(mockUnionPirexGlp.strategy()), address(0));

        address strategy = address(this);

        vm.expectEmit(false, false, false, true, address(mockUnionPirexGlp));

        emit StrategySet(strategy);

        mockUnionPirexGlp.setStrategy(strategy);

        assertEq(address(mockUnionPirexGlp.strategy()), strategy);
    }

    /*//////////////////////////////////////////////////////////////
                        totalAssets TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test calculating total assets
        @param  etherAmount  uint80  Ether amount
     */
    function testTotalAssets(uint80 etherAmount) external {
        // Deposit into the UnionPirex to populate the assets
        vm.assume(etherAmount > 0.001 ether);
        vm.assume(etherAmount < 1_000 ether);

        vm.deal(address(this), etherAmount);

        uint256 assets = pirexGmxGlp.depositGlpWithETH{value: etherAmount}(
            1,
            address(this),
            true
        );

        assertEq(unionPirexGlp.totalAssets(), assets);
    }

    /**
        @notice Test calculating total assets with rewards
        @param  etherAmount     uint80  Ether amount
        @param  rewardAmount    uint80  Reward amount
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testTotalAssetsWithReward(
        uint80 etherAmount,
        uint80 rewardAmount,
        uint32 secondsElapsed
    ) external {
        uint256 assets = _setupForReward(
            etherAmount,
            rewardAmount,
            secondsElapsed
        );

        (uint256 _totalSupply, uint256 rewards) = unionPirexGlpStrategy
            .totalSupplyWithRewards();
        uint256 platformFee = unionPirexGlp.platformFee();
        uint256 feeDenom = unionPirexGlp.FEE_DENOMINATOR();
        uint256 totalAssets = unionPirexGlp.totalAssets();

        assertGt(totalAssets, assets);
        assertEq(_totalSupply, assets);
        assertEq(
            totalAssets,
            _totalSupply + rewards - ((rewards * platformFee) / feeDenom)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        harvest TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test harvest
        @param  etherAmount     uint80  Ether amount
        @param  rewardAmount    uint80  Reward amount
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testHarvest(
        uint80 etherAmount,
        uint80 rewardAmount,
        uint32 secondsElapsed
    ) external {
        uint256 assets = _setupForReward(
            etherAmount,
            rewardAmount,
            secondsElapsed
        );

        (uint256 totalSupply, uint256 rewards) = unionPirexGlpStrategy
            .totalSupplyWithRewards();
        uint256 platformFee = unionPirexGlp.platformFee();
        address platform = unionPirexGlp.platform();
        uint256 feeDenom = unionPirexGlp.FEE_DENOMINATOR();
        uint256 feeAmount = (rewards * platformFee) / feeDenom;
        uint256 pxGlpPlatformBalance = pxGlp.balanceOf(platform);

        assertEq(totalSupply, assets);
        assertGt(rewards, 0);

        unionPirexGlp.harvest();

        // Validate balances and supply after harvest
        (
            uint256 postHarvestTotalSupply,
            uint256 postHarvestRewards
        ) = unionPirexGlpStrategy.totalSupplyWithRewards();

        assertGt(postHarvestTotalSupply, totalSupply);
        assertEq(postHarvestTotalSupply, totalSupply + rewards - feeAmount);
        assertEq(postHarvestRewards, 0);
        assertEq(pxGlp.balanceOf(platform), pxGlpPlatformBalance + feeAmount);
    }
}
