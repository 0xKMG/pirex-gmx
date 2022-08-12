// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {PxGlp} from "src/PxGlp.sol";
import {Helper} from "./Helper.t.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract PxGlpTest is Helper {
    event SetPirexRewards(address pirexRewards);

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
            bytes(
                abi.encodePacked(
                    "AccessControl: account ",
                    Strings.toHexString(uint160(caller), 20),
                    " is missing role ",
                    Strings.toHexString(uint256(pxGlp.DEFAULT_ADMIN_ROLE()), 32)
                )
            )
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

        vm.prank(address(pirexGmxGlp));
        vm.expectRevert(PxGlp.ZeroAddress.selector);

        pxGlp.mint(invalidTo, amount);
    }

    /**
        @notice Test tx reversion due to amount being zero
     */
    function testCannotMintToZeroAmount() external {
        address to = address(this);
        uint256 invalidAmount = 0;

        vm.prank(address(pirexGmxGlp));
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
        uint256 premintBalance = pxGlp.balanceOf(to);

        vm.prank(address(pirexGmxGlp));

        pxGlp.mint(to, amount);

        assertEq(pxGlp.balanceOf(to) - premintBalance, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        burn TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to caller not having the minter role
     */
    function testCannotBurnNoMinterRole() external {
        address from = address(this);
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

        pxGlp.burn(from, amount);
    }

    /**
        @notice Test tx reversion due to to being the zero address
     */
    function testCannotBurnFromZeroAddress() external {
        address invalidFrom = address(0);
        uint256 amount = 1;

        vm.prank(address(pirexGmxGlp));
        vm.expectRevert(PxGlp.ZeroAddress.selector);

        pxGlp.burn(invalidFrom, amount);
    }

    /**
        @notice Test tx reversion due to amount being zero
     */
    function testCannotBurnWithZeroAmount() external {
        address from = address(this);
        uint256 invalidAmount = 0;

        vm.prank(address(pirexGmxGlp));
        vm.expectRevert(PxGlp.ZeroAmount.selector);

        pxGlp.burn(from, invalidAmount);
    }

    /**
        @notice Test burning pxGLP
        @param  amount  uint256  Amount to burn
     */
    function testBurn(uint256 amount) external {
        vm.assume(amount != 0);

        address account = address(this);

        vm.startPrank(address(pirexGmxGlp));

        // Mint first before attempting to burn
        pxGlp.mint(account, amount);

        uint256 preburnBalance = pxGlp.balanceOf(account);

        pxGlp.burn(account, amount);

        vm.stopPrank();

        assertEq(preburnBalance - pxGlp.balanceOf(address(this)), amount);
    }
}
