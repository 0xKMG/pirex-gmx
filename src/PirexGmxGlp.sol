// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {Pausable} from "openzeppelin-contracts/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IRewardRouterV2} from "./interfaces/IRewardRouterV2.sol";
import {Vault} from "./external/Vault.sol";
import {PxGlp} from "./PxGlp.sol";
import {PxGmx} from "./PxGmx.sol";
import {PirexRewards} from "./PirexRewards.sol";

contract PirexGmxGlp is ReentrancyGuard, Owned, Pausable {
    using SafeTransferLib for ERC20;

    // Miscellaneous dependency contracts (e.g. GMX) and addresses
    IRewardRouterV2 public constant REWARD_ROUTER_V2 =
        IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    Vault public constant VAULT =
        Vault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    address public constant GLP_MANAGER =
        0x321F653eED006AD1C29D174e17d96351BDe22649;
    ERC20 public constant GMX =
        ERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    ERC20 public constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    // Pirex token contract(s)
    PxGmx public immutable pxGmx;
    PxGlp public immutable pxGlp;

    // Pirex reward module contract
    address public pirexRewards;

    event SetPirexRewards(address pirexRewards);
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
    event InitiateMigration(address newContract);
    event CompleteMigration(address oldContract);

    error ZeroAmount();
    error ZeroAddress();
    error InvalidToken(address token);
    error NotPirexRewards();

    /**
        @param  _pxGmx         address  PxGmx contract address
        @param  _pxGlp         address  PxGlp contract address
        @param  _pirexRewards  address  PirexRewards contract address
        @param  stakedGmx      address  StakedGmx contract address
    */
    constructor(
        address _pxGmx,
        address _pxGlp,
        address _pirexRewards,
        address stakedGmx
    ) Owned(msg.sender) {
        // Started as being paused, and should only be unpaused after correctly setup
        _pause();

        if (_pxGmx == address(0)) revert ZeroAddress();
        if (_pxGlp == address(0)) revert ZeroAddress();
        if (_pirexRewards == address(0)) revert ZeroAddress();
        if (stakedGmx == address(0)) revert ZeroAddress();

        pxGmx = PxGmx(_pxGmx);
        pxGlp = PxGlp(_pxGlp);
        pirexRewards = _pirexRewards;

        // Pre-approving stakedGmx contract for staking GMX on behalf of our vault
        GMX.safeApprove(stakedGmx, type(uint256).max);
    }

    /**
        @notice Set pirexRewards
        @param  _pirexRewards  address  PirexRewards contract address
     */
    function setPirexRewards(address _pirexRewards) external onlyOwner {
        if (_pirexRewards == address(0)) revert ZeroAddress();

        pirexRewards = _pirexRewards;

        emit SetPirexRewards(_pirexRewards);
    }

    /**
        @notice Deposit and stake GMX for pxGMX
        @param  gmxAmount  uint256  GMX amount
        @param  receiver   address  Recipient of pxGMX
     */
    function depositGmx(uint256 gmxAmount, address receiver)
        external
        whenNotPaused
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
        whenNotPaused
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
    ) external whenNotPaused nonReentrant returns (uint256 assets) {
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
    ) external whenNotPaused nonReentrant returns (uint256 redeemed) {
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
    ) external whenNotPaused nonReentrant returns (uint256 redeemed) {
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
        @return producerTokens  ERC20[]    Producer tokens (pxGLP and pxGMX)
        @return rewardTokens    ERC20[]    Reward token contract instances
        @return rewardAmounts   uint256[]  Reward amounts from each producerToken
     */
    function claimWETHRewards()
        external
        returns (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        )
    {
        if (msg.sender != pirexRewards) revert NotPirexRewards();

        // @NOTE: Need to improve once more producer and reward tokens are added
        producerTokens = new ERC20[](1);
        rewardTokens = new ERC20[](1);
        rewardAmounts = new uint256[](1);

        // Set the addresses of the px tokens responsible for the rewards
        producerTokens[0] = pxGlp;

        // Currently, not useful but this method will be generalized to handle other rewards
        rewardTokens[0] = WETH;

        // Necessary for calculating the exact amount received from GMX
        uint256 wethBalanceBefore = WETH.balanceOf(address(this));

        // Claim only WETH rewards to keep gas to a minimum - may change in generalized version
        REWARD_ROUTER_V2.handleRewards(
            false,
            false,
            false,
            false,
            false,
            true,
            false
        );

        uint256 wethRewards = WETH.balanceOf(address(this)) - wethBalanceBefore;

        if (wethRewards != 0) {
            rewardAmounts[0] = wethRewards;

            WETH.safeTransfer(msg.sender, wethRewards);
        }
    }

    /**
        @notice Claim and stake all available multiplier points
     */
    function compoundMultiplierPoints() external whenNotPaused {
        REWARD_ROUTER_V2.handleRewards(
            false,
            false,
            false,
            false,
            true,
            false,
            false
        );
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY/MIGRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /** 
        @notice Set the contract's pause state
        @param state  bool  Pause state
    */
    function setPauseState(bool state) external onlyOwner {
        if (state) {
            _pause();
        } else {
            _unpause();
        }
    }

    /** 
        @notice Initiate contract migration (called by the old contract)
    */
    function initiateMigration(address newContract)
        external
        whenPaused
        onlyOwner
    {
        if (newContract == address(0)) revert ZeroAddress();

        // Notify the reward router that the current/old contract is going to perform
        // full account transfer to the specified new contract
        REWARD_ROUTER_V2.signalTransfer(newContract);

        emit InitiateMigration(newContract);
    }

    /** 
        @notice Complete contract migration (called by the new contract)
    */
    function completeMigration(address oldContract)
        external
        whenPaused
        onlyOwner
    {
        if (oldContract == address(0)) revert ZeroAddress();

        // Trigger harvest to claim remaining rewards before the account transfer
        PirexRewards(pirexRewards).harvest();

        // Complete the full account transfer process
        REWARD_ROUTER_V2.acceptTransfer(oldContract);

        emit CompleteMigration(oldContract);
    }
}
