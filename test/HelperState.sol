// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PirexGmx} from "src/PirexGmx.sol";
import {PirexFees} from "src/PirexFees.sol";

contract HelperState {
    // PirexGmx reusable state
    uint256 internal feeMax;

    PirexGmx.Fees[3] internal feeTypes;
}
