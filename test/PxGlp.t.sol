// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {PxGlp} from "src/PxGlp.sol";
import {Helper} from "./Helper.t.sol";

contract PxGlpTest is Helper {
    /*//////////////////////////////////////////////////////////////
                            setPirexRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller does not have the admin role
     */
    function testCannotSetPirexRewardsNoAdminRole() external {
        address _pirexRewards = address(this);
        address caller = testAccounts[0];

        vm.expectRevert(_encodeRoleError(caller, pxGlp.DEFAULT_ADMIN_ROLE()));

        vm.startPrank(caller);

        pxGlp.setPirexRewards(_pirexRewards);
    }

    /**
        @notice Test tx success: set pirexRewards
     */
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
        @notice Test tx reversion: caller does not have the minter role
     */
    function testCannotMintNoMinterRole() external {
        address to = address(this);
        uint256 amount = 1;

        vm.expectRevert(_encodeRoleError(address(this), pxGlp.MINTER_ROLE()));

        pxGlp.mint(to, amount);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotMintToZeroAddress() external {
        address invalidTo = address(0);
        uint256 amount = 1;

        vm.expectRevert(PxGlp.ZeroAddress.selector);

        vm.prank(address(pirexGmxGlp));

        pxGlp.mint(invalidTo, amount);
    }

    /**
        @notice Test tx reversion: amount is zero
     */
    function testCannotMintToZeroAmount() external {
        address to = address(this);
        uint256 invalidAmount = 0;

        vm.expectRevert(PxGlp.ZeroAmount.selector);

        vm.prank(address(pirexGmxGlp));

        pxGlp.mint(to, invalidAmount);
    }

    /**
        @notice Test tx success: mint pxGLP
        @param  amount  224  Amount to mint
     */
    function testMint(uint224 amount) external {
        vm.assume(amount != 0);

        address to = address(this);
        uint256 premintBalance = pxGlp.balanceOf(to);

        assertEq(premintBalance, 0);

        vm.prank(address(pirexGmxGlp));

        pxGlp.mint(to, amount);

        assertEq(pxGlp.balanceOf(to) - premintBalance, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        burn TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller does not have the minter role
     */
    function testCannotBurnNoMinterRole() external {
        address from = address(this);
        uint256 amount = 1;

        vm.expectRevert(_encodeRoleError(address(this), pxGlp.MINTER_ROLE()));

        pxGlp.burn(from, amount);
    }

    /**
        @notice Test tx reversion: from is zero address
     */
    function testCannotBurnFromZeroAddress() external {
        address invalidFrom = address(0);
        uint256 amount = 1;

        vm.expectRevert(PxGlp.ZeroAddress.selector);

        vm.prank(address(pirexGmxGlp));

        pxGlp.burn(invalidFrom, amount);
    }

    /**
        @notice Test tx reversion: amount is zero
     */
    function testCannotBurnWithZeroAmount() external {
        address from = address(this);
        uint256 invalidAmount = 0;

        vm.expectRevert(PxGlp.ZeroAmount.selector);

        vm.prank(address(pirexGmxGlp));

        pxGlp.burn(from, invalidAmount);
    }

    /**
        @notice Test tx success: burn pxGLP
        @param  amount  uint224  Amount to burn
     */
    function testBurn(uint224 amount) external {
        vm.assume(amount != 0);

        address account = address(this);

        vm.startPrank(address(pirexGmxGlp));

        // Mint first before attempting to burn
        pxGlp.mint(account, amount);

        uint256 preburnBalance = pxGlp.balanceOf(account);

        assertEq(preburnBalance, amount);

        pxGlp.burn(account, amount);

        vm.stopPrank();

        assertEq(preburnBalance - pxGlp.balanceOf(address(this)), amount);
    }
}
