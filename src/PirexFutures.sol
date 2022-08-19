// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC1155PresetMinterSupply} from "src/tokens/ERC1155PresetMinterSupply.sol";

contract PirexFutures is Owned {
    address public immutable pxGmx;
    address public immutable pxGlp;

    uint256[] public durations = [30 days, 90 days, 180 days, 360 days];

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

    /**
        @notice Mint secured future yield for a specified duration
        @param  token          ERC1155PresetMinterSupply  Token contract
        @param  tokenUri       bytes                      Token URI bytes
        @param  durationIndex  uint256                    Duration index
        @param  periods        uint256                    Number of expiry periods
        @param  assets         uint256                    Futures amount
        @param  receiver       address                    Receives futures
    */
    function mintYield(
        ERC1155PresetMinterSupply token,
        bytes memory tokenUri,
        uint256 durationIndex,
        uint256 periods,
        uint256 assets,
        address receiver
    ) external {
        uint256 duration = durations[durationIndex];
        uint256 startingExpiry = getExpiry(durationIndex);
        uint256[] memory tokenIds = new uint256[](periods);
        uint256[] memory amounts = new uint256[](periods);

        for (uint256 i; i < periods; ++i) {
            // Rounds subsequent to the 1st are locked for the full duration, earning
            // full rewards (100% of assets)
            if (i != 0) {
                tokenIds[i] = startingExpiry + i * duration;
                amounts[i] = assets;
            } else {
                tokenIds[i] = startingExpiry;

                // For the 1st round, assets may be generating only partial rewards, so the
                // amount of yield tokens minted is based on time remaining until expiry
                amounts[i] =
                    assets *
                    ((startingExpiry - block.timestamp) / duration);
            }
        }

        token.mintBatch(receiver, tokenIds, amounts, tokenUri);
    }
}
