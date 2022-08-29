// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {UnionPirexGlp} from "src/vaults/UnionPirexGlp.sol";
import {Helper} from "./Helper.t.sol";

contract UnionPirexGlpTest is Helper {
    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event PlatformUpdated(address indexed platform);
    event StrategySet(address indexed strategy);

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
}
