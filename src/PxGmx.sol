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
    }
}
