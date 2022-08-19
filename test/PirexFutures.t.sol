// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexFutures} from "src/PirexFutures.sol";
import {Helper} from "./Helper.t.sol";

contract PirexFuturesTest is Helper {
    event MintYield(
        bool indexed useGmx,
        uint256 indexed durationIndex,
        uint256 periods,
        uint256 assets,
        address indexed receiver,
        uint256[] tokenIds,
        uint256[] amounts
    );

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

    /**
        @notice Test minting yield
        @param  useGmx         bool     Use pxGMX
        @param  durationIndex  uint256  Duration index
        @param  assets         uint80   Amount of pxGMX or pxGLP
     */
    function testMintYield(
        bool useGmx,
        uint256 durationIndex,
        uint80 assets
    ) external {
        vm.assume(durationIndex < 4);
        vm.assume(assets != 0);
        vm.assume(assets < 10000e18);

        // Test starting period and the subsequent one
        uint256 periods = 2;

        address receiver = testAccounts[0];

        _mintPx(address(this), assets, useGmx);

        ERC20 producerToken = useGmx
            ? ERC20(address(pxGmx))
            : ERC20(address(pxGlp));
        uint256 pxBalanceBeforeMint = producerToken.balanceOf(address(this));

        producerToken.approve(address(pirexFutures), assets);

        uint256 startingExpiry = pirexFutures.getExpiry(durationIndex);
        uint256 duration = pirexFutures.durations(durationIndex);
        uint256[] memory expectedTokenIds = new uint256[](periods);
        uint256[] memory expectedAmounts = new uint256[](periods);
        expectedTokenIds[0] = startingExpiry;
        expectedTokenIds[1] = startingExpiry + duration;
        expectedAmounts[0] =
            assets *
            ((startingExpiry - block.timestamp) /
                pirexFutures.durations(durationIndex));
        expectedAmounts[1] = assets;

        vm.expectEmit(true, true, true, true, address(pirexFutures));

        // This is an assertion on the minted yield token ids and amounts
        emit MintYield(
            useGmx,
            durationIndex,
            periods,
            assets,
            receiver,
            expectedTokenIds,
            expectedAmounts
        );

        pirexFutures.mintYield(
            useGmx,
            durationIndex,
            periods,
            assets,
            receiver
        );

        uint256 pxBalanceAfterMint = producerToken.balanceOf(address(this));

        assertEq(pxBalanceBeforeMint - assets, pxBalanceAfterMint);
    }
}
