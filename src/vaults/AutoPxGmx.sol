// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {PirexERC4626} from "src/vaults/PirexERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {PirexRewards} from "src/PirexRewards.sol";
import {IV3SwapRouter} from "src/interfaces/IV3SwapRouter.sol";

contract AutoPxGmx is Owned, PirexERC4626 {
    using SafeTransferLib for ERC20;

    ERC20 public constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    ERC20 public constant GMX =
        ERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    IV3SwapRouter public constant SWAP_ROUTER =
        IV3SwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    uint256 public constant MAX_WITHDRAWAL_PENALTY = 500;
    uint256 public constant MAX_PLATFORM_FEE = 2000;
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MAX_COMPOUND_INCENTIVE = 5000;

    uint256 public withdrawalPenalty = 300;
    uint256 public platformFee = 1000;
    uint256 public compoundIncentive = 1000;
    address public platform;
    address public rewardsModule;

    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event CompoundIncentiveUpdated(uint256 incentive);
    event PlatformUpdated(address _platform);
    event RewardsModuleUpdated(address _rewardsModule);
    event Compounded(
        address indexed caller,
        uint24 fee,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        uint256 wethAmountIn,
        uint256 gmxAmountOut,
        uint256 pxGmxMintAmount,
        uint256 totalFee,
        uint256 incentive
    );

    error ZeroAddress();
    error InvalidAssetParam();
    error ExceedsMax();
    error AlreadySet();
    error InvalidParam();

    /**
        @param  _asset         address  Asset address (e.g. pxGMX)
        @param  _name          string   Asset name (e.g. Autocompounding pxGMX)
        @param  _symbol        string   Asset symbol (e.g. apxGMX)
        @param  _platform      address  Platform address (e.g. PirexGmxGlp)
     */
    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _platform
    ) Owned(msg.sender) PirexERC4626(ERC20(_asset), _name, _symbol) {
        if (_asset == address(0)) revert ZeroAddress();
        if (bytes(_name).length == 0) revert InvalidAssetParam();
        if (bytes(_symbol).length == 0) revert InvalidAssetParam();
        if (_platform == address(0)) revert ZeroAddress();

        platform = _platform;

        // Approve the Uniswap V3 router to manage our WETH (inbound swap token)
        WETH.safeApprove(address(SWAP_ROUTER), type(uint256).max);
        GMX.safeApprove(_platform, type(uint256).max);
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
        @notice Set the compound incentive
        @param  incentive  uint256  Compound incentive
     */
    function setCompoundIncentive(uint256 incentive) external onlyOwner {
        if (incentive > MAX_COMPOUND_INCENTIVE) revert ExceedsMax();

        compoundIncentive = incentive;

        emit CompoundIncentiveUpdated(incentive);
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
        @notice Get the pxGMX custodied by the AutoPxGmx contract
        @return uint256  Amount of pxGMX custodied by the autocompounder
     */
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
        @notice Compound pxGMX rewards before depositing
     */
    function beforeDeposit(uint256, uint256) internal override {
        compound(3000, 1, 0, true);
    }

    /**
        @notice Compound pxGMX rewards
        @param  fee                uint24   Uniswap pool tier fee
        @param  amountOutMinimum   uint256  Outbound token swap amount
        @param  sqrtPriceLimitX96  uint160  Swap price impact limit (optional)
        @param  optOutIncentive    bool     Whether to opt out of the incentive
        @return wethAmountIn       uint256  WETH inbound swap amount
        @return gmxAmountOut       uint256  GMX outbound swap amount
        @return pxGmxMintAmount    uint256  pxGMX minted when depositing GMX
     */
    function compound(
        uint24 fee,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        bool optOutIncentive
    )
        public
        returns (
            uint256 wethAmountIn,
            uint256 gmxAmountOut,
            uint256 pxGmxMintAmount
        )
    {
        if (fee == 0) revert InvalidParam();
        if (amountOutMinimum == 0) revert InvalidParam();

        uint256 assetsBeforeClaim = asset.balanceOf(address(this));

        PirexRewards(rewardsModule).claim(asset, address(this));

        // Swap entire WETH balance for GMX
        wethAmountIn = WETH.balanceOf(address(this));

        if (wethAmountIn != 0)
            gmxAmountOut = SWAP_ROUTER.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: address(WETH),
                    tokenOut: address(GMX),
                    fee: fee,
                    recipient: address(this),
                    amountIn: wethAmountIn,
                    amountOutMinimum: amountOutMinimum,
                    sqrtPriceLimitX96: sqrtPriceLimitX96
                })
            );

        uint256 gmxBalance = GMX.balanceOf(address(this));

        // GMX balance is zero, return method to avoid wasteful gas expenditure
        if (gmxBalance == 0) return (0, 0, 0);

        // Deposit entire GMX balance for pxGMX, increasing the asset/share amount
        (, pxGmxMintAmount) = PirexGmxGlp(platform).depositGmx(
            gmxBalance,
            address(this)
        );

        // Distribute fees to the owner (Pirex multisig) and the caller (if incentive is not opted out)
        uint256 totalFee = ((asset.balanceOf(address(this)) -
            assetsBeforeClaim) * platformFee) / FEE_DENOMINATOR;
        uint256 incentive = optOutIncentive
            ? 0
            : (totalFee * compoundIncentive) / FEE_DENOMINATOR;

        if (incentive != 0) asset.safeTransfer(msg.sender, incentive);

        asset.safeTransfer(owner, totalFee - incentive);

        emit Compounded(
            msg.sender,
            fee,
            amountOutMinimum,
            sqrtPriceLimitX96,
            wethAmountIn,
            gmxAmountOut,
            pxGmxMintAmount,
            totalFee,
            incentive
        );
    }
}
