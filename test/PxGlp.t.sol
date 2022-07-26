// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {PxGlp} from "src/PxGlp.sol";
import {Helper} from "./Helper.t.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract PxGlpTest is Test, Helper {
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
        @notice Test minting pxGLP
        @param  amount  uint256  Amount to mint
     */
    function testMint(uint256 amount) external {
        address to = address(this);
        uint256 premintBalance = pxGlp.balanceOf(address(this));

        vm.prank(address(pirexGlp));

        pxGlp.mint(to, amount);

        assertEq(pxGlp.balanceOf(address(this)) - premintBalance, amount);
    }
}
