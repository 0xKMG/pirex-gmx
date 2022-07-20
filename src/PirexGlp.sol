// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {IRewardRouterV2} from "./interface/IRewardRouterV2.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract PirexGlp is ReentrancyGuard, ERC4626 {
    IRewardRouterV2 constant REWARD_ROUTER_V2 =
        IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    ERC20 constant FS_GLP = ERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);

    event Mint(
        address indexed caller,
        uint256 indexed minShares,
        address indexed receiver,
        uint256 assets
    );

    error ZeroAmount();
    error ZeroAddress();

    constructor() ERC4626(FS_GLP, "PirexGLP", "pxGLP") {}

    /**
        @notice Total underlying GLP assets managed by Pirex
        @return uint256  Contract GLP balance
     */
    function totalAssets() public view override returns (uint256) {
        return FS_GLP.balanceOf(address(this));
    }

    /**
        @notice Deposit ETH for pxGLP
        @param  minShares  uint256  Minimum amount of pxGLP
        @param  receiver   address  Recipient of pxGLP
        @return assets     uint256  Amount of GLP minted and staked
     */
    function mintWithETH(uint256 minShares, address receiver)
        external
        payable
        nonReentrant
        returns (uint256 assets)
    {
        if (msg.value == 0) revert ZeroAmount();
        if (minShares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Buy GLP with the user's ETH, specifying the minimum amount of GLP
        assets = REWARD_ROUTER_V2.mintAndStakeGlpETH{value: msg.value}(
            0,
            minShares
        );

        // Mint pxGLP based on the actual amount of GLP minted
        _mint(receiver, assets);

        emit Mint(msg.sender, minShares, receiver, assets);
    }
}
