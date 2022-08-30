// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";

contract UnionPirexGlpStaking is Owned {
    using SafeTransferLib for ERC20;

    struct Reward {
        uint32 periodFinish;
        uint224 rewardRate;
        uint32 lastUpdateTime;
        uint224 rewardPerTokenStored;
    }

    address public immutable vault;
    address public immutable token;
    address public immutable extraToken;

    uint256 public constant rewardsDuration = 14 days;

    address public distributor;
    mapping(address => Reward) public rewardData;
    mapping(address => mapping(address => uint256))
        public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public rewards;

    uint256 internal _totalSupply;

    event RewardAdded(address token, uint256 reward);
    event Staked(uint256 amount);
    event Withdrawn(uint256 amount);
    event RewardPaid(address token, address receiver, uint256 reward);
    event Recovered(address token, uint256 amount);
    event SetDistributor(address distributor);

    error ZeroAmount();
    error ZeroAddress();
    error InvalidToken();
    error InvalidNumber(uint256 value);
    error NotDistributor();
    error NotVault();
    error NoRewards();

    /**
        @notice Internal modifier to update reward related states used on major mutative methods
        @param  account  address  Account address
     */
    modifier updateReward(address account) {
        // Update the main vault token state
        Reward storage mainReward = rewardData[token];
        mainReward.rewardPerTokenStored = _toUint224(rewardPerToken(token));
        mainReward.lastUpdateTime = _toUint32(
            _lastTimeRewardApplicable(mainReward.periodFinish)
        );

        // Update the extra token state
        Reward storage extraReward = rewardData[extraToken];
        extraReward.rewardPerTokenStored = _toUint224(
            rewardPerToken(extraToken)
        );
        extraReward.lastUpdateTime = _toUint32(
            _lastTimeRewardApplicable(extraReward.periodFinish)
        );

        if (account != address(0)) {
            // Main token is directly managed and claimed by the vault contract
            rewards[token][vault] = earned(vault, token, _totalSupply);
            userRewardPerTokenPaid[token][vault] = mainReward
                .rewardPerTokenStored;

            if (account != vault) {
                // Extra token is tracked per and claimed by users based on their current vault shares
                rewards[extraToken][account] = earned(
                    account,
                    extraToken,
                    ERC20(vault).balanceOf(account)
                );
                userRewardPerTokenPaid[extraToken][account] = extraReward
                    .rewardPerTokenStored;
            }
        }
        _;
    }

    modifier onlyDistributor() {
        if (msg.sender != distributor) revert NotDistributor();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    constructor(
        address _token,
        address _extraToken,
        address _distributor,
        address _vault
    ) Owned(msg.sender) {
        if (_token == address(0)) revert ZeroAddress();
        if (_extraToken == address(0)) revert ZeroAddress();
        if (_distributor == address(0)) revert ZeroAddress();
        if (_vault == address(0)) revert ZeroAddress();

        token = _token;
        extraToken = _extraToken;
        distributor = _distributor;
        vault = _vault;
    }

    /**
        @notice Set distributor address
        @param  _distributor  address  Distributor address
     */
    function setDistributor(address _distributor) external onlyOwner {
        if (_distributor == address(0)) revert ZeroAddress();

        distributor = _distributor;

        afterDistributorSet(_distributor);

        emit SetDistributor(_distributor);
    }

    /**
        @notice Total supply of staked assets
        @return uint256  Total supply
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
        @notice Total supply of staked assets + rewards
        @return uint256  Total supply
        @return uint256  Rewards
     */
    function totalSupplyWithRewards() external view returns (uint256, uint256) {
        uint256 t = _totalSupply;

        return (t, earned(vault, token, t));
    }

    /**
        @notice Get the last applicable timestamp based on the ending timestamp
        @param  periodFinish  uint32   Timestamp for the end of reward streaming
        @return               uint256  Timestamp
     */
    function _lastTimeRewardApplicable(uint32 periodFinish)
        internal
        view
        returns (uint256)
    {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /**
        @notice Get the last applicable timestamp based on the reward token address
        @param  _token  address  Reward token address
        @return         uint256  Timestamp
     */
    function lastTimeRewardApplicable(address _token)
        external
        view
        returns (uint256)
    {
        return _lastTimeRewardApplicable(rewardData[_token].periodFinish);
    }

    /**
        @notice Get the amount of reward per token (with expanded decimals)
        @param  _token  address  Reward token address
        @return         uint256  Amount per token
     */
    function rewardPerToken(address _token) public view returns (uint256) {
        // Extra token tracking is based on vault shares ownership
        uint256 supply = _token == token
            ? _totalSupply
            : ERC20(vault).totalSupply();
        Reward memory reward = rewardData[_token];

        if (supply == 0) {
            return reward.rewardPerTokenStored;
        }

        return
            reward.rewardPerTokenStored +
            ((((_lastTimeRewardApplicable(reward.periodFinish) -
                reward.lastUpdateTime) * reward.rewardRate) * 1e18) / supply);
    }

    /**
        @notice Get the amount of accrued/earned reward over time
        @param  account  address  Account address
        @param  _token   address  Token address
        @param  balance  uint256  Account balance
        @return          uint256  Amount earned
     */
    function earned(
        address account,
        address _token,
        uint256 balance
    ) public view returns (uint256) {
        return
            ((balance *
                (rewardPerToken(_token) -
                    userRewardPerTokenPaid[_token][account])) / 1e18) +
            rewards[_token][account];
    }

    /**
        @notice Get the total amount of accrued rewards for the full stream duration
        @param  _token   address  Token address
        @return          uint256  Amount accrued
     */
    function getRewardForDuration(address _token)
        external
        view
        returns (uint256)
    {
        return rewardData[_token].rewardRate * rewardsDuration;
    }

    /**
        @notice Stake vault assets
        @param  account  address  Account address
        @param  amount   uint256  Stake amount
     */
    function stake(address account, uint256 amount)
        external
        onlyVault
        updateReward(account)
    {
        if (amount == 0) revert ZeroAmount();

        _totalSupply += amount;
        ERC20(token).safeTransferFrom(vault, address(this), amount);

        emit Staked(amount);
    }

    /**
        @notice Withdraw vault assets
        @param  account  address  Account address
        @param  amount   uint256  Stake amount
     */
    function withdraw(address account, uint256 amount)
        external
        onlyVault
        updateReward(account)
    {
        if (amount == 0) revert ZeroAmount();

        _totalSupply -= amount;
        ERC20(token).safeTransfer(vault, amount);

        emit Withdrawn(amount);
    }

    /**
        @notice Claim available rewards for main vault token
     */
    function getReward() external updateReward(vault) {
        uint256 reward = rewards[token][vault];

        if (reward > 0) {
            rewards[token][vault] = 0;
            ERC20(token).safeTransfer(vault, reward);

            emit RewardPaid(token, vault, reward);
        }
    }

    /**
        @notice Claim available extra token rewards for the caller
     */
    function getExtraReward() external updateReward(msg.sender) {
        uint256 reward = rewards[extraToken][msg.sender];

        if (reward > 0) {
            rewards[extraToken][msg.sender] = 0;
            ERC20(extraToken).safeTransfer(msg.sender, reward);

            emit RewardPaid(extraToken, msg.sender, reward);
        }
    }

    /**
        @notice Update reward data
        @param  _token  address  Token address
        @param  rate    uint256  Reward rate
     */
    function _updateRewardData(address _token, uint256 rate) internal {
        if (rate == 0) revert NoRewards();

        Reward storage reward = rewardData[_token];
        reward.rewardRate = _toUint224(rate);
        reward.lastUpdateTime = _toUint32(block.timestamp);
        reward.periodFinish = _toUint32(block.timestamp + rewardsDuration);
    }

    /**
        @notice Notify new reward stream for main vault token by distributor
     */
    function notifyReward() external onlyDistributor updateReward(address(0)) {
        // Rewards transferred directly to this contract are not added to _totalSupply
        // To get the rewards w/o relying on a potentially incorrect passed in arg,
        // we can use the difference between the token balance and _totalSupply.
        // Additionally, to avoid re-distributing rewards, deduct the output of `earned`
        uint256 rewardBalance = ERC20(token).balanceOf(address(this)) -
            _totalSupply -
            earned(vault, token, _totalSupply);

        _updateRewardData(token, rewardBalance / rewardsDuration);

        emit RewardAdded(address(0), rewardBalance);
    }

    /**
        @notice Notify new reward stream for extra token rewards
     */
    function _notifyExtraReward(uint256 amount)
        internal
        updateReward(address(0))
    {
        // As only the contract itself can call this method right after claiming
        // the rewards, we can directly specify the exact amount of extra token reward
        // and update the reward data based on actual claimed pxGMX reward amount
        _updateRewardData(extraToken, amount / rewardsDuration);

        emit RewardAdded(extraToken, amount);
    }

    /**
        @notice For recovering LP Rewards from other systems such as BAL to be distributed to holders
        @param  tokenAddress  address  Token address
        @param  tokenAmount   uint256  Token amount
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        if (tokenAddress == address(0)) revert ZeroAddress();
        if (tokenAddress == token || tokenAddress == extraToken)
            revert InvalidToken();
        if (tokenAmount == 0) revert ZeroAmount();

        ERC20(tokenAddress).safeTransfer(owner, tokenAmount);

        emit Recovered(tokenAddress, tokenAmount);
    }

    /**
        @notice Validate and cast a uint256 integer to uint224
        @param  value  uint256  Value
        @return        uint224  Casted value
     */
    function _toUint224(uint256 value) internal pure returns (uint224) {
        if (value > type(uint224).max) revert InvalidNumber(value);

        return uint224(value);
    }

    /**
        @notice Validate and cast a uint256 integer to uint32
        @param  value  uint256  Value
        @return        uint32   Casted value
     */
    function _toUint32(uint256 value) internal pure returns (uint32) {
        if (value > type(uint32).max) revert InvalidNumber(value);

        return uint32(value);
    }

    /**
        @notice Internal hook for distributor update
        @param  _distributor  address  Distributor address
     */
    function afterDistributorSet(address _distributor) internal virtual {}
}
