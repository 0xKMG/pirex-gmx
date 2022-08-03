// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {PxGlpRewards} from "./PxGlpRewards.sol";

contract PxGlp is ERC20("Pirex GLP", "pxGLP", 18), AccessControl {
    PxGlpRewards public immutable pxGlpRewards;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    error ZeroAddress();
    error ZeroAmount();

    /**
        @param  _pxGlpRewards  address  PxGlpRewards contract address
    */
    constructor(address _pxGlpRewards) {
        if (_pxGlpRewards == address(0)) revert ZeroAddress();

        pxGlpRewards = PxGlpRewards(_pxGlpRewards);

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

        // Update global reward accrual state before tokens are added to the supply
        pxGlpRewards.globalAccrue();

        _mint(to, amount);

        // Kick off reward accrual for user to snapshot post-mint balance
        pxGlpRewards.userAccrue(to);
    }

    /**
        @notice Burn pxGLP
        @param  from    address  Account owning the pxGLP to be burned
        @param  amount  uint256  Amount of pxGLP
    */
    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (from == address(0)) revert ZeroAddress();

        // Update global reward accrual state before tokens are removed from the supply
        pxGlpRewards.globalAccrue();

        _burn(from, amount);

        // Accrue user rewards and snapshot post-burn balance
        pxGlpRewards.userAccrue(from);
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
        pxGlpRewards.userAccrue(msg.sender);
        pxGlpRewards.userAccrue(to);

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

        pxGlpRewards.userAccrue(from);
        pxGlpRewards.userAccrue(to);

        return true;
    }
}
