// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IRewardRouterV2} from "./interfaces/IRewardRouterV2.sol";
import {Vault} from "./external/Vault.sol";
import {PxGlp} from "./PxGlp.sol";

contract PirexGlp is ReentrancyGuard {
    using SafeTransferLib for ERC20;

    IRewardRouterV2 public constant REWARD_ROUTER_V2 =
        IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    ERC20 public constant FS_GLP =
        ERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    Vault public constant VAULT =
        Vault(0x489ee077994B6658eAfA855C308275EAd8097C4A);

    address public constant GLP_MANAGER =
        0x321F653eED006AD1C29D174e17d96351BDe22649;

    PxGlp public immutable pxGlp;

    event Deposit(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 minShares,
        uint256 amount,
        uint256 assets
    );

    event Redeem(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 minRedemption,
        uint256 amount,
        uint256 redemption
    );

    error ZeroAmount();
    error ZeroAddress();
    error InvalidToken(address token);

    /**
        @param  _pxGlp  address  PxGlp contract address
    */
    constructor(address _pxGlp) {
        if (_pxGlp == address(0)) revert ZeroAddress();

        pxGlp = PxGlp(_pxGlp);
    }

    /**
        @notice Deposit ETH for pxGLP
        @param  minShares  uint256  Minimum amount of pxGLP
        @param  receiver   address  Recipient of pxGLP
        @return assets     uint256  Amount of pxGLP
     */
    function depositWithETH(uint256 minShares, address receiver)
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
        pxGlp.mint(receiver, assets);

        emit Deposit(
            msg.sender,
            receiver,
            address(0),
            minShares,
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
        @return assets       uint256  Amount of pxGLP
     */
    function depositWithERC20(
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

        pxGlp.mint(receiver, assets);

        emit Deposit(msg.sender, receiver, token, minShares, tokenAmount, assets);
    }

    /**
        @notice Redeem back ETH from pxGLP
        @param  amount         uint256  Amount of pxGLP
        @param  minRedemption  uint256  Minimum amount of ETH to be redeemed
        @param  receiver       address  Recipient of the redeemed ETH
        @return redeemed       uint256  Amount of ETH received
     */
    function redeemForETH(
        uint256 amount,
        uint256 minRedemption,
        address receiver
    ) external nonReentrant returns (uint256 redeemed) {
        if (amount == 0) revert ZeroAmount();
        if (minRedemption == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Burn pxGLP before unstaking the underlying GLP
        pxGlp.burn(receiver, amount);

        // Unstake and redeem the underlying GLP for ETH
        redeemed = REWARD_ROUTER_V2.unstakeAndRedeemGlpETH(
            amount,
            minRedemption,
            receiver
        );

        emit Redeem(
            msg.sender,
            receiver,
            address(0),
            minRedemption,
            amount,
            redeemed
        );
    }

    /**
        @notice Redeem back any of the whitelisted ERC20 tokens from pxGLP
        @param  token          address  GMX-whitelisted token to be redeemed
        @param  amount         uint256  Amount of pxGLP
        @param  minRedemption  uint256  Minimum amount of token to be redeemed
        @param  receiver       address  Recipient of the redeemed token
        @return redeemed       uint256  Amount of token received
     */
    function redeemForERC20(
        address token,
        uint256 amount,
        uint256 minRedemption,
        address receiver
    ) external nonReentrant returns (uint256 redeemed) {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (minRedemption == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (!VAULT.whitelistedTokens(token)) revert InvalidToken(token);

        // Burn pxGLP before unstaking the underlying GLP
        pxGlp.burn(receiver, amount);

        // Unstake and redeem the underlying GLP for ERC20 token
        redeemed = REWARD_ROUTER_V2.unstakeAndRedeemGlp(
            token,
            amount,
            minRedemption,
            receiver
        );

        emit Redeem(
            msg.sender,
            receiver,
            token,
            minRedemption,
            amount,
            redeemed
        );
    }
}
