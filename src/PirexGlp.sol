// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {IRewardRouterV2} from "./interface/IRewardRouterV2.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract PirexGlp is ERC4626 {
    IRewardRouterV2 constant REWARD_ROUTER_V2 =
        IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    ERC20 constant FS_GLP = ERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);

    constructor() ERC4626(FS_GLP, "PirexGLP", "pxGLP") {}

    /**
        @notice Total underlying GLP assets managed by Pirex
        @return uint256  Contract GLP balance
     */
    function totalAssets() public view override returns (uint256) {
        return FS_GLP.balanceOf(address(this));
    }
}
