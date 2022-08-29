// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {Pausable} from "openzeppelin-contracts/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IRewardRouterV2} from "src/interfaces/IRewardRouterV2.sol";
import {IRewardDistributor} from "src/interfaces/IRewardDistributor.sol";
import {RewardTracker} from "src/external/RewardTracker.sol";
import {Vault} from "src/external/Vault.sol";
import {UnionPirexGlp} from "src/vaults/UnionPirexGlp.sol";
import {PxGlp} from "src/PxGlp.sol";
import {PxGmx} from "src/PxGmx.sol";
import {PirexRewards} from "src/PirexRewards.sol";

contract PirexGmxGlp is ReentrancyGuard, Owned, Pausable {
    using SafeTransferLib for ERC20;

    // Miscellaneous dependency contracts (e.g. GMX) and addresses
    // @TODO: Add a compound method for updating any that may change
    IRewardRouterV2 public constant REWARD_ROUTER_V2 =
        IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    RewardTracker public constant REWARD_TRACKER_GMX =
        RewardTracker(0xd2D1162512F927a7e282Ef43a362659E4F2a728F);
    RewardTracker public constant REWARD_TRACKER_GLP =
        RewardTracker(0x4e971a87900b931fF39d1Aad67697F49835400b6);
    RewardTracker public constant FEE_STAKED_GLP =
        RewardTracker(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    RewardTracker public constant STAKED_GMX =
        RewardTracker(0x908C4D94D34924765f1eDc22A1DD098397c59dD4);
    Vault public constant GMX_VAULT =
        Vault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    address public constant GLP_MANAGER =
        0x321F653eED006AD1C29D174e17d96351BDe22649;
    ERC20 public constant GMX =
        ERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    ERC20 public constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    ERC20 public constant ESGMX =
        ERC20(0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA);

    // Pirex token contract(s)
    PxGmx public immutable pxGmx;
    PxGlp public immutable pxGlp;

    // Pirex reward module contract
    address public pirexRewards;

    // Union-Pirex contract(s)
    UnionPirexGlp public unionPirexGlp;

    event SetPirexRewards(address pirexRewards);
    event SetUnionPirexGlp(address unionPirexGlp);
    event DepositGmx(
        address indexed caller,
        address indexed receiver,
        uint256 amount
    );
    event DepositGlp(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        bool shouldCompound,
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
    event ClaimRewards(
        uint256 wethRewards,
        uint256 esGmxRewards,
        uint256 gmxWethRewards,
        uint256 glpWethRewards,
        uint256 gmxEsGmxRewards,
        uint256 glpEsGmxRewards
    );

    error ZeroAmount();
    error ZeroAddress();
    error InvalidToken(address token);
    error NotPirexRewards();
    error InvalidReward(address token);

    modifier onlyPirexRewards() {
        if (msg.sender != pirexRewards) revert NotPirexRewards();
        _;
    }

    /**
        @param  _pxGmx         address  PxGmx contract address
        @param  _pxGlp         address  PxGlp contract address
        @param  _pirexRewards  address  PirexRewards contract address
    */
    constructor(
        address _pxGmx,
        address _pxGlp,
        address _pirexRewards
    ) Owned(msg.sender) {
        // Started as being paused, and should only be unpaused after correctly setup
        _pause();

        if (_pxGmx == address(0)) revert ZeroAddress();
        if (_pxGlp == address(0)) revert ZeroAddress();
        if (_pirexRewards == address(0)) revert ZeroAddress();

        pxGmx = PxGmx(_pxGmx);
        pxGlp = PxGlp(_pxGlp);
        pirexRewards = _pirexRewards;

        // Pre-approving stakedGmx contract for staking GMX on behalf of our vault
        GMX.safeApprove(address(STAKED_GMX), type(uint256).max);
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
        @notice Set unionPirexGlp
        @param  _unionPirexGlp  address  UnionPirexGlp contract address
     */
    function setUnionPirexGlp(address _unionPirexGlp) external onlyOwner {
        if (_unionPirexGlp == address(0)) revert ZeroAddress();

        // Revoke approval from the old contract and approve the new contract
        ERC20 pxGlpERC20 = ERC20(address(pxGlp));
        address oldUnionPirexGlp = address(unionPirexGlp);

        if (oldUnionPirexGlp != address(0)) {
            pxGlpERC20.safeApprove(oldUnionPirexGlp, 0);
        }

        unionPirexGlp = UnionPirexGlp(_unionPirexGlp);
        pxGlpERC20.safeApprove(address(unionPirexGlp), type(uint256).max);

        emit SetUnionPirexGlp(_unionPirexGlp);
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
        @param  minShares       uint256  Minimum amount of GLP
        @param  receiver        address  Recipient of pxGLP
        @param  shouldCompound  bool     Whether to auto-compound
        @return assets          uint256  Amount of pxGLP
     */
    function depositGlpWithETH(
        uint256 minShares,
        address receiver,
        bool shouldCompound
    ) external payable whenNotPaused nonReentrant returns (uint256 assets) {
        if (msg.value == 0) revert ZeroAmount();
        if (minShares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Buy GLP with the user's ETH, specifying the minimum amount of GLP
        assets = REWARD_ROUTER_V2.mintAndStakeGlpETH{value: msg.value}(
            0,
            minShares
        );

        // Mint pxGLP based on the actual amount of GLP minted
        pxGlp.mint(shouldCompound ? address(this) : receiver, assets);

        if (shouldCompound) {
            // Transfer the minted pxGLP to the Union vault while the user receives the shares
            unionPirexGlp.deposit(assets, receiver);
        }

        emit DepositGlp(
            msg.sender,
            receiver,
            address(0),
            shouldCompound,
            minShares,
            msg.value,
            assets
        );
    }

    /**
        @notice Deposit whitelisted ERC20 token for pxGLP
        @param  token           address  GMX-whitelisted token for buying GLP
        @param  tokenAmount     uint256  Whitelisted token amount
        @param  minShares       uint256  Minimum amount of GLP
        @param  receiver        address  Recipient of pxGLP
        @param  shouldCompound  bool     Whether to auto-compound
        @return assets          uint256  Amount of pxGLP
     */
    function depositGlpWithERC20(
        address token,
        uint256 tokenAmount,
        uint256 minShares,
        address receiver,
        bool shouldCompound
    ) external whenNotPaused nonReentrant returns (uint256 assets) {
        if (token == address(0)) revert ZeroAddress();
        if (tokenAmount == 0) revert ZeroAmount();
        if (minShares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (!GMX_VAULT.whitelistedTokens(token)) revert InvalidToken(token);

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

        pxGlp.mint(shouldCompound ? address(this) : receiver, assets);

        if (shouldCompound) {
            // Transfer the minted pxGLP to the Union vault while the user receives the shares
            unionPirexGlp.deposit(assets, receiver);
        }

        emit DepositGlp(
            msg.sender,
            receiver,
            token,
            shouldCompound,
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
        if (!GMX_VAULT.whitelistedTokens(token)) revert InvalidToken(token);

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
        @notice Calculate the WETH/esGMX rewards for either GMX or GLP
        @param  isWeth  bool     Whether to calculate WETH or esGMX rewards
        @param  useGmx  bool     Whether the calculation should be for GMX
        @return         uint256  Amount of WETH/esGMX rewards
     */
    function calculateRewards(bool isWeth, bool useGmx)
        public
        view
        returns (uint256)
    {
        RewardTracker r;
        if (isWeth) {
            r = useGmx ? REWARD_TRACKER_GMX : REWARD_TRACKER_GLP;
        } else {
            r = useGmx ? STAKED_GMX : FEE_STAKED_GLP;
        }
        address distributor = r.distributor();
        uint256 pendingRewards = IRewardDistributor(distributor)
            .pendingRewards();
        ERC20 token = (isWeth ? WETH : ESGMX);
        uint256 distributorBalance = token.balanceOf(distributor);
        uint256 blockReward = pendingRewards > distributorBalance
            ? distributorBalance
            : pendingRewards;
        uint256 precision = r.PRECISION();
        uint256 _cumulativeRewardPerToken = r.cumulativeRewardPerToken() +
            ((blockReward * precision) / r.totalSupply());

        if (_cumulativeRewardPerToken == 0) {
            return 0;
        }

        return
            r.claimableReward(address(this)) +
            ((r.stakedAmounts(address(this)) *
                (_cumulativeRewardPerToken -
                    r.previousCumulatedRewardPerToken(address(this)))) /
                precision);
    }

    /**
        @notice Claim WETH/esGMX rewards
        @return producerTokens  ERC20[]    Producer tokens (pxGLP and pxGMX)
        @return rewardTokens    ERC20[]    Reward token contract instances
        @return rewardAmounts   uint256[]  Reward amounts from each producerToken
     */
    function claimRewards()
        external
        onlyPirexRewards
        returns (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        )
    {
        producerTokens = new ERC20[](4);
        rewardTokens = new ERC20[](4);
        rewardAmounts = new uint256[](4);
        producerTokens[0] = pxGmx;
        producerTokens[1] = pxGlp;
        producerTokens[2] = pxGmx;
        producerTokens[3] = pxGlp;
        rewardTokens[0] = WETH;
        rewardTokens[1] = WETH;
        rewardTokens[2] = ERC20(pxGmx); // esGMX rewards distributed as pxGMX
        rewardTokens[3] = ERC20(pxGmx);

        uint256 wethBeforeClaim = WETH.balanceOf(address(this));
        uint256 gmxWethRewards = calculateRewards(true, true);
        uint256 glpWethRewards = calculateRewards(true, false);

        uint256 esGmxBeforeClaim = STAKED_GMX.depositBalances(
            address(this),
            address(ESGMX)
        );
        uint256 gmxEsGmxRewards = calculateRewards(false, true);
        uint256 glpEsGmxRewards = calculateRewards(false, false);

        // Claim and stake claimable esGMX, while also claim WETH rewards
        REWARD_ROUTER_V2.handleRewards(
            false,
            false,
            true,
            true,
            false,
            true,
            false
        );

        uint256 wethRewards = WETH.balanceOf(address(this)) - wethBeforeClaim;
        uint256 esGmxRewards = STAKED_GMX.depositBalances(
            address(this),
            address(ESGMX)
        ) - esGmxBeforeClaim;

        if (wethRewards != 0) {
            // This may not be necessary and is more of a hedge against a discrepancy between
            // the actual rewards and the calculated amounts. Needs further consideration
            rewardAmounts[0] =
                (gmxWethRewards * wethRewards) /
                (gmxWethRewards + glpWethRewards);
            rewardAmounts[1] = wethRewards - rewardAmounts[0];
        }

        if (esGmxRewards != 0) {
            rewardAmounts[2] =
                (gmxEsGmxRewards * esGmxRewards) /
                (gmxEsGmxRewards + glpEsGmxRewards);
            rewardAmounts[3] = esGmxRewards - rewardAmounts[2];
        }

        emit ClaimRewards(
            wethRewards,
            esGmxRewards,
            gmxWethRewards,
            glpWethRewards,
            gmxEsGmxRewards,
            glpEsGmxRewards
        );
    }

    /**
        @notice Mint/transfer the specified reward token to the recipient
        @param  recipient           address  Recipient of the claim
        @param  rewardTokenAddress  address  Reward token address
        @param  rewardAmount        uint256  Reward amount
     */
    function claimUserReward(
        address recipient,
        address rewardTokenAddress,
        uint256 rewardAmount
    ) external onlyPirexRewards {
        if (rewardTokenAddress == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();

        if (rewardTokenAddress == address(pxGmx)) {
            // Distribute esGMX rewards as pxGMX
            pxGmx.mint(recipient, rewardAmount);
        } else if (rewardTokenAddress == address(WETH)) {
            // For WETH, we can directly transfer it
            WETH.safeTransfer(recipient, rewardAmount);
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
        @param  newContract  address  Address of the new contract
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
        @param  oldContract  address  Address of the old contract
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
