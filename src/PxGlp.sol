// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {PxERC20} from "src/PxERC20.sol";

contract PxGlp is PxERC20 {
    /**
        @param  _pirexRewards  address  PirexRewards contract address
        @param  _name          address  Token name (e.g. Pirex GLP)
        @param  _symbol        address  Token symbol (e.g. pxGLP)
        @param  _decimals      address  Token decimals (e.g. 18)
    */
    constructor(
        address _pirexRewards,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) PxERC20(_pirexRewards, _name, _symbol, _decimals) {}
}
