// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {PirexRewards} from "src/PirexRewards.sol";

contract PxGmx is ERC20("Pirex GMX", "pxGMX", 18), AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    PirexRewards public pirexRewards;

    event SetPirexRewards(address pirexRewards);

    error ZeroAddress();
    error ZeroAmount();

    /**
        @param  _pirexRewards  address  PirexRewards contract address
    */
    constructor(address _pirexRewards) {
        if (_pirexRewards == address(0)) revert ZeroAddress();

        pirexRewards = PirexRewards(_pirexRewards);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
        @notice Set PirexRewards contract
        @param  _pirexRewards  address  PirexRewards contract address
     */
    function setPirexRewards(address _pirexRewards)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_pirexRewards == address(0)) revert ZeroAddress();

        pirexRewards = PirexRewards(_pirexRewards);

        emit SetPirexRewards(_pirexRewards);
    }

    /**
        @notice Mint pxGMX
        @param  to      address  Account receiving pxGMX
        @param  amount  uint256  Amount of pxGMX
    */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _mint(to, amount);

        // Accrue global and user rewards and store post-mint supply for future accrual
        pirexRewards.globalAccrue(this);
        pirexRewards.userAccrue(this, to);
    }

    /**
        @notice Called by the balancer holder to transfer to another account
        @param  to      address  Account receiving pxGMX
        @param  amount  uint256  Amount of pxGMX
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
        pirexRewards.userAccrue(this, msg.sender);
        pirexRewards.userAccrue(this, to);

        return true;
    }

    /**
        @notice Called by an account with a spending allowance to transfer to another account
        @param  from    address  Account sending pxGMX
        @param  to      address  Account receiving pxGMX
        @param  amount  uint256  Amount of pxGMX
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

        pirexRewards.userAccrue(this, from);
        pirexRewards.userAccrue(this, to);

        return true;
    }
}
