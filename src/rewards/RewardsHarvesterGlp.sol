// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {PirexGlp} from "../PirexGlp.sol";

contract RewardsHarvesterGlp {
    using SafeTransferLib for ERC20;

    // Pirex contract which maintains reward accrual state and coordinates silos
    address public immutable coordinator;

    // Pirex contract which produces and enables reward claims
    address public immutable producer;

    // Pirex token which enables the attribution of rewards
    ERC20 public immutable producerToken;

    // Token distributed as rewards
    ERC20 public immutable rewardToken;

    error ZeroAddress();

    /**
        @param  _coordinator    address  Pirex contract which maintains reward accrual state and coordinates silos
        @param  _producer       address  Pirex contract which produces and enables reward claims
        @param  _producerToken  ERC20    Pirex token which enables the attribution of rewards
        @param  _rewardToken    ERC20    Token distributed as rewards
    */
    constructor(
        address _coordinator,
        address _producer,
        ERC20 _producerToken,
        ERC20 _rewardToken
    ) {
        if (_coordinator == address(0)) revert ZeroAddress();
        if (_producer == address(0)) revert ZeroAddress();
        if (address(_producerToken) == address(0)) revert ZeroAddress();
        if (address(_rewardToken) == address(0)) revert ZeroAddress();

        coordinator = _coordinator;
        producer = _producer;
        producerToken = _producerToken;
        rewardToken = _rewardToken;
    }
}
