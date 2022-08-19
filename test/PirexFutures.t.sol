// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {Helper} from "./Helper.t.sol";

contract PirexFutures is Helper {
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
}
