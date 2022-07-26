// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {FlywheelCore} from "./rewards/FlywheelCore.sol";

contract PxGlp is ERC20("Pirex GLP", "pxGLP", 18), AccessControl {
    FlywheelCore public immutable flywheelCore;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    error ZeroAddress();
    error ZeroAmount();

    /**
        @param  owner          address       Pirex-GMX multisig
        @param  _flywheelCore  FlywheelCore  FlywheelCore contract address
    */
    constructor(address owner, FlywheelCore _flywheelCore) {
        if (owner == address(0)) revert ZeroAddress();
        if (address(_flywheelCore) == address(0)) revert ZeroAddress();

        flywheelCore = _flywheelCore;

        _setupRole(DEFAULT_ADMIN_ROLE, owner);
    }

    /**
        @notice Mint pxGLP
        @param  to      address  Account receiving pxGLP
        @param  amount  uint256  Amount of pxGLP
    */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _mint(to, amount);

        // Kick off reward accrual
        flywheelCore.accrue(this, to);
    }

    /**
        @notice Burn pxGLP
        @param  from    address  Account owning the pxGLP to be burned
        @param  amount  uint256  Amount of pxGLP
    */
    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (from == address(0)) revert ZeroAddress();

        _burn(from, amount);
    }
}
