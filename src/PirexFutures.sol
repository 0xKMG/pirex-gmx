// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC1155PresetMinterSupply} from "src/interfaces/IERC1155PresetMinterSupply.sol";

contract PirexFutures is Owned {
    using SafeTransferLib for ERC20;

    ERC20 public immutable pxGmx;
    ERC20 public immutable pxGlp;
    IERC1155PresetMinterSupply public immutable ypxGmx;
    IERC1155PresetMinterSupply public immutable ypxGlp;

    uint256[] public durations = [30 days, 90 days, 180 days, 360 days];

    event MintYield(
        bool indexed useGmx,
        uint256 indexed durationIndex,
        uint256 periods,
        uint256 assets,
        address indexed receiver,
        uint256[] tokenIds,
        uint256[] amounts
    );

    error ZeroAddress();
    error ZeroAmount();

    /**
        @param  _pxGmx   address  PxGmx contract address
        @param  _pxGlp   address  PxGlp contract address
        @param  _ypxGmx  address  YpxGmx contract address
        @param  _ypxGlp  address  YpxGlp contract address
    */
    constructor(
        address _pxGmx,
        address _pxGlp,
        address _ypxGmx,
        address _ypxGlp
    ) Owned(msg.sender) {
        if (_pxGmx == address(0)) revert ZeroAddress();
        if (_pxGlp == address(0)) revert ZeroAddress();
        if (_ypxGmx == address(0)) revert ZeroAddress();
        if (_ypxGlp == address(0)) revert ZeroAddress();

        pxGmx = ERC20(_pxGmx);
        pxGlp = ERC20(_pxGlp);
        ypxGmx = IERC1155PresetMinterSupply(_ypxGmx);
        ypxGlp = IERC1155PresetMinterSupply(_ypxGlp);
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
        @param  useGmx         bool     Use pxGMX
        @param  durationIndex  uint256  Duration index
        @param  periods        uint256  Number of expiry periods
        @param  assets         uint256  Futures amount
        @param  receiver       address  Receives futures
    */
    function mintYield(
        bool useGmx,
        uint256 durationIndex,
        uint256 periods,
        uint256 assets,
        address receiver
    ) external {
        if (periods == 0) revert ZeroAmount();
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

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

        emit MintYield(
            useGmx,
            durationIndex,
            periods,
            assets,
            receiver,
            tokenIds,
            amounts
        );

        // Secure productive assets and batch mint yield tokens
        if (useGmx) {
            pxGmx.safeTransferFrom(msg.sender, address(this), assets);
            ypxGmx.mintBatch(receiver, tokenIds, amounts, "");
        } else {
            pxGlp.safeTransferFrom(msg.sender, address(this), assets);
            ypxGlp.mintBatch(receiver, tokenIds, amounts, "");
        }
    }
}
