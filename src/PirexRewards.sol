// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IProducer} from "src/interfaces/IProducer.sol";

/**
    Originally inspired by Flywheel V2 (thank you Tribe team):
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/FlywheelCore.sol
*/
contract PirexRewards is Owned {
    using SafeTransferLib for ERC20;

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

    struct ProducerToken {
        GlobalState globalState;
        mapping(address => UserState) userStates;
        mapping(ERC20 => uint256) rewardStates;
        ERC20[] rewardTokens;
    }

    // Pirex contract which produces rewards
    IProducer public producer;

    // Producer tokens mapped to their data
    mapping(ERC20 => ProducerToken) public producerTokens;

    // Users mapped to reward tokens mapped to recipients
    mapping(address => mapping(ERC20 => address)) public rewardRecipients;

    event SetProducer(address producer);
    event SetRewardRecipient(
        address indexed user,
        address indexed recipient,
        ERC20 indexed rewardToken
    );
    event UnsetRewardRecipient(address indexed user, ERC20 indexed rewardToken);
    event PushRewardToken(
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken
    );
    event PopRewardToken(ERC20 indexed producerToken);
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
    event Harvest(
        ERC20[] producerTokens,
        ERC20[] rewardTokens,
        uint256[] rewardAmounts
    );
    event Claim(ERC20 indexed producerToken, address indexed user);
    event SetRewardRecipientPrivileged(
        address indexed lpContract,
        address indexed recipient,
        ERC20 indexed rewardToken
    );

    error ZeroAddress();
    error ZeroAmount();
    error EmptyArray();
    error NoRewardRecipient();
    error NotContract();

    constructor() Owned(msg.sender) {}

    /**
        @notice Set producer
        @param  _producer  address  Producer contract address
     */
    function setProducer(address _producer) external onlyOwner {
        if (_producer == address(0)) revert ZeroAddress();

        producer = IProducer(_producer);

        emit SetProducer(_producer);
    }

    /**
        @notice Set reward recipient for a reward token
        @param  recipient    address  Rewards recipient
        @param  rewardToken  ERC20    Reward token contract
    */
    function setRewardRecipient(address recipient, ERC20 rewardToken) external {
        if (recipient == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        rewardRecipients[msg.sender][rewardToken] = recipient;

        emit SetRewardRecipient(msg.sender, recipient, rewardToken);
    }

    /**
        @notice Unset reward recipient for a reward token
        @param  rewardToken  ERC20  Reward token contract
    */
    function unsetRewardRecipient(ERC20 rewardToken) external {
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        rewardRecipients[msg.sender][rewardToken] = address(0);

        emit UnsetRewardRecipient(msg.sender, rewardToken);
    }

    /**
        @notice Push a reward token to a producer token's rewardTokens array
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
    */
    function pushRewardToken(ERC20 producerToken, ERC20 rewardToken)
        external
        onlyOwner
    {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        producerTokens[producerToken].rewardTokens.push(rewardToken);

        emit PushRewardToken(producerToken, rewardToken);
    }

    /**
        @notice Push a reward token to a producer token's rewardTokens array
        @param  producerToken  ERC20    Producer token contract
    */
    function popRewardToken(ERC20 producerToken) external onlyOwner {
        if (address(producerToken) == address(0)) revert ZeroAddress();

        producerTokens[producerToken].rewardTokens.pop();

        emit PopRewardToken(producerToken);
    }

    /**
        @notice Getter for a producerToken's UserState struct member values
        @param  producerToken  ERC20    Producer token contract
        @param  user           address  User
        @return lastUpdate     uint256  Last update
        @return lastBalance    uint256  Last balance
        @return rewards        uint256  Rewards
    */
    function getUserState(ERC20 producerToken, address user)
        external
        view
        returns (
            uint256 lastUpdate,
            uint256 lastBalance,
            uint256 rewards
        )
    {
        UserState memory userState = producerTokens[producerToken].userStates[
            user
        ];

        return (userState.lastUpdate, userState.lastBalance, userState.rewards);
    }

    /**
        @notice Getter for a producerToken's UserState struct member values
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
        @return                uint256  Reward state
    */
    function getRewardState(ERC20 producerToken, ERC20 rewardToken)
        external
        view
        returns (uint256)
    {
        return producerTokens[producerToken].rewardStates[rewardToken];
    }

    /**
        @notice Getter for a producerToken's rewardTokens
        @param  producerToken  ERC20    Producer token contract
        @return                ERC20[]  Reward token contracts
    */
    function getRewardTokens(ERC20 producerToken)
        external
        view
        returns (ERC20[] memory)
    {
        return producerTokens[producerToken].rewardTokens;
    }

    /**
        @notice Getter for rewardRecipients
        @param  user         address  User
        @param  rewardToken  ERC20    Reward token contract
        @return              address  Reward recipient
    */
    function getRewardRecipient(address user, ERC20 rewardToken)
        public
        view
        returns (address)
    {
        return rewardRecipients[user][rewardToken];
    }

    /**
        @notice Update global rewards accrual state
        @param  producerToken  ERC20  Rewards-producing token
    */
    function globalAccrue(ERC20 producerToken) public {
        if (address(producerToken) == address(0)) revert ZeroAddress();

        GlobalState memory g = producerTokens[producerToken].globalState;
        uint256 timestamp = block.timestamp;
        uint256 totalSupply = producerToken.totalSupply();

        // Calculate rewards, the product of seconds elapsed and last supply
        uint256 rewards = g.rewards + (timestamp - g.lastUpdate) * g.lastSupply;

        producerTokens[producerToken].globalState = GlobalState({
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
    function userAccrue(ERC20 producerToken, address user) public {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (user == address(0)) revert ZeroAddress();

        UserState storage u = producerTokens[producerToken].userStates[user];
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

    /**
        @notice Update reward accrual state
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
        @param  rewardAmount   uint256  Reward amount
    */
    function _rewardAccrue(
        ERC20 producerToken,
        ERC20 rewardToken,
        uint256 rewardAmount
    ) internal {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();
        if (rewardAmount == 0) revert ZeroAmount();

        producerTokens[producerToken].rewardStates[rewardToken] += rewardAmount;
    }

    /**
        @notice Harvest rewards
        @return _producerTokens  ERC20[]  Producer token contracts
        @return rewardTokens    ERC20[]  Reward token contracts
        @return rewardAmounts   ERC20[]  Reward token amounts
    */
    function harvest()
        public
        returns (
            ERC20[] memory _producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        )
    {
        (_producerTokens, rewardTokens, rewardAmounts) = producer
            .claimWETHRewards();
        uint256 pLen = _producerTokens.length;

        // Iterate over the producer tokens and update reward state
        for (uint256 i; i < pLen; ++i) {
            ERC20 p = _producerTokens[i];
            uint256 r = rewardAmounts[i];

            // Update global reward accrual state and associate with the update of reward state
            globalAccrue(p);

            if (r != 0) {
                _rewardAccrue(p, rewardTokens[i], r);
            }
        }

        emit Harvest(_producerTokens, rewardTokens, rewardAmounts);
    }

    /**
        @notice Harvest rewards
        @param  producerToken   ERC20    Producer token contract
        @param  user            address  User
        @param  forwardRewards  bool     Whether to forward rewards (recipient must be set)
    */
    function claim(
        ERC20 producerToken,
        address user,
        bool forwardRewards
    ) external {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (user == address(0)) revert ZeroAddress();

        harvest();
        userAccrue(producerToken, user);

        ProducerToken storage p = producerTokens[producerToken];
        uint256 globalRewards = p.globalState.rewards;
        uint256 userRewards = p.userStates[user].rewards;
        ERC20[] memory rewardTokens = p.rewardTokens;
        uint256 rLen = rewardTokens.length;

        // Update global and user reward states to reflect the claim
        p.globalState.rewards -= userRewards;
        p.userStates[user].rewards = 0;

        emit Claim(producerToken, user);

        // Iterate over reward tokens and transfer the proportionate amount to the recipient
        for (uint256 i; i < rLen; ++i) {
            ERC20 rewardToken = rewardTokens[i];
            address recipient = forwardRewards
                ? rewardRecipients[user][rewardToken]
                : user;
            uint256 amount = (p.rewardStates[rewardToken] * userRewards) /
                globalRewards;

            // Update reward state (i.e. amount) to reflect amount of reward token transferred out
            p.rewardStates[rewardToken] -= amount;

            // If forwardRewards is true, recipient must be set
            if (recipient == address(0)) revert NoRewardRecipient();

            rewardTokens[i].safeTransfer(recipient, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ⚠️ PRIVILEGED METHODS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Privileged method for setting the reward recipient for a contract
        @notice This should ONLY be used to forward rewards for Pirex-GMX LP contracts
        @notice In production, we will have a 2nd multisig which reduces risk of abuse
        @param  lpContract    address  Pirex-GMX LP contract
        @param  recipient     address  Rewards recipient
        @param  rewardToken   ERC20    Reward token contract
    */
    function setRewardRecipientPrivileged(
        address lpContract,
        address recipient,
        ERC20 rewardToken
    ) external onlyOwner {
        if (lpContract.code.length == 0) revert NotContract();
        if (recipient == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        rewardRecipients[lpContract][rewardToken] = recipient;

        emit SetRewardRecipientPrivileged(lpContract, recipient, rewardToken);
    }
}
