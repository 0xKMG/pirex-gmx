// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/**
    Originally inspired by Flywheel V2 (thank you Tribe team):
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/FlywheelCore.sol
*/
contract RewardsHarvester is Owned {
    struct GlobalState {
        uint256 lastUpdate;
        uint256 lastSupply;
        uint256 rewards;
    }

    struct UserState {
        uint256 lastUpdate;
        uint256 lastBalance;
        uint256 rewards;
    }

    // Producer tokens mapped to their respective global states
    mapping(ERC20 => GlobalState) public globalStates;

    // Producer tokens mapped to their users' state
    mapping(ERC20 => mapping(address => UserState)) public userStates;

    // Stores rewards data and tokens
    address public rewardsSilo;

    event SetRewardsSilo(address rewardsSilo);

    event GlobalAccrue(
        ERC20 indexed producerToken,
        uint256 lastUpdate,
        uint256 lastSupply,
        uint256 rewards
    );

    event UserAccrue(
        ERC20 indexed producerToken,
        address indexed user,
        uint256 lastUpdate,
        uint256 lastSupply,
        uint256 rewards
    );

    error ZeroAddress();

    constructor() Owned(msg.sender) {}

    /**
        @notice Set rewardsHarvester
        @param  _rewardsSilo  address  RewardsSilo contract address
     */
    function setRewardsSilo(address _rewardsSilo) external onlyOwner {
        if (_rewardsSilo == address(0)) revert ZeroAddress();

        rewardsSilo = _rewardsSilo;

        emit SetRewardsSilo(_rewardsSilo);
    }

    /**
        @notice Update global rewards accrual state
        @param  producerToken  ERC20  Rewards-producing token
    */
    function globalAccrue(ERC20 producerToken) external {
        if (address(producerToken) == address(0)) revert ZeroAddress();

        GlobalState memory g = globalStates[producerToken];
        uint256 timestamp = block.timestamp;
        uint256 totalSupply = producerToken.totalSupply();

        // Calculate rewards, the product of seconds elapsed and last supply
        uint256 rewards = g.rewards + (timestamp - g.lastUpdate) * g.lastSupply;

        globalStates[producerToken] = GlobalState({
            lastUpdate: timestamp,
            lastSupply: totalSupply,
            rewards: rewards
        });

        emit GlobalAccrue(producerToken, timestamp, totalSupply, rewards);
    }

    /**
        @notice Update global rewards accrual state
        @param  producerToken  ERC20    Rewards-producing token
        @param  user           address  User address
    */
    function userAccrue(ERC20 producerToken, address user) external {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (user == address(0)) revert ZeroAddress();

        UserState storage u = userStates[producerToken][user];
        uint256 timestamp = block.timestamp;
        uint256 balance = producerToken.balanceOf(user);

        // Calculate the amount of rewards accrued by the user up to this call
        uint256 rewards = u.rewards +
            u.lastBalance *
            (timestamp - u.lastUpdate);

        u.lastUpdate = timestamp;
        u.lastBalance = balance;
        u.rewards = rewards;

        emit UserAccrue(producerToken, user, timestamp, balance, rewards);
    }
}
