// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC1155PresetMinterSupply} from "src/tokens/ERC1155PresetMinterSupply.sol";

contract PirexFuturesVault {
    using SafeTransferLib for ERC20;

    ERC1155PresetMinterSupply public immutable asset;
    ERC1155PresetMinterSupply public immutable yield;

    error ZeroAddress();

    constructor(
        ERC1155PresetMinterSupply _asset,
        ERC1155PresetMinterSupply _yield
    ) {
        if (address(_asset) == address(0)) revert ZeroAddress();
        if (address(_yield) == address(0)) revert ZeroAddress();

        asset = _asset;
        yield = _yield;
    }
}
