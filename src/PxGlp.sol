// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";

contract PxGlp is ERC20("Pirex GLP", "pxGLP", 18), AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    error ZeroAddress();

    /**
        @param  owner  address  Pirex-GMX multisig
    */
    constructor(address owner) {
        if (owner == address(0)) revert ZeroAddress();

        _setupRole(DEFAULT_ADMIN_ROLE, owner);
    }

    /**
        @notice Mint pxGLP
        @param  to      address  Account receiving pxGLP
        @param  amount  uint256  Amount of pxGLP
    */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();

        _mint(to, amount);
    }
}
