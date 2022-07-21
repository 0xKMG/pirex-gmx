// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {PirexGlp} from "src/PirexGlp.sol";
import {PxGlp} from "src/PxGlp.sol";
import {IRewardRouterV2} from "src/interface/IRewardRouterV2.sol";
import {IVaultReader} from "src/interface/IVaultReader.sol";
import {IGlpManager} from "src/interface/IGlpManager.sol";
import {IReader} from "src/interface/IReader.sol";
import {IWBTC} from "src/interface/IWBTC.sol";
import {Vault} from "src/external/Vault.sol";

contract Helper {
    IRewardRouterV2 internal constant REWARD_ROUTER_V2 =
        IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    IVaultReader internal constant VAULT_READER =
        IVaultReader(0xfebB9f4CAC4cD523598fE1C5771181440143F24A);
    IGlpManager internal constant GLP_MANAGER =
        IGlpManager(0x321F653eED006AD1C29D174e17d96351BDe22649);
    IReader internal constant READER =
        IReader(0x22199a49A999c351eF7927602CFB187ec3cae489);
    Vault internal constant VAULT =
        Vault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    IERC20 internal constant REWARD_TRACKER =
        IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    IERC20 internal constant USDG =
        IERC20(0x45096e7aA921f27590f8F19e457794EB09678141);
    IERC20 FEE_STAKED_GLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    IWBTC internal constant WBTC =
        IWBTC(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);

    PirexGlp internal immutable pirexGlp;
    PxGlp internal immutable pxGlp;

    address internal constant POSITION_ROUTER =
        0x3D6bA331e3D9702C5e8A8d254e5d8a285F223aba;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    uint256 internal constant FEE_BPS = 25;
    uint256 internal constant TAX_BPS = 50;
    uint256 internal constant BPS_DIVISOR = 10_000;
    uint256 internal constant SLIPPAGE = 30;
    uint256 internal constant PRECISION = 1e30;
    uint256 internal constant EXPANDED_GLP_DECIMALS = 18;
    uint256 internal constant INFO_USDG_AMOUNT = 1e18;

    constructor() {
        pxGlp = new PxGlp(address(this));
        pirexGlp = new PirexGlp(address(pxGlp));

        pxGlp.grantRole(pxGlp.MINTER_ROLE(), address(pirexGlp));
    }
}
