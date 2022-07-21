// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IRewardRouterV2} from "./interface/IRewardRouterV2.sol";
import {Vault} from "./external/Vault.sol";

contract PirexGlp is ReentrancyGuard, ERC4626 {
    using SafeTransferLib for ERC20;

    IRewardRouterV2 constant REWARD_ROUTER_V2 =
        IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    ERC20 constant FS_GLP = ERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    Vault constant VAULT = Vault(0x489ee077994B6658eAfA855C308275EAd8097C4A);

    address constant GLP_MANAGER = 0x321F653eED006AD1C29D174e17d96351BDe22649;

    event Mint(
        address indexed caller,
        uint256 indexed minShares,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 assets
    );

    error ZeroAmount();
    error ZeroAddress();
    error InvalidToken(address token);

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

        emit Mint(
            msg.sender,
            minShares,
            receiver,
            address(0),
            msg.value,
            assets
        );
    }

    /**
        @notice Deposit whitelisted ERC20 token for pxGLP
        @param  token        address  GMX-whitelisted token for buying GLP
        @param  tokenAmount  uint256  Whitelisted token amount
        @param  minShares    uint256  Minimum amount of pxGLP
        @param  receiver     address  Recipient of pxGLP
        @return assets       uint256  Amount of GLP minted and staked
     */
    function mintWithERC20(
        address token,
        uint256 tokenAmount,
        uint256 minShares,
        address receiver
    ) external nonReentrant returns (uint256 assets) {
        if (token == address(0)) revert ZeroAddress();
        if (tokenAmount == 0) revert ZeroAmount();
        if (minShares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (!VAULT.whitelistedTokens(token)) revert InvalidToken(token);

        ERC20 t = ERC20(token);

        // Intake user tokens and approve GLP Manager contract for amount
        t.safeTransferFrom(msg.sender, address(this), tokenAmount);
        t.safeApprove(GLP_MANAGER, tokenAmount);

        assets = REWARD_ROUTER_V2.mintAndStakeGlp(
            token,
            tokenAmount,
            0,
            minShares
        );

        _mint(receiver, assets);

        emit Mint(msg.sender, minShares, receiver, token, tokenAmount, assets);
    }
}
