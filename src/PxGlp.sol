// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {FlywheelCore} from "./FlywheelCore.sol";

contract PxGlp is ERC20("Pirex GLP", "pxGLP", 18), AccessControl {
    FlywheelCore public immutable flywheelCore;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    error ZeroAddress();
    error ZeroAmount();

    /**
        @param  _flywheelCore  address  FlywheelCore contract address
    */
    constructor(address _flywheelCore) {
        if (_flywheelCore == address(0)) revert ZeroAddress();

        flywheelCore = FlywheelCore(_flywheelCore);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
        @notice Mint pxGLP
        @param  to      address  Account receiving pxGLP
        @param  amount  uint256  Amount of pxGLP
    */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // Update global accrued rewards state before new tokens added to supply
        flywheelCore.globalAccrue();

        _mint(to, amount);

        // Kick off reward accrual for user to snapshot post-mint balance
        flywheelCore.userAccrue(to);
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

    /**
        @notice Called by the balancer holder to transfer to another account
        @param  to      address  Account receiving pxGLP
        @param  amount  uint256  Amount of pxGLP
    */
    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        // Accrue rewards for sender, up to their current balance and kick off accrual for receiver
        flywheelCore.userAccrue(msg.sender);
        flywheelCore.userAccrue(to);

        return true;
    }

    /**
        @notice Called by an account with a spending allowance to transfer to another account
        @param  from    address  Account sending pxGLP
        @param  to      address  Account receiving pxGLP
        @param  amount  uint256  Amount of pxGLP
    */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        flywheelCore.userAccrue(from);
        flywheelCore.userAccrue(to);

        return true;
    }
}
