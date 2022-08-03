// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IRewardRouterV2} from "./interfaces/IRewardRouterV2.sol";
import {IRewardTracker} from "./interfaces/IRewardTracker.sol";
import {Vault} from "./external/Vault.sol";
import {PxGlp} from "./PxGlp.sol";
import {PxGmx} from "./PxGmx.sol";

contract PirexGmxGlp is ReentrancyGuard {
    using SafeTransferLib for ERC20;

    // GMX contracts and addresses
    IRewardRouterV2 public constant REWARD_ROUTER_V2 =
        IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    IRewardTracker public constant REWARD_TRACKER_GMX =
        IRewardTracker(0xd2D1162512F927a7e282Ef43a362659E4F2a728F);
    IRewardTracker public constant REWARD_TRACKER_GLP =
        IRewardTracker(0x4e971a87900b931fF39d1Aad67697F49835400b6);
    Vault public constant VAULT =
        Vault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    address public constant GLP_MANAGER =
        0x321F653eED006AD1C29D174e17d96351BDe22649;
    ERC20 public constant GMX =
        ERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    ERC20 public constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    // Pirex token contracts
    PxGmx public immutable pxGmx;
    PxGlp public immutable pxGlp;

    // Mutability subject to change
    address public immutable pxGlpRewards;

    event DepositGmx(
        address indexed caller,
        address indexed receiver,
        uint256 amount
    );

    event DepositGlp(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 minShares,
        uint256 amount,
        uint256 assets
    );

    event RedeemGlp(
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
    error NotPxGlpRewards();

    /**
        @param  _pxGmx         address  PxGmx contract address
        @param  _pxGlp         address  PxGlp contract address
        @param  _pxGlpRewards  address  PxGlpRewards contract address
        @param  _stakedGmx     address  StakedGmx contract address
    */
    constructor(
        address _pxGmx,
        address _pxGlp,
        address _pxGlpRewards,
        address _stakedGmx
    ) {
        if (_pxGmx == address(0)) revert ZeroAddress();
        if (_pxGlp == address(0)) revert ZeroAddress();
        if (_pxGlpRewards == address(0)) revert ZeroAddress();

        pxGmx = PxGmx(_pxGmx);
        pxGlp = PxGlp(_pxGlp);
        pxGlpRewards = _pxGlpRewards;

        // Pre-approving stakedGmx contract for staking GMX on behalf of our vault
        GMX.safeApprove(_stakedGmx, type(uint256).max);
    }

    /**
        @notice Deposit and stake GMX for pxGMX
        @param  gmxAmount  uint256  GMX amount
        @param  receiver   address  Recipient of pxGMX
     */
    function depositGmx(uint256 gmxAmount, address receiver)
        external
        nonReentrant
    {
        if (gmxAmount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Transfer the caller's GMX before staking
        GMX.safeTransferFrom(msg.sender, address(this), gmxAmount);

        REWARD_ROUTER_V2.stakeGmx(gmxAmount);

        // Mint pxGMX equal to the specified amount of GMX
        pxGmx.mint(receiver, gmxAmount);

        emit DepositGmx(msg.sender, receiver, gmxAmount);
    }

    /**
        @notice Deposit ETH for pxGLP
        @param  minShares  uint256  Minimum amount of GLP
        @param  receiver   address  Recipient of pxGLP
        @return assets     uint256  Amount of pxGLP
     */
    function depositGlpWithETH(uint256 minShares, address receiver)
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

        emit DepositGlp(
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
        @param  minShares    uint256  Minimum amount of GLP
        @param  receiver     address  Recipient of pxGLP
        @return assets       uint256  Amount of pxGLP
     */
    function depositGlpWithERC20(
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

        emit DepositGlp(
            msg.sender,
            receiver,
            token,
            minShares,
            tokenAmount,
            assets
        );
    }

    /**
        @notice Redeem back ETH from pxGLP
        @param  amount         uint256  Amount of pxGLP
        @param  minRedemption  uint256  Minimum amount of ETH to be redeemed
        @param  receiver       address  Recipient of the redeemed ETH
        @return redeemed       uint256  Amount of ETH received
     */
    function redeemPxGlpForETH(
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

        emit RedeemGlp(
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
    function redeemPxGlpForERC20(
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

        emit RedeemGlp(
            msg.sender,
            receiver,
            token,
            minRedemption,
            amount,
            redeemed
        );
    }

    /**
        @notice Claim WETH rewards
        @return fromGmx  uint256  WETH earned from staked GMX and esGMX
        @return fromGlp  uint256  WETH earned from staked GLP
        @return weth     uint256  WETH transferred
     */
    function claimWETHRewards()
        external
        returns (
            uint256 fromGmx,
            uint256 fromGlp,
            uint256 weth
        )
    {
        // Restrict call to pxGlpRewards since it is the rewards receiver
        // Additionally, the WETH amount may need to be synced with reward points
        if (msg.sender != pxGlpRewards) revert NotPxGlpRewards();

        // Retrieve the WETH reward amounts for each reward-producing token
        fromGmx = REWARD_TRACKER_GMX.claimable(address(this));
        fromGlp = REWARD_TRACKER_GLP.claimable(address(this));

        uint256 wethBalanceBefore = WETH.balanceOf(address(this));

        // Claim only WETH rewards to keep gas to a minimum
        REWARD_ROUTER_V2.handleRewards(
            false,
            false,
            false,
            false,
            false,
            true,
            false
        );

        uint256 fromGmxGlp = fromGmx + fromGlp;

        if (fromGmxGlp != 0) {
            // Recalculate fromGmx/Glp since the WETH amount received may differ
            weth = WETH.balanceOf(address(this)) - wethBalanceBefore;
            fromGmx = (weth * fromGmx) / fromGmxGlp;
            fromGlp = (weth * fromGlp) / fromGmxGlp;

            // Check above ensures that msg.sender is pxGlpRewards
            WETH.safeTransfer(msg.sender, weth);
        }
    }
}
