// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Owned} from "solmate/auth/Owned.sol";

contract PirexFutures is Owned {
    address public immutable pxGmx;
    address public immutable pxGlp;

    uint256[] public durations = [
        30 days,
        90 days,
        180 days,
        360 days
    ];

    error ZeroAddress();

    /**
        @param  _pxGmx  address  PxGmx contract address
        @param  _pxGlp  address  PxGlp contract address
    */
    constructor(address _pxGmx, address _pxGlp) Owned(msg.sender) {
        if (_pxGmx == address(0)) revert ZeroAddress();
        if (_pxGlp == address(0)) revert ZeroAddress();

        pxGmx = _pxGmx;
        pxGlp = _pxGlp;
    }

    /**
        @notice Get expiry timestamp for a duration
        @param  index  uint256  Duration index
    */
    function getExpiry(uint256 index) public view returns (uint256) {
        uint256 duration = durations[index];

        return duration + ((block.timestamp / duration) * duration);
    }
}
