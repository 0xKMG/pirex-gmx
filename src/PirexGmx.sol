// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {Pausable} from "openzeppelin-contracts/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IRewardRouterV2} from "src/interfaces/IRewardRouterV2.sol";
import {IRewardDistributor} from "src/interfaces/IRewardDistributor.sol";
import {IVault} from "src/interfaces/IVault.sol";
import {DelegateRegistry} from "src/external/DelegateRegistry.sol";
import {RewardTracker} from "src/external/RewardTracker.sol";
import {PxGmx} from "src/PxGmx.sol";
import {PxGlp} from "src/PxGlp.sol";
import {PirexFees} from "src/PirexFees.sol";
import {PirexRewards} from "src/PirexRewards.sol";

contract PirexGmx is ReentrancyGuard, Owned, Pausable {
    using SafeTransferLib for ERC20;

    // Configurable fees
    enum Fees {
        Deposit,
        Redemption,
        Reward
    }

    // Configurable external contracts
    enum Contracts {
        RewardRouterV2,
        RewardTrackerGmx,
        RewardTrackerGlp,
        FeeStakedGlp,
        StakedGmx,
        GmxVault,
        GlpManager
    }

    // External contracts which are extremely unlikely to change (e.g. protocol tokens)
    ERC20 public constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    ERC20 public constant GMX =
        ERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    ERC20 public constant ES_GMX =
        ERC20(0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA);

    // Dependency contracts which are modifiable by the contract owner
    IRewardRouterV2 public gmxRewardRouterV2 =
        IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    RewardTracker public rewardTrackerGmx =
        RewardTracker(0xd2D1162512F927a7e282Ef43a362659E4F2a728F);
    RewardTracker public rewardTrackerGlp =
        RewardTracker(0x4e971a87900b931fF39d1Aad67697F49835400b6);
    RewardTracker public feeStakedGlp =
        RewardTracker(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    RewardTracker public stakedGmx =
        RewardTracker(0x908C4D94D34924765f1eDc22A1DD098397c59dD4);
    IVault public gmxVault = IVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    address public glpManager = 0x321F653eED006AD1C29D174e17d96351BDe22649;

    // Fee denominator
    uint256 public constant FEE_DENOMINATOR = 1_000_000;

    // Fee maximum
    uint256 public constant FEE_MAX = 100_000;

    // Pirex token contract(s)
    PxGmx public immutable pxGmx;
    PxGlp public immutable pxGlp;
    PirexFees public immutable pirexFees;

    // Pirex reward module contract
    address public pirexRewards;

    // Snapshot delegation states
    DelegateRegistry public delegateRegistry;
    bytes32 public delegationSpace = bytes32("gmx.eth");

    // Fees (e.g. 5000 / 1000000 = 0.5%)
    mapping(Fees => uint256) public fees;

    event SetPirexRewards(address pirexRewards);
    event SetDelegateRegistry(address delegateRegistry);
    event SetFee(Fees indexed f, uint256 fee);
    event SetContract(Contracts indexed c, address contractAddress);
    event DepositGmx(
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 postFeeAmount,
        uint256 feeAmount
    );
    event DepositGlp(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 tokenAmount,
        uint256 minUsdg,
        uint256 minGlp,
        uint256 assets,
        uint256 postFeeAmount,
        uint256 feeAmount
    );
    event RedeemGlp(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 assets,
        uint256 minOut,
        uint256 redemption,
        uint256 postFeeAmount,
        uint256 feeAmount
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
    event SetDelegationSpace(string delegationSpace, bool shouldClear);
    event SetVoteDelegate(address voteDelegate);
    event ClearVoteDelegate();

    error ZeroAmount();
    error ZeroAddress();
    error InvalidToken(address token);
    error NotPirexRewards();
    error InvalidFee();
    error EmptyString();

    modifier onlyPirexRewards() {
        if (msg.sender != pirexRewards) revert NotPirexRewards();
        _;
    }

    /**
        @param  _pxGmx             address  PxGmx contract address
        @param  _pxGlp             address  PxGlp contract address
        @param  _pirexFees         address  PirexFees contract address
        @param  _pirexRewards      address  PirexRewards contract address
        @param  _delegateRegistry  address  Delegation registry contract address
    */
    constructor(
        address _pxGmx,
        address _pxGlp,
        address _pirexFees,
        address _pirexRewards,
        address _delegateRegistry
    ) Owned(msg.sender) {
        // Start the contract paused, to ensure contract set is properly configured
        _pause();

        if (_pxGmx == address(0)) revert ZeroAddress();
        if (_pxGlp == address(0)) revert ZeroAddress();
        if (_pirexFees == address(0)) revert ZeroAddress();
        if (_pirexRewards == address(0)) revert ZeroAddress();
        if (_delegateRegistry == address(0)) revert ZeroAddress();

        pxGmx = PxGmx(_pxGmx);
        pxGlp = PxGlp(_pxGlp);
        pirexFees = PirexFees(_pirexFees);
        pirexRewards = _pirexRewards;
        delegateRegistry = DelegateRegistry(_delegateRegistry);

        uint256 maxAmount = type(uint256).max;

        // Max approve various token balances to be externally transferred on our behalf
        WETH.safeApprove(_pirexFees, maxAmount);
        GMX.safeApprove(address(stakedGmx), maxAmount);
        ERC20(pxGmx).safeApprove(_pirexFees, maxAmount);
        ERC20(pxGlp).safeApprove(_pirexFees, maxAmount);
    }

    /**
        @notice Derive fee and post-fee asset amounts from a fee type and total asset amount
        @param  f           Fees     Fee type
        @param  amount      uint256  GMX/GLP/WETH amount
        @return userAmount  uint256  Post-fee user-related asset amount (mint/burn/claim/etc.)
        @return feeAmount   uint256  Fee amount
     */
    function _deriveAssetAmounts(Fees f, uint256 amount)
        internal
        view
        returns (uint256 userAmount, uint256 feeAmount)
    {
        feeAmount = (amount * fees[f]) / FEE_DENOMINATOR;
        userAmount = amount - feeAmount;

        // The sum of the fee and post-fee amounts should never exceed the total asset amount
        assert(feeAmount + userAmount == amount);
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
        @notice Set delegateRegistry
        @param  _delegateRegistry  address  DelegateRegistry contract address
     */
    function setDelegateRegistry(address _delegateRegistry) external onlyOwner {
        if (_delegateRegistry == address(0)) revert ZeroAddress();

        delegateRegistry = DelegateRegistry(_delegateRegistry);

        emit SetDelegateRegistry(_delegateRegistry);
    }

    /**
        @notice Set fee
        @param  f    enum     Fee
        @param  fee  uint256  Fee amount
     */
    function setFee(Fees f, uint256 fee) external onlyOwner {
        if (fee > FEE_MAX) revert InvalidFee();

        fees[f] = fee;

        emit SetFee(f, fee);
    }

    /**
        @notice Set a contract address
        @param  c                enum     Contracts
        @param  contractAddress  address  Contract address
     */
    function setContract(Contracts c, address contractAddress)
        external
        onlyOwner
    {
        if (contractAddress == address(0)) revert ZeroAddress();

        emit SetContract(c, contractAddress);

        if (c == Contracts.RewardRouterV2) {
            gmxRewardRouterV2 = IRewardRouterV2(contractAddress);
            return;
        }

        if (c == Contracts.RewardTrackerGmx) {
            rewardTrackerGmx = RewardTracker(contractAddress);
            return;
        }

        if (c == Contracts.RewardTrackerGlp) {
            rewardTrackerGlp = RewardTracker(contractAddress);
            return;
        }

        if (c == Contracts.FeeStakedGlp) {
            feeStakedGlp = RewardTracker(contractAddress);
            return;
        }

        if (c == Contracts.StakedGmx) {
            // Set the current stakedGmx (pending change) approval amount to 0
            GMX.safeApprove(address(stakedGmx), 0);

            stakedGmx = RewardTracker(contractAddress);

            // Approve the new stakedGmx contract address allowance to the max
            GMX.safeApprove(contractAddress, type(uint256).max);

            return;
        }

        if (c == Contracts.GmxVault) {
            gmxVault = IVault(contractAddress);
            return;
        }

        glpManager = contractAddress;
    }

    /**
        @notice Deposit GMX for pxGMX
        @param  assets         uint256  GMX amount
        @param  receiver       address  pxGMX receiver
        @return postFeeAmount  uint256  pxGMX minted for the receiver
        @return feeAmount      uint256  pxGMX distributed as fees
     */
    function depositGmx(uint256 assets, address receiver)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 postFeeAmount, uint256 feeAmount)
    {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Transfer the caller's GMX to this contract and stake it for rewards
        GMX.safeTransferFrom(msg.sender, address(this), assets);
        gmxRewardRouterV2.stakeGmx(assets);

        // Get the pxGMX amounts for the receiver and the protocol (fees)
        (postFeeAmount, feeAmount) = _deriveAssetAmounts(Fees.Deposit, assets);

        // Mint pxGMX for the receiver (excludes fees)
        pxGmx.mint(receiver, postFeeAmount);

        // Mint and distribute pxGMX for the protocol
        if (feeAmount != 0) {
            pxGmx.mint(address(this), feeAmount);
            pirexFees.distributeFees(address(this), address(pxGmx), feeAmount);
        }

        emit DepositGmx(msg.sender, receiver, assets, postFeeAmount, feeAmount);
    }

    /**
        @notice Deposit GLP for pxGLP
        @param  token        address  GMX-whitelisted token for minting GLP (optional)
        @param  tokenAmount  uint256  Token amount
        @param  minUsdg      uint256  Minimum USDG purchased and used to mint GLP
        @param  minGlp       uint256  Minimum GLP amount minted from tokens
        @param  receiver     address  pxGLP receiver
        @return assets       uint256  GLP amount
     */
    function _depositGlp(
        address token,
        uint256 tokenAmount,
        uint256 minUsdg,
        uint256 minGlp,
        address receiver
    ) internal returns (uint256 assets) {
        if (tokenAmount == 0) revert ZeroAmount();
        if (minUsdg == 0) revert ZeroAmount();
        if (minGlp == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        if (token == address(0)) {
            // Mint and stake GLP using ETH
            assets = gmxRewardRouterV2.mintAndStakeGlpETH{value: tokenAmount}(
                minUsdg,
                minGlp
            );
        } else {
            ERC20 t = ERC20(token);

            // Intake user ERC20 tokens and approve GLP Manager contract for amount
            t.safeTransferFrom(msg.sender, address(this), tokenAmount);
            t.safeApprove(glpManager, tokenAmount);

            // Mint and stake GLP using ERC20 tokens
            assets = gmxRewardRouterV2.mintAndStakeGlp(
                token,
                tokenAmount,
                minUsdg,
                minGlp
            );
        }

        // Calculate the post-fee and fee amounts based on the fee type and total assets
        (uint256 postFeeAmount, uint256 feeAmount) = _deriveAssetAmounts(
            Fees.Deposit,
            assets
        );

        // Mint pxGLP for the receiver
        pxGlp.mint(receiver, postFeeAmount);

        // Mint and distribute pxGLP for the protocol (fees)
        if (feeAmount != 0) {
            pxGlp.mint(address(this), feeAmount);
            pirexFees.distributeFees(address(this), address(pxGlp), feeAmount);
        }

        emit DepositGlp(
            msg.sender,
            receiver,
            token,
            tokenAmount,
            minUsdg,
            minGlp,
            assets,
            postFeeAmount,
            feeAmount
        );
    }

    /**
        @notice Deposit GLP (minted with ETH) for pxGLP
        @param  minUsdg   uint256  Minimum USDG purchased and used to mint GLP
        @param  minGlp    uint256  Minimum GLP amount minted from ETH
        @param  receiver  address  pxGLP receiver
        @return assets    uint256  GLP amount
     */
    function depositGlpETH(
        uint256 minUsdg,
        uint256 minGlp,
        address receiver
    ) external payable whenNotPaused nonReentrant returns (uint256 assets) {
        return _depositGlp(address(0), msg.value, minUsdg, minGlp, receiver);
    }

    /**
        @notice Deposit GLP (minted with ERC20 tokens) for pxGLP
        @param  token        address  GMX-whitelisted token for minting GLP
        @param  tokenAmount  uint256  Whitelisted token amount
        @param  minUsdg      uint256  Minimum USDG purchased and used to mint GLP
        @param  minGlp       uint256  Minimum GLP amount minted from ERC20 tokens
        @param  receiver     address  pxGLP receiver
        @return assets       uint256  GLP amount
     */
    function depositGlp(
        address token,
        uint256 tokenAmount,
        uint256 minUsdg,
        uint256 minGlp,
        address receiver
    ) external whenNotPaused nonReentrant returns (uint256 assets) {
        if (token == address(0)) revert ZeroAddress();
        if (!gmxVault.whitelistedTokens(token)) revert InvalidToken(token);

        return _depositGlp(token, tokenAmount, minUsdg, minGlp, receiver);
    }

    /**
        @notice Redeem pxGLP
        @param  token     address  GMX-whitelisted token to be redeemed (optional)
        @param  assets    uint256  pxGLP amount
        @param  minOut    uint256  Minimum token output from GLP redemption
        @param  receiver  address  Output token recipient
        @return redeemed  uint256  Output tokens from redeeming GLP
     */
    function _redeemPxGlp(
        address token,
        uint256 assets,
        uint256 minOut,
        address receiver
    ) internal returns (uint256 redeemed) {
        if (assets == 0) revert ZeroAmount();
        if (minOut == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Calculate the post-fee and fee amounts based on the fee type and total assets
        (uint256 postFeeAmount, uint256 feeAmount) = _deriveAssetAmounts(
            Fees.Redemption,
            assets
        );

        // Burn pxGLP before redeeming the underlying GLP
        pxGlp.burn(msg.sender, postFeeAmount);

        if (feeAmount != 0) {
            ERC20(pxGlp).safeTransferFrom(msg.sender, address(this), feeAmount);
            pirexFees.distributeFees(address(this), address(pxGlp), feeAmount);
        }

        // Unstake and redeem the underlying GLP for ERC20 tokens
        redeemed = token == address(0)
            ? gmxRewardRouterV2.unstakeAndRedeemGlpETH(
                postFeeAmount,
                minOut,
                receiver
            )
            : gmxRewardRouterV2.unstakeAndRedeemGlp(
                token,
                postFeeAmount,
                minOut,
                receiver
            );

        emit RedeemGlp(
            msg.sender,
            receiver,
            token,
            assets,
            minOut,
            redeemed,
            postFeeAmount,
            feeAmount
        );
    }

    /**
        @notice Redeem pxGLP for ETH from redeeming GLP
        @param  assets    uint256  pxGLP amount
        @param  minOut    uint256  Minimum ETH output from GLP redemption
        @param  receiver  address  ETH recipient
        @return redeemed  uint256  ETH redeemed from GLP
     */
    function redeemPxGlpETH(
        uint256 assets,
        uint256 minOut,
        address receiver
    ) external whenNotPaused nonReentrant returns (uint256 redeemed) {
        return _redeemPxGlp(address(0), assets, minOut, receiver);
    }

    /**
        @notice Redeem pxGLP for ERC20 tokens from redeeming GLP
        @param  token     address  GMX-whitelisted token to be redeemed
        @param  assets    uint256  pxGLP amount
        @param  minOut    uint256  Minimum ERC20 output from GLP redemption
        @param  receiver  address  ERC20 token recipient
        @return redeemed  uint256  ERC20 tokens from redeeming GLP
     */
    function redeemPxGlp(
        address token,
        uint256 assets,
        uint256 minOut,
        address receiver
    ) external whenNotPaused nonReentrant returns (uint256 redeemed) {
        if (token == address(0)) revert ZeroAddress();
        if (!gmxVault.whitelistedTokens(token)) revert InvalidToken(token);

        return _redeemPxGlp(token, assets, minOut, receiver);
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
            r = useGmx ? rewardTrackerGmx : rewardTrackerGlp;
        } else {
            r = useGmx ? stakedGmx : feeStakedGlp;
        }

        address distributor = r.distributor();
        uint256 pendingRewards = IRewardDistributor(distributor)
            .pendingRewards();
        uint256 distributorBalance = ERC20(isWeth ? WETH : ES_GMX).balanceOf(
            distributor
        );
        uint256 blockReward = pendingRewards > distributorBalance
            ? distributorBalance
            : pendingRewards;
        uint256 precision = r.PRECISION();
        uint256 cumulativeRewardPerToken = r.cumulativeRewardPerToken() +
            ((blockReward * precision) / r.totalSupply());

        if (cumulativeRewardPerToken == 0) return 0;

        return
            r.claimableReward(address(this)) +
            ((r.stakedAmounts(address(this)) *
                (cumulativeRewardPerToken -
                    r.previousCumulatedRewardPerToken(address(this)))) /
                precision);
    }

    /**
        @notice Claim WETH/esGMX rewards + multiplier points (MP)
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
        // Assign return values used by the PirexRewards contract
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

        // Get pre-reward claim reward token balances to calculate actual amount received
        uint256 wethBeforeClaim = WETH.balanceOf(address(this));
        uint256 esGmxBeforeClaim = stakedGmx.depositBalances(
            address(this),
            address(ES_GMX)
        );

        // Calculate the unclaimed reward token amounts produced for each token type
        uint256 gmxWethRewards = calculateRewards(true, true);
        uint256 glpWethRewards = calculateRewards(true, false);
        uint256 gmxEsGmxRewards = calculateRewards(false, true);
        uint256 glpEsGmxRewards = calculateRewards(false, false);

        // Claim and stake esGMX + MP, and claim WETH
        IRewardRouterV2(gmxRewardRouterV2).handleRewards(
            false,
            false,
            true,
            true,
            true,
            true,
            false
        );

        uint256 wethRewards = WETH.balanceOf(address(this)) - wethBeforeClaim;
        uint256 esGmxRewards = stakedGmx.depositBalances(
            address(this),
            address(ES_GMX)
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
        @notice Mint/transfer the specified reward token to the receiver
        @param  receiver  address  Reward receiver
        @param  token     address  Reward token address
        @param  amount    uint256  Reward amount
     */
    function claimUserReward(
        address receiver,
        address token,
        uint256 amount
    ) external onlyPirexRewards {
        if (token == address(0)) revert ZeroAddress();
        if (receiver == address(0)) revert ZeroAddress();
        if (amount == 0) return;

        (uint256 rewardAmount, uint256 feeAmount) = _deriveAssetAmounts(
            Fees.Reward,
            amount
        );
        address pxGmxAddress = address(pxGmx);

        if (token == pxGmxAddress) {
            // Mint pxGMX for the user - the analog for esGMX rewards
            pxGmx.mint(receiver, rewardAmount);
        } else if (token == address(WETH)) {
            WETH.safeTransfer(receiver, rewardAmount);
        }

        if (feeAmount != 0) {
            // Mint the fees portion of the esGMX rewards
            if (token == pxGmxAddress) pxGmx.mint(address(this), feeAmount);

            pirexFees.distributeFees(address(this), token, feeAmount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        VOTE DELEGATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Set delegationSpace
        @param  _delegationSpace  string  Convex Snapshot delegation space
        @param  shouldClear       bool    Whether to clear the vote delegate for current delegation space
     */
    function setDelegationSpace(
        string memory _delegationSpace,
        bool shouldClear
    ) external onlyOwner {
        if (shouldClear) {
            // Clear the delegation for the current delegation space
            clearVoteDelegate();
        }

        bytes memory d = bytes(_delegationSpace);

        if (d.length == 0) revert EmptyString();

        delegationSpace = bytes32(d);

        emit SetDelegationSpace(_delegationSpace, shouldClear);
    }

    /**
        @notice Set vote delegate
        @param  voteDelegate  address  Account to delegate votes to
     */
    function setVoteDelegate(address voteDelegate) external onlyOwner {
        if (voteDelegate == address(0)) revert ZeroAddress();

        emit SetVoteDelegate(voteDelegate);

        delegateRegistry.setDelegate(delegationSpace, voteDelegate);
    }

    /**
        @notice Clear vote delegate
     */
    function clearVoteDelegate() public onlyOwner {
        emit ClearVoteDelegate();

        delegateRegistry.clearDelegate(delegationSpace);
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
        IRewardRouterV2(gmxRewardRouterV2).signalTransfer(newContract);

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
        IRewardRouterV2(gmxRewardRouterV2).acceptTransfer(oldContract);

        emit CompleteMigration(oldContract);
    }
}
