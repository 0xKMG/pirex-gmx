// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {PxERC20} from "src/PxERC20.sol";
import {Helper} from "./Helper.sol";

contract PxGlpTest is Helper {
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
            _encodeRoleError(invalidCaller, pxGlp.DEFAULT_ADMIN_ROLE())
        );
        vm.prank(invalidCaller);

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
        address invalidCaller = testAccounts[0];
        address to = address(this);
        uint256 amount = 1;

        vm.expectRevert(_encodeRoleError(invalidCaller, pxGlp.MINTER_ROLE()));
        vm.prank(invalidCaller);

        pxGlp.mint(to, amount);
    }

    /**
        @notice Test tx success: mint pxGLP
        @param  amount  uint224  Amount to mint
     */
    function testMint(uint224 amount) external {
        vm.assume(amount != 0);

        address to = address(this);
        uint256 expectedPreMintBalance = 0;

        assertEq(expectedPreMintBalance, pxGlp.balanceOf(to));

        vm.prank(address(pirexGmx));
        vm.expectEmit(true, true, false, true, address(pxGlp));

        emit Transfer(address(0), to, amount);

        pxGlp.mint(to, amount);

        uint256 expectedPostMintBalance = expectedPreMintBalance + amount;

        assertEq(expectedPostMintBalance, pxGlp.balanceOf(to));
    }

    /*//////////////////////////////////////////////////////////////
                        burn TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller does not have the burner role
     */
    function testCannotBurnNoBurnerRole() external {
        address invalidCaller = testAccounts[0];
        address from = address(this);
        uint256 amount = 1;

        vm.expectRevert(_encodeRoleError(invalidCaller, pxGlp.BURNER_ROLE()));
        vm.prank(invalidCaller);

        pxGlp.burn(from, amount);
    }

    /**
        @notice Test tx success: burn pxGLP
        @param  amount  uint224  Amount to burn
     */
    function testBurn(uint224 amount) external {
        vm.assume(amount != 0);

        address from = address(this);

        vm.startPrank(address(pirexGmx));

        // Mint tokens which will be burned
        pxGlp.mint(from, amount);

        uint256 expectedPreBurnBalance = amount;

        assertEq(expectedPreBurnBalance, pxGlp.balanceOf(from));

        vm.expectEmit(true, true, false, true, address(pxGlp));

        emit Transfer(from, address(0), amount);

        pxGlp.burn(from, amount);

        vm.stopPrank();

        uint256 expectedPostBurnBalance = expectedPreBurnBalance - amount;

        assertEq(expectedPostBurnBalance, pxGlp.balanceOf(from));
    }
}
