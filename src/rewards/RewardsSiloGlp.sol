// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {PirexGlp} from "../PirexGlp.sol";

contract RewardsSiloGlp {
    using SafeTransferLib for ERC20;

    // Pirex contract which produces and enables reward claims
    address public immutable producer;

    // Pirex contract which maintains reward accrual state and coordinates silos
    address public immutable coordinator;

    // Pirex token which enables the attribution of rewards
    ERC20 public immutable producerToken;

    // Token distributed as rewards
    ERC20 public immutable rewardToken;

    error ZeroAddress();

    /**
        @param  _producer       address  Pirex contract which produces and enables reward claims
        @param  _coordinator    address  Pirex contract which maintains reward accrual state and coordinates silos
        @param  _producerToken  ERC20    Pirex token which enables the attribution of rewards
        @param  _rewardToken    ERC20    Token distributed as rewards
    */
    constructor(
        address _producer,
        address _coordinator,
        ERC20 _producerToken,
        ERC20 _rewardToken
    ) {
        if (_producer == address(0)) revert ZeroAddress();
        if (_coordinator == address(0)) revert ZeroAddress();
        if (address(_producerToken) == address(0)) revert ZeroAddress();
        if (address(_rewardToken) == address(0)) revert ZeroAddress();

        producer = _producer;
        coordinator = _coordinator;
        producerToken = _producerToken;
        rewardToken = _rewardToken;
    }
}
