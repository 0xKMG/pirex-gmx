// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {PxGmx} from "src/tokens/PxGmx.sol";
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

        vm.startPrank(caller);
        vm.expectRevert(
            _encodeRoleError(caller, pxGmx.DEFAULT_ADMIN_ROLE())
        );

        pxGlp.setPirexRewards(_pirexRewards);
    }

    function testSetPirexRewards() external {
        address _pirexRewards = address(this);

        assertTrue(_pirexRewards != address(pxGlp.pirexRewards()));

        vm.expectEmit(false, false, false, true, address(pxGlp));

        emit SetPirexRewards(_pirexRewards);

        pxGlp.setPirexRewards(_pirexRewards);

        assertEq(_pirexRewards, address(pxGlp.pirexRewards()));
    }

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
            _encodeRoleError(address(this), pxGmx.MINTER_ROLE())
        );

        pxGmx.mint(to, amount);
    }

    /**
        @notice Test tx reversion due to to being the zero address
     */
    function testCannotMintToZeroAddress() external {
        address invalidTo = address(0);
        uint256 amount = 1;

        vm.prank(address(pirexGmxGlp));
        vm.expectRevert(PxGmx.ZeroAddress.selector);

        pxGmx.mint(invalidTo, amount);
    }

    /**
        @notice Test tx reversion due to amount being zero
     */
    function testCannotMintToZeroAmount() external {
        address to = address(this);
        uint256 invalidAmount = 0;

        vm.prank(address(pirexGmxGlp));
        vm.expectRevert(PxGmx.ZeroAmount.selector);

        pxGmx.mint(to, invalidAmount);
    }

    /**
        @notice Test minting pxGMX
        @param  amount  uint256  Amount to mint
     */
    function testMint(uint256 amount) external {
        vm.assume(amount != 0);

        address to = address(this);
        uint256 premintBalance = pxGmx.balanceOf(address(this));

        vm.prank(address(pirexGmxGlp));

        pxGmx.mint(to, amount);

        assertEq(pxGmx.balanceOf(address(this)) - premintBalance, amount);
    }
}
