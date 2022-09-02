// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {PirexRewards} from "src/PirexRewards.sol";

contract AutoPxGlp is Owned, ERC4626 {
    using SafeTransferLib for ERC20;

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
    ) Owned(msg.sender) ERC4626(ERC20(_asset), _name, _symbol) {
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
            // TODO: Properly calculate and use the minimum received amount
            uint256 minGlpAmount = 0.000000000000001 ether;

            pxGlpAmountOut = PirexGmxGlp(platform).depositGlpWithERC20(
                address(WETH),
                wethAmountIn,
                minGlpAmount,
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
        @notice Override deposit method to handle pre-deposit logic related to extra rewards
        @param  assets    uint256  Assets amount
        @param  receiver  uint256  Receiver of the minted vault shares
        @return shares    uint256  Shares amount
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        compound();

        _updateExtraReward(msg.sender);
        _updateExtraReward(receiver);

        (shares) = ERC4626.deposit(assets, receiver);
    }

    /**
        @notice Override mint method to handle pre-deposit logic related to extra rewards
        @param  shares    uint256  Shares amount
        @param  receiver  uint256  Receiver of the minted vault shares
        @return assets    uint256  Assets amount
     */
    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        compound();

        _updateExtraReward(msg.sender);
        _updateExtraReward(receiver);

        (assets) = ERC4626.mint(shares, receiver);
    }

    /**
        @notice Override withdraw method to handle pre-deposit logic related to extra rewards
        @param  assets    uint256  Assets amount
        @param  receiver  address  Receiver of the vault assets
        @param  owner     address  Owner address
        @return shares    uint256  Shares amount
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        compound();

        _updateExtraReward(owner);
        _updateExtraReward(receiver);

        (shares) = ERC4626.withdraw(assets, receiver, owner);
    }

    /**
        @notice Override redeem method to handle pre-deposit logic related to extra rewards
        @param  shares    uint256  Shares amount
        @param  receiver  address  Receiver of the vault assets
        @param  owner     address  Owner address
        @return assets    uint256  Assets amount
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        compound();

        _updateExtraReward(owner);
        _updateExtraReward(receiver);

        (assets) = ERC4626.redeem(shares, receiver, owner);
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
