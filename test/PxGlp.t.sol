// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {PxGlp} from "src/PxGlp.sol";
import {Helper} from "./Helper.t.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract PxGlpTest is Helper {
    /*//////////////////////////////////////////////////////////////
                        mint TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to caller not having the minter role
     */
    function testCannotMintNoMinterRole() external {
        address to = address(this);
        uint256 amount = 1;

        vm.expectRevert(
            bytes(
                abi.encodePacked(
                    "AccessControl: account ",
                    Strings.toHexString(uint160(address(this)), 20),
                    " is missing role ",
                    Strings.toHexString(uint256(pxGlp.MINTER_ROLE()), 32)
                )
            )
        );

        pxGlp.mint(to, amount);
    }

    /**
        @notice Test tx reversion due to to being the zero address
     */
    function testCannotMintToZeroAddress() external {
        address invalidTo = address(0);
        uint256 amount = 1;

        vm.prank(address(pirexGlp));
        vm.expectRevert(PxGlp.ZeroAddress.selector);

        pxGlp.mint(invalidTo, amount);
    }

    /**
        @notice Test tx reversion due to amount being zero
     */
    function testCannotMintToZeroAmount() external {
        address to = address(this);
        uint256 invalidAmount = 0;

        vm.prank(address(pirexGlp));
        vm.expectRevert(PxGlp.ZeroAmount.selector);

        pxGlp.mint(to, invalidAmount);
    }

    /**
        @notice Test minting pxGLP
        @param  amount  uint256  Amount to mint
     */
    function testMint(uint256 amount) external {
        vm.assume(amount != 0);

        address to = address(this);
        uint256 premintBalance = pxGlp.balanceOf(address(this));
        uint224 userIndexBefore = flywheelCore.userIndex(pxGlp, to);

        assertEq(userIndexBefore, 0);

        vm.prank(address(pirexGlp));

        pxGlp.mint(to, amount);

        // Check whether the user index has updated (i.e. accrue was called)
        (uint224 index, ) = flywheelCore.strategyState(pxGlp);
        uint224 userIndexAfter = flywheelCore.userIndex(pxGlp, to);

        assertEq(userIndexAfter, index);
        assertEq(pxGlp.balanceOf(address(this)) - premintBalance, amount);
    }
}
