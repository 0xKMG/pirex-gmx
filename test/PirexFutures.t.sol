// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexFutures} from "src/futures/PirexFutures.sol";
import {PirexFuturesVault} from "src/futures/PirexFuturesVault.sol";
import {ERC1155PresetMinterSupply} from "src/tokens/ERC1155PresetMinterSupply.sol";
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
                            getMaturity TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx: get maturity timestamp for a 30-day duration
    */
    function testGetMaturityFor30DayDuration() external {
        uint256 index = 0;
        uint256 expectedTimestamp = _calculateMaturity(index);

        assertEq(expectedTimestamp, pirexFutures.getMaturity(index));
    }

    /**
        @notice Test tx: get maturity timestamp for a 90-day duration
    */
    function testGetMaturityFor90DayDuration() external {
        uint256 index = 1;
        uint256 expectedTimestamp = _calculateMaturity(index);

        assertEq(expectedTimestamp, pirexFutures.getMaturity(index));
    }

    /**
        @notice Test tx: get maturity timestamp for a 180-day duration
    */
    function testGetMaturityFor180DayDuration() external {
        uint256 index = 2;
        uint256 expectedTimestamp = _calculateMaturity(index);

        assertEq(expectedTimestamp, pirexFutures.getMaturity(index));
    }

    /**
        @notice Test tx: get maturity timestamp for a 360-day duration
    */
    function testGetMaturityFor360DayDuration() external {
        uint256 index = 3;
        uint256 expectedTimestamp = _calculateMaturity(index);

        assertEq(expectedTimestamp, pirexFutures.getMaturity(index));
    }

    /*//////////////////////////////////////////////////////////////
                            mintYield TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice  Test tx reversion: assets is zero
    */
    function testCannotMintYieldAssetsZeroAmount() external {
        bool useGmx = true;
        uint256 durationIndex = 0;
        uint256 invalidAssets = 0;
        address receiver = address(this);

        vm.expectRevert(PirexFutures.ZeroAmount.selector);

        pirexFutures.mintYield(useGmx, durationIndex, invalidAssets, receiver);
    }

    /**
        @notice  Test tx reversion: receiver is the zero address
    */
    function testCannotMintYieldReceiverZeroAddress() external {
        bool useGmx = true;
        uint256 durationIndex = 0;
        uint256 assets = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexFutures.ZeroAddress.selector);

        pirexFutures.mintYield(useGmx, durationIndex, assets, invalidReceiver);
    }

    // /**
    //     @notice Test minting yield
    //     @param  useGmx         bool     Use pxGMX
    //     @param  durationIndex  uint256  Duration index
    //     @param  assets         uint80   Amount of pxGMX or pxGLP
    //  */
    // function testMintYield(
    //     bool useGmx,
    //     uint256 durationIndex,
    //     uint80 assets
    // ) external {
    //     vm.assume(durationIndex < 4);
    //     vm.assume(assets != 0);
    //     vm.assume(assets < 10000e18);
    // function testMintYield() external {
    //     bool useGmx = true;
    //     uint256 durationIndex = 0;
    //     uint80 assets = 1e18;

    //     address receiver = testAccounts[0];
    //     uint256 maturity = pirexFutures.getMaturity(durationIndex);

    //     // Check vault creation
    //     assertEq(address(0), pirexFutures.vaults(maturity));

    //     _mintPx(address(this), assets, useGmx);

    //     ERC20 producerToken = useGmx ? ERC20(pxGmx) : ERC20(pxGlp);
    //     uint256 pxBalanceBeforeMint = producerToken.balanceOf(address(this));

    //     producerToken.approve(address(pirexFutures), assets);

    //     uint256 duration = pirexFutures.durations(durationIndex);
    //     uint256 expectedYieldTokenAmount = assets *
    //         ((maturity - block.timestamp) / duration);

    //     // vm.expectEmit(true, true, true, true, address(pirexFutures));

    //     // // This is an assertion on the minted yield token ids and amounts
    //     // emit MintYield(
    //     //     useGmx,
    //     //     durationIndex,
    //     //     periods,
    //     //     assets,
    //     //     receiver,
    //     //     expectedTokenIds,
    //     //     expectedAmounts
    //     // );

    //     pirexFutures.mintYield(useGmx, durationIndex, assets, receiver);

    //     PirexFuturesVault vault = PirexFuturesVault(
    //         pirexFutures.vaults(maturity)
    //     );
    //     ERC1155PresetMinterSupply vaultAsset = vault.asset();
    //     ERC1155PresetMinterSupply vaultYield = vault.yield();
    //     uint256 pxBalanceAfterMint = producerToken.balanceOf(address(this));
    //     uint256 assetBalance = vaultAsset.balanceOf(receiver);

    //     assertEq(pxBalanceBeforeMint - assets, pxBalanceAfterMint);
    // }
}
