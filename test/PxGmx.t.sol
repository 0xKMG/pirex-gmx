// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {PxERC20} from "src/PxERC20.sol";
import {Helper} from "./Helper.sol";

contract PxGmxTest is Helper {
    /*//////////////////////////////////////////////////////////////
                            setPirexRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller does not have the admin role
     */
    function testCannotSetPirexRewardsNoAdminRole() external {
        address invalidCaller = testAccounts[0];
        address _pirexRewards = address(this);

        vm.expectRevert(
            _encodeRoleError(invalidCaller, pxGmx.DEFAULT_ADMIN_ROLE())
        );
        vm.prank(invalidCaller);

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
        address invalidCaller = testAccounts[0];
        address to = address(this);
        uint256 amount = 1;

        vm.expectRevert(_encodeRoleError(invalidCaller, pxGmx.MINTER_ROLE()));
        vm.prank(invalidCaller);

        pxGmx.mint(to, amount);
    }

    /**
        @notice Test tx success: mint pxGMX
        @param  amount  uint224  Amount to mint
     */
    function testMint(uint224 amount) external {
        vm.assume(amount != 0);

        address to = address(this);
        uint256 expectedPreMintBalance = 0;

        assertEq(expectedPreMintBalance, pxGmx.balanceOf(to));

        vm.prank(address(pirexGmx));
        vm.expectEmit(true, true, false, true, address(pxGmx));

        emit Transfer(address(0), to, amount);

        pxGmx.mint(to, amount);

        uint256 expectedPostMintBalance = expectedPreMintBalance + amount;

        assertEq(expectedPostMintBalance, pxGmx.balanceOf(to));
    }
}
