// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {PxGmx} from "src/PxGmx.sol";
import {PxGlp} from "src/PxGlp.sol";
import {PxGlpRewards} from "src/PxGlpRewards.sol";
import {IRewardRouterV2} from "src/interfaces/IRewardRouterV2.sol";
import {IRewardTracker} from "src/interfaces/IRewardTracker.sol";
import {IVaultReader} from "src/interfaces/IVaultReader.sol";
import {IGlpManager} from "src/interfaces/IGlpManager.sol";
import {IReader} from "src/interfaces/IReader.sol";
import {IGMX} from "src/interfaces/IGMX.sol";
import {ITimelock} from "src/interfaces/ITimelock.sol";
import {IWBTC} from "src/interfaces/IWBTC.sol";
import {Vault} from "src/external/Vault.sol";

contract Helper is Test {
    IRewardRouterV2 internal constant REWARD_ROUTER_V2 =
        IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    IRewardTracker public constant REWARD_TRACKER_GMX =
        IRewardTracker(0xd2D1162512F927a7e282Ef43a362659E4F2a728F);
    IRewardTracker public constant REWARD_TRACKER_GLP =
        IRewardTracker(0x4e971a87900b931fF39d1Aad67697F49835400b6);
    IVaultReader internal constant VAULT_READER =
        IVaultReader(0xfebB9f4CAC4cD523598fE1C5771181440143F24A);
    IGlpManager internal constant GLP_MANAGER =
        IGlpManager(0x321F653eED006AD1C29D174e17d96351BDe22649);
    IReader internal constant READER =
        IReader(0x22199a49A999c351eF7927602CFB187ec3cae489);
    Vault internal constant VAULT =
        Vault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    IGMX internal constant GMX =
        IGMX(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    IERC20 internal constant REWARD_TRACKER =
        IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    IERC20 internal constant USDG =
        IERC20(0x45096e7aA921f27590f8F19e457794EB09678141);
    IERC20 FEE_STAKED_GLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    IWBTC internal constant WBTC =
        IWBTC(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    ERC20 internal constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    address internal constant STAKED_GMX =
        0x908C4D94D34924765f1eDc22A1DD098397c59dD4;

    PirexGmxGlp internal immutable pirexGmxGlp;
    PxGmx internal immutable pxGmx;
    PxGlp internal immutable pxGlp;
    PxGlpRewards internal immutable pxGlpRewards;

    address internal constant POSITION_ROUTER =
        0x3D6bA331e3D9702C5e8A8d254e5d8a285F223aba;
    uint256 internal constant FEE_BPS = 25;
    uint256 internal constant TAX_BPS = 50;
    uint256 internal constant BPS_DIVISOR = 10_000;
    uint256 internal constant SLIPPAGE = 30;
    uint256 internal constant PRECISION = 1e30;
    uint256 internal constant EXPANDED_GLP_DECIMALS = 18;
    uint256 internal constant INFO_USDG_AMOUNT = 1e18;

    address[3] internal testAccounts = [
        0x6Ecbe1DB9EF729CBe972C83Fb886247691Fb6beb,
        0xE36Ea790bc9d7AB70C55260C66D52b1eca985f84,
        0xE834EC434DABA538cd1b9Fe1582052B880BD7e63
    ];

    // For testing ETH transfers
    receive() external payable {}

    constructor() {
        pxGlpRewards = new PxGlpRewards();
        pxGmx = new PxGmx();
        pxGlp = new PxGlp(address(pxGlpRewards));
        pirexGmxGlp = new PirexGmxGlp(
            address(pxGmx),
            address(pxGlp),
            address(pxGlpRewards),
            STAKED_GMX
        );

        pxGmx.grantRole(pxGmx.MINTER_ROLE(), address(pirexGmxGlp));
        pxGlp.grantRole(pxGlp.MINTER_ROLE(), address(pirexGmxGlp));
        pxGlpRewards.setStrategyForRewards(pxGlp);
        pxGlpRewards.setPirexGmxGlp(pirexGmxGlp);
    }

    /**
        @notice Mint WBTC for testing ERC20 GLP minting
        @param  amount  uint256  Amount of WBTC
     */
    function _mintWbtc(uint256 amount) internal {
        // Set self to l2Gateway
        vm.store(
            address(WBTC),
            bytes32(uint256(204)),
            bytes32(uint256(uint160(address(this))))
        );

        WBTC.bridgeMint(address(this), amount);
    }

    /**
        @notice Mint GMX for pxGMX related tests
        @param  amount  uint256  Amount of GMX
     */
    function _mintGmx(uint256 amount) internal {
        // Simulate minting for GMX by impersonating the admin in the timelock contract
        // Using the current values as they do change based on which block is pinned for tests
        ITimelock gmxTimeLock = ITimelock(GMX.gov());
        address timelockAdmin = gmxTimeLock.admin();

        vm.startPrank(timelockAdmin);

        gmxTimeLock.signalMint(address(GMX), address(this), amount);

        vm.warp(block.timestamp + gmxTimeLock.buffer() + 1 hours);

        gmxTimeLock.processMint(address(GMX), address(this), amount);

        vm.stopPrank();
    }
}
