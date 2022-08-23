// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC1155PresetMinterSupply} from "src/tokens/ERC1155PresetMinterSupply.sol";
import {PirexFuturesVault} from "src/futures/PirexFuturesVault.sol";

contract PirexFutures is Owned {
    using SafeTransferLib for ERC20;

    ERC20 public immutable pxGmx;
    ERC20 public immutable pxGlp;
    ERC1155PresetMinterSupply public immutable apxGmx;
    ERC1155PresetMinterSupply public immutable apxGlp;
    ERC1155PresetMinterSupply public immutable ypxGmx;
    ERC1155PresetMinterSupply public immutable ypxGlp;

    // Fixed time periods for minting and securing future token yield
    uint256[] public durations = [30 days, 90 days, 180 days, 360 days];

    // Maturity timestamps mapped to a vault contract
    mapping(uint256 => PirexFuturesVault) public vaults;

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
        @param  _apxGmx  address  PxGmx derivative contract address
        @param  _apxGlp  address  PxGlp derivative contract address
        @param  _ypxGmx  address  PxGmx yield contract address
        @param  _ypxGlp  address  PxGlp yield contract address
    */
    constructor(
        address _pxGmx,
        address _pxGlp,
        address _apxGmx,
        address _apxGlp,
        address _ypxGmx,
        address _ypxGlp
    ) Owned(msg.sender) {
        if (_pxGmx == address(0)) revert ZeroAddress();
        if (_pxGlp == address(0)) revert ZeroAddress();
        if (_apxGmx == address(0)) revert ZeroAddress();
        if (_apxGlp == address(0)) revert ZeroAddress();
        if (_ypxGmx == address(0)) revert ZeroAddress();
        if (_ypxGlp == address(0)) revert ZeroAddress();

        pxGmx = ERC20(_pxGmx);
        pxGlp = ERC20(_pxGlp);
        apxGmx = ERC1155PresetMinterSupply(_apxGmx);
        apxGlp = ERC1155PresetMinterSupply(_apxGlp);
        ypxGmx = ERC1155PresetMinterSupply(_ypxGmx);
        ypxGlp = ERC1155PresetMinterSupply(_ypxGlp);
    }

    /**
        @notice Get maturity timestamp for a duration
        @param  index  uint256  Duration index
    */
    function getMaturity(uint256 index) public view returns (uint256) {
        uint256 duration = durations[index];

        return duration + ((block.timestamp / duration) * duration);
    }

    /**
        @notice Mint secured future yield for a number of terms
        @param  useGmx         bool     Use pxGMX
        @param  durationIndex  uint256  Duration index
        @param  assets         uint256  Futures amount
        @param  receiver       address  Receives futures
    */
    function mintYield(
        bool useGmx,
        uint256 durationIndex,
        uint256 assets,
        address receiver
    ) external {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        ERC20 producerToken = useGmx ? ERC20(pxGmx) : ERC20(pxGlp);
        ERC1155PresetMinterSupply asset = useGmx ? apxGmx : apxGlp;
        ERC1155PresetMinterSupply yield = useGmx ? ypxGmx : ypxGlp;
        uint256 maturity = getMaturity(durationIndex);
        PirexFuturesVault vault = vaults[maturity];

        // Create the requisite vault contract for asset and reward management
        if (address(vault) == address(0)) {
            vault = new PirexFuturesVault(asset, yield);
            vaults[maturity] = vault;
        }

        // Transfer tokens to the vault for reward accrual and redemption purposes
        producerToken.safeTransferFrom(msg.sender, address(vault), assets);

        // Mint a synthetic of the yield-backing asset equal to the vault-custodied amount
        asset.mint(receiver, maturity, assets, bytes(""));

        // Mint yield tokens, the amount of which is based on the time remaining until maturity
        yield.mint(
            receiver,
            maturity,
            assets * ((maturity - block.timestamp) / durations[durationIndex]),
            bytes("")
        );

        // emit MintYield(
        //     useGmx,
        //     durationIndex,
        //     periods,
        //     assets,
        //     receiver,
        //     tokenIds,
        //     amounts
        // );
    }
}
