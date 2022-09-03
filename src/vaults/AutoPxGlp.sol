// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {PirexERC4626} from "src/vaults/PirexERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {PirexRewards} from "src/PirexRewards.sol";

contract AutoPxGlp is Owned, PirexERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    ERC20 public constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    uint256 public constant MAX_WITHDRAWAL_PENALTY = 500;
    uint256 public constant MAX_PLATFORM_FEE = 2000;
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant EXPANDED_DECIMALS = 1e30;

    ERC20 public immutable extraReward;

    uint256 public withdrawalPenalty = 300;
    uint256 public platformFee = 1000;
    address public platform;
    address public rewardsModule;

    uint256 public extraRewardPerToken;
    mapping(address => uint256) public pendingExtraRewards;
    mapping(address => uint256) public userExtraRewardPerToken;

    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event PlatformUpdated(address _platform);
    event RewardsModuleUpdated(address _rewardsModule);
    event Compounded(
        address indexed caller,
        uint256 wethAmount,
        uint256 pxGmxAmountOut,
        uint256 pxGlpAmountOut
    );
    event ExtraRewardClaimed(
        address indexed account,
        address receiver,
        uint256 amount
    );

    error ZeroAmount();
    error ZeroAddress();
    error InvalidAssetParam();
    error ExceedsMax();

    /**
        @param  _asset         address  Asset address (vault asset, e.g. pxGLP)
        @param  _extraReward   address  Extra reward address (secondary reward, e.g. pxGMX)
        @param  _name          string   Asset name (e.g. Autocompounding pxGLP)
        @param  _symbol        string   Asset symbol (e.g. apxGLP)
        @param  _platform      address  Platform address (e.g. PirexGmxGlp)
     */
    constructor(
        address _asset,
        address _extraReward,
        string memory _name,
        string memory _symbol,
        address _platform
    ) Owned(msg.sender) PirexERC4626(ERC20(_asset), _name, _symbol) {
        if (_asset == address(0)) revert ZeroAddress();
        if (_extraReward == address(0)) revert ZeroAddress();
        if (bytes(_name).length == 0) revert InvalidAssetParam();
        if (bytes(_symbol).length == 0) revert InvalidAssetParam();
        if (_platform == address(0)) revert ZeroAddress();

        platform = _platform;
        extraReward = ERC20(_extraReward);

        // Approve the Uniswap V3 router to manage our WETH (inbound swap token)
        WETH.safeApprove(address(_platform), type(uint256).max);
    }

    /**
        @notice Set the withdrawal penalty
        @param  penalty  uint256  Withdrawal penalty
     */
    function setWithdrawalPenalty(uint256 penalty) external onlyOwner {
        if (penalty > MAX_WITHDRAWAL_PENALTY) revert ExceedsMax();

        withdrawalPenalty = penalty;

        emit WithdrawalPenaltyUpdated(penalty);
    }

    /**
        @notice Set the platform fee
        @param  fee  uint256  Platform fee
     */
    function setPlatformFee(uint256 fee) external onlyOwner {
        if (fee > MAX_PLATFORM_FEE) revert ExceedsMax();

        platformFee = fee;

        emit PlatformFeeUpdated(fee);
    }

    /**
        @notice Set the platform
        @param  _platform  address  Platform
     */
    function setPlatform(address _platform) external onlyOwner {
        if (_platform == address(0)) revert ZeroAddress();

        platform = _platform;

        emit PlatformUpdated(_platform);
    }

    /**
        @notice Set rewardsModule
        @param  _rewardsModule  address  Rewards module contract
     */
    function setRewardsModule(address _rewardsModule) external onlyOwner {
        if (_rewardsModule == address(0)) revert ZeroAddress();

        rewardsModule = _rewardsModule;

        emit RewardsModuleUpdated(_rewardsModule);
    }

    /**
        @notice Get the pxGLP custodied by the AutoPxGlp contract
        @return uint256  Amount of pxGLP custodied by the autocompounder
     */
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
        @notice Preview the amount of assets a user would receive from redeeming shares
        @param  shares   uint256  Shares amount
        @return          uint256  Assets amount
     */
    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        // Calculate assets based on a user's % ownership of vault shares
        uint256 assets = convertToAssets(shares);

        uint256 _totalSupply = totalSupply;

        // Calculate a penalty - zero if user is the last to withdraw
        uint256 penalty = (_totalSupply == 0 || _totalSupply - shares == 0)
            ? 0
            : assets.mulDivDown(withdrawalPenalty, FEE_DENOMINATOR);

        // Redeemable amount is the post-penalty amount
        return assets - penalty;
    }

    /**
        @notice Preview the amount of shares a user would need to redeem the specified asset amount
        @notice This modified version takes into consideration the withdrawal fee
        @param  assets   uint256  Assets amount
        @return          uint256  Shares amount
     */
    function previewWithdraw(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        // Calculate shares based on the specified assets' proportion of the pool
        uint256 shares = convertToShares(assets);

        // Save 1 SLOAD
        uint256 _totalSupply = totalSupply;

        // Factor in additional shares to fulfill withdrawal if user is not the last to withdraw
        return
            (_totalSupply == 0 || _totalSupply - shares == 0)
                ? shares
                : (shares * FEE_DENOMINATOR) /
                    (FEE_DENOMINATOR - withdrawalPenalty);
    }

    /**
        @notice Compound pxGLP rewards (privileged call to prevent manipulation)
        @return wethAmountIn    uint256  WETH inbound amount
        @return pxGmxAmountOut  uint256  pxGMX outbound amount
        @return pxGlpAmountOut  uint256  pxGLP outbound amount
     */
    function compound()
        public
        returns (
            uint256 wethAmountIn,
            uint256 pxGmxAmountOut,
            uint256 pxGlpAmountOut
        )
    {
        uint256 preClaimPxGmxAmount = extraReward.balanceOf(address(this));

        PirexRewards(rewardsModule).claim(asset, address(this));
        PirexRewards(rewardsModule).claim(extraReward, address(this));

        // Track the amount of WETH and pxGMX received
        wethAmountIn = WETH.balanceOf(address(this));
        pxGmxAmountOut =
            extraReward.balanceOf(address(this)) -
            preClaimPxGmxAmount;

        if (totalSupply != 0) {
            // Update amount of reward per vault share/token
            // Note that we expand the decimals to handle small rewards (less than supply)
            extraRewardPerToken +=
                (pxGmxAmountOut * EXPANDED_DECIMALS) /
                totalSupply;
        }

        if (wethAmountIn != 0) {
            // Deposit received WETH for pxGLP
            pxGlpAmountOut = PirexGmxGlp(platform).depositGlpWithERC20(
                address(WETH),
                wethAmountIn,
                1,
                address(this)
            );
        }

        emit Compounded(
            msg.sender,
            wethAmountIn,
            pxGmxAmountOut,
            pxGlpAmountOut
        );
    }

    /**
        @notice Update extra rewards related states
        @param  account  address  Account address
     */
    function _updateExtraReward(address account) internal {
        // Update pending claimable extra reward for the account based on vault shares
        // Note that the stored reward per token data has expanded decimals
        pendingExtraRewards[account] += ((balanceOf[account] *
            (extraRewardPerToken - userExtraRewardPerToken[account])) /
            EXPANDED_DECIMALS);

        // Update reward per token for the account to the latest amount
        userExtraRewardPerToken[account] = extraRewardPerToken;
    }

    /**
        @notice Compound pxGLP rewards and handle extra rewards logic before deposit
        @param  receiver  address  Receiver of the vault shares
     */
    function beforeDeposit(
        uint256,
        uint256,
        address receiver
    ) internal override {
        compound();

        _updateExtraReward(msg.sender);
        _updateExtraReward(receiver);
    }

    /**
        @notice Compound pxGLP rewards and handle extra rewards logic before withdrawal
        @param  owner     address  Owner of the vault shares
        @param  receiver  address  Receiver of the vault assets
     */
    function beforeWithdraw(
        uint256,
        uint256,
        address owner,
        address receiver
    ) internal override {
        compound();

        _updateExtraReward(owner);
        _updateExtraReward(receiver);
    }

    /**
        @notice Override transfer method to handle pre-deposit logic related to extra rewards
        @param  to      address  Account receiving apxGLP
        @param  amount  uint256  Amount of apxGLP
    */
    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        compound();

        _updateExtraReward(msg.sender);
        _updateExtraReward(to);

        return ERC20.transfer(to, amount);
    }

    /**
        @notice Override transferFrom method to handle pre-deposit logic related to extra rewards
        @param  from    address  Account sending apxGLP
        @param  to      address  Account receiving apxGLP
        @param  amount  uint256  Amount of apxGLP
    */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        compound();

        _updateExtraReward(from);
        _updateExtraReward(to);

        return ERC20.transferFrom(from, to, amount);
    }

    /**
        @notice Claim available extra rewards for the caller
        @param  receiver  address  Receiver of the extra rewards
     */
    function claimExtraReward(address receiver) external {
        if (receiver == address(0)) revert ZeroAddress();

        compound();

        _updateExtraReward(msg.sender);

        uint256 claimable = pendingExtraRewards[msg.sender];

        // Claim latest amount of available extra rewards
        // and reset the accumulated reward state
        if (claimable != 0) {
            pendingExtraRewards[msg.sender] = 0;

            extraReward.safeTransfer(receiver, claimable);

            emit ExtraRewardClaimed(msg.sender, receiver, claimable);
        }
    }
}
