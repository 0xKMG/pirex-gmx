// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {PirexFutures} from "src/PirexFutures.sol";
import {Helper} from "./Helper.t.sol";

contract PirexFuturesTest is Helper {
    /*//////////////////////////////////////////////////////////////
                            getExpiry TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx: get expiry timestamp for a 30-day duration
    */
    function testGetExpiryFor30DayDuration() external {
        uint256 index = 0;
        uint256 expectedTimestamp = _getExpiry(index);

        assertEq(expectedTimestamp, pirexFutures.getExpiry(index));
    }

    /**
        @notice Test tx: get expiry timestamp for a 90-day duration
    */
    function testGetExpiryFor90DayDuration() external {
        uint256 index = 1;
        uint256 expectedTimestamp = _getExpiry(index);

        assertEq(expectedTimestamp, pirexFutures.getExpiry(index));
    }

    /**
        @notice Test tx: get expiry timestamp for a 180-day duration
    */
    function testGetExpiryFor180DayDuration() external {
        uint256 index = 2;
        uint256 expectedTimestamp = _getExpiry(index);

        assertEq(expectedTimestamp, pirexFutures.getExpiry(index));
    }

    /**
        @notice Test tx: get expiry timestamp for a 360-day duration
    */
    function testGetExpiryFor360DayDuration() external {
        uint256 index = 3;
        uint256 expectedTimestamp = _getExpiry(index);

        assertEq(expectedTimestamp, pirexFutures.getExpiry(index));
    }

    /*//////////////////////////////////////////////////////////////
                            mintYield TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice  Test tx reversion: periods is zero
    */
    function testCannotMintYieldPeriodsZeroAmount() external {
        bool useGmx = true;
        uint256 durationIndex = 0;
        uint256 invalidPeriods = 0;
        uint256 assets = 1;
        address receiver = address(this);

        vm.expectRevert(PirexFutures.ZeroAmount.selector);

        pirexFutures.mintYield(
            useGmx,
            durationIndex,
            invalidPeriods,
            assets,
            receiver
        );
    }

    /**
        @notice  Test tx reversion: assets is zero
    */
    function testCannotMintYieldAssetsZeroAmount() external {
        bool useGmx = true;
        uint256 durationIndex = 0;
        uint256 periods = 1;
        uint256 invalidAssets = 0;
        address receiver = address(this);

        vm.expectRevert(PirexFutures.ZeroAmount.selector);

        pirexFutures.mintYield(
            useGmx,
            durationIndex,
            periods,
            invalidAssets,
            receiver
        );
    }

    /**
        @notice  Test tx reversion: receiver is the zero address
    */
    function testCannotMintYieldReceiverZeroAddress() external {
        bool useGmx = true;
        uint256 durationIndex = 0;
        uint256 periods = 1;
        uint256 assets = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexFutures.ZeroAddress.selector);

        pirexFutures.mintYield(
            useGmx,
            durationIndex,
            periods,
            assets,
            invalidReceiver
        );
    }
}
