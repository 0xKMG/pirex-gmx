// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {PxGmx} from "src/PxGmx.sol";
import {Helper} from "./Helper.t.sol";

contract PxGmxTest is Helper {
    /*//////////////////////////////////////////////////////////////
                            setPirexRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller does not have the admin role
     */
    function testCannotSetPirexRewardsNoAdminRole() external {
        address _pirexRewards = address(this);
        address caller = testAccounts[0];

        vm.expectRevert(_encodeRoleError(caller, pxGmx.DEFAULT_ADMIN_ROLE()));

        vm.startPrank(caller);

        pxGmx.setPirexRewards(_pirexRewards);
    }

    /**
        @notice Test tx success: set pirexRewards
     */
    function testSetPirexRewards() external {
        address _pirexRewards = address(this);

        assertTrue(_pirexRewards != address(pxGmx.pirexRewards()));

        vm.expectEmit(false, false, false, true, address(pxGmx));

        emit SetPirexRewards(_pirexRewards);

        pxGmx.setPirexRewards(_pirexRewards);

        assertEq(_pirexRewards, address(pxGmx.pirexRewards()));
    }

    /*//////////////////////////////////////////////////////////////
                        mint TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller does not have the minter role
     */
    function testCannotMintNoMinterRole() external {
        address to = address(this);
        uint256 amount = 1;

        vm.expectRevert(_encodeRoleError(address(this), pxGmx.MINTER_ROLE()));

        pxGmx.mint(to, amount);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotMintToZeroAddress() external {
        address invalidTo = address(0);
        uint256 amount = 1;

        vm.expectRevert(PxGmx.ZeroAddress.selector);

        vm.prank(address(pirexGmx));

        pxGmx.mint(invalidTo, amount);
    }

    /**
        @notice Test tx reversion: amount is zero
     */
    function testCannotMintToZeroAmount() external {
        address to = address(this);
        uint256 invalidAmount = 0;

        vm.expectRevert(PxGmx.ZeroAmount.selector);

        vm.prank(address(pirexGmx));

        pxGmx.mint(to, invalidAmount);
    }

    /**
        @notice Test tx success: mint pxGMX
        @param  amount  uint256  Amount to mint
     */
    function testMint(uint256 amount) external {
        vm.assume(amount != 0);

        address to = address(this);
        uint256 premintBalance = pxGmx.balanceOf(address(this));

        assertEq(premintBalance, 0);

        vm.prank(address(pirexGmx));

        pxGmx.mint(to, amount);

        assertEq(pxGmx.balanceOf(address(this)) - premintBalance, amount);
    }
}
