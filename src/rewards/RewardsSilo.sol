// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {PirexGlp} from "../PirexGlp.sol";

contract RewardsSilo {
    using SafeTransferLib for ERC20;

    // Pirex contract which maintains reward accrual state and coordinates silos
    address public immutable harvester;

    // Producer tokens mapped their reward tokens and amounts accrued
    mapping(ERC20 => mapping(ERC20 => uint256)) public rewardStates;

    error ZeroAddress();
    error ZeroAmount();
    error NotAuthorized();

    /**
        @param  _harvester  address  Pirex contract which maintains reward accrual state and coordinates silos
    */
    constructor(address _harvester) {
        if (_harvester == address(0)) revert ZeroAddress();

        harvester = _harvester;
    }

    modifier onlyHarvester() {
        if (msg.sender != harvester) revert NotAuthorized();
        _;
    }

    /**q
        @notice Update reward accrual state
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
        @param  rewardAmount   uint256  Reward amount
    */
    function rewardAccrue(
        ERC20 producerToken,
        ERC20 rewardToken,
        uint256 rewardAmount
    ) external onlyHarvester {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();
        if (rewardAmount == 0) revert ZeroAmount();

        rewardStates[producerToken][rewardToken] += rewardAmount;
    }
}
