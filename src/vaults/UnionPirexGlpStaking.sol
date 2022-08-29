// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";

contract UnionPirexGlpStaking is Owned {
    using SafeTransferLib for ERC20;

    address public immutable vault;
    ERC20 public immutable token;

    uint256 public constant rewardsDuration = 14 days;

    address public distributor;
    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public userRewardPerTokenPaid;
    uint256 public rewards;

    uint256 internal _totalSupply;

    event RewardAdded(uint256 reward);
    event Staked(uint256 amount);
    event Withdrawn(uint256 amount);
    event RewardPaid(uint256 reward);
    event Recovered(address token, uint256 amount);
    event SetDistributor(address distributor);

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards = earned();
            userRewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    modifier onlyDistributor() {
        require((msg.sender == distributor), "Distributor only");
        _;
    }

    modifier onlyVault() {
        require((msg.sender == vault), "Vault only");
        _;
    }

    constructor(
        address _token,
        address _distributor,
        address _vault
    ) Owned(msg.sender) {
        token = ERC20(_token);
        distributor = _distributor;
        vault = _vault;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function totalSupplyWithRewards() external view returns (uint256, uint256) {
        uint256 t = _totalSupply;

        return (
            t,
            ((t * (rewardPerToken() - userRewardPerTokenPaid)) / 1e18) + rewards
        );
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            ((((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate) *
                1e18) / _totalSupply);
    }

    function earned() public view returns (uint256) {
        return
            ((_totalSupply * (rewardPerToken() - userRewardPerTokenPaid)) /
                1e18) + rewards;
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    function stake(uint256 amount) external onlyVault updateReward(vault) {
        require(amount > 0, "Cannot stake 0");

        _totalSupply += amount;
        token.safeTransferFrom(vault, address(this), amount);

        emit Staked(amount);
    }

    function withdraw(uint256 amount) external onlyVault updateReward(vault) {
        require(amount > 0, "Cannot withdraw 0");

        _totalSupply -= amount;
        token.safeTransfer(vault, amount);

        emit Withdrawn(amount);
    }

    function getReward() external updateReward(vault) {
        uint256 reward = rewards;

        if (reward > 0) {
            rewards = 0;
            token.safeTransfer(vault, reward);

            emit RewardPaid(reward);
        }
    }

    function notifyRewardAmount()
        external
        onlyDistributor
        updateReward(address(0))
    {
        // Rewards transferred directly to this contract are not added to _totalSupply
        // To get the rewards w/o relying on a potentially incorrect passed in arg,
        // we can use the difference between the token balance and _totalSupply.
        // Additionally, to avoid re-distributing rewards, deduct the output of `earned`
        uint256 rewardBalance = token.balanceOf(address(this)) -
            _totalSupply -
            earned();

        rewardRate = rewardBalance / rewardsDuration;
        require(rewardRate != 0, "No rewards");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;

        emit RewardAdded(rewardBalance);
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        require(
            tokenAddress != address(token),
            "Cannot withdraw the staking token"
        );

        ERC20(tokenAddress).safeTransfer(owner, tokenAmount);

        emit Recovered(tokenAddress, tokenAmount);
    }

    function setDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0));

        distributor = _distributor;

        emit SetDistributor(_distributor);
    }
}