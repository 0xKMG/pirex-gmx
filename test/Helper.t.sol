// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {PxGmx} from "src/tokens/PxGmx.sol";
import {PxGlp} from "src/tokens/PxGlp.sol";
import {PirexRewards} from "src/PirexRewards.sol";
import {PirexFutures} from "src/PirexFutures.sol";
import {ERC1155PresetMinterSupply} from "src/tokens/ERC1155PresetMinterSupply.sol";
import {IRewardRouterV2} from "src/interfaces/IRewardRouterV2.sol";
import {IVaultReader} from "src/interfaces/IVaultReader.sol";
import {IGlpManager} from "src/interfaces/IGlpManager.sol";
import {IReader} from "src/interfaces/IReader.sol";
import {IGMX} from "src/interfaces/IGMX.sol";
import {ITimelock} from "src/interfaces/ITimelock.sol";
import {IWBTC} from "src/interfaces/IWBTC.sol";
import {Vault} from "src/external/Vault.sol";
import {RewardTracker} from "src/external/RewardTracker.sol";

contract Helper is Test {
    IRewardRouterV2 internal constant REWARD_ROUTER_V2 =
        IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    RewardTracker public constant REWARD_TRACKER_GMX =
        RewardTracker(0xd2D1162512F927a7e282Ef43a362659E4F2a728F);
    RewardTracker public constant REWARD_TRACKER_GLP =
        RewardTracker(0x4e971a87900b931fF39d1Aad67697F49835400b6);
    RewardTracker public constant REWARD_TRACKER_MP =
        RewardTracker(0x4d268a7d4C16ceB5a606c173Bd974984343fea13);
    RewardTracker internal constant FEE_STAKED_GLP =
        RewardTracker(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    RewardTracker internal constant STAKED_GMX =
        RewardTracker(0x908C4D94D34924765f1eDc22A1DD098397c59dD4);
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
    IERC20 internal constant USDG =
        IERC20(0x45096e7aA921f27590f8F19e457794EB09678141);
    IWBTC internal constant WBTC =
        IWBTC(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    ERC20 internal constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    PirexGmxGlp internal immutable pirexGmxGlp;
    PxGmx internal immutable pxGmx;
    PxGlp internal immutable pxGlp;
    PirexRewards internal immutable pirexRewards;
    PirexFutures internal immutable pirexFutures;
    ERC1155PresetMinterSupply internal immutable ypxGmx;
    ERC1155PresetMinterSupply internal immutable ypxGlp;

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

    event SetPirexRewards(address pirexRewards);

    // For testing ETH transfers
    receive() external payable {}

    constructor() {
        pirexRewards = new PirexRewards();
        pxGmx = new PxGmx(address(pirexRewards));
        pxGlp = new PxGlp(address(pirexRewards));
        ypxGmx = new ERC1155PresetMinterSupply("");
        ypxGlp = new ERC1155PresetMinterSupply("");
        pirexGmxGlp = new PirexGmxGlp(
            address(pxGmx),
            address(pxGlp),
            address(pirexRewards)
        );
        pirexFutures = new PirexFutures(
            address(pxGmx),
            address(pxGlp),
            address(ypxGmx),
            address(ypxGlp)
        );
        bytes32 minterRole = pxGmx.MINTER_ROLE();

        pxGmx.grantRole(minterRole, address(pirexGmxGlp));
        pxGlp.grantRole(minterRole, address(pirexGmxGlp));
        pirexGmxGlp.setPirexRewards(address(pirexRewards));
        pirexRewards.setProducer(address(pirexGmxGlp));
        ypxGmx.grantRole(minterRole, address(pirexFutures));
        ypxGlp.grantRole(minterRole, address(pirexFutures));

        // Unpause after completing the setup
        pirexGmxGlp.setPauseState(false);
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
        @notice Mint pxGMX or pxGLP
        @param  to      address  Recipient of pxGMX/pxGLP
        @param  amount  uint256  Amount of pxGMX/pxGLP
        @param  useGmx  bool     Whether to mint GMX variant
     */
    function _mintPx(
        address to,
        uint256 amount,
        bool useGmx
    ) internal {
        vm.prank(address(pirexGmxGlp));

        if (useGmx) {
            pxGmx.mint(to, amount);
        } else {
            pxGlp.mint(to, amount);
        }
    }

    /**
        @notice Burn pxGLP
        @param  from    address  Burn from account
        @param  amount  uint256  Amount of pxGLP
     */
    function _burnPxGlp(address from, uint256 amount) internal {
        vm.prank(address(pirexGmxGlp));

        pxGlp.burn(from, amount);
    }

    /**
        @notice Mint pxGMX or pxGLP for test accounts
        @param  useGmx      bool     Whether to use pxGMX
        @param  multiplier  uint256  Multiplied with fixed token amounts (uint256 to avoid overflow)
        @param  useETH      bool     Whether or not to use ETH as the source asset for minting GLP

     */
    function _depositForTestAccounts(
        bool useGmx,
        uint256 multiplier,
        bool useETH
    ) internal {
        if (useGmx) {
            _depositForTestAccountsPxGmx(multiplier);
        } else {
            _depositForTestAccountsPxGlp(multiplier, useETH);
        }
    }

    /**
        @notice Mint pxGMX for test accounts
        @param  multiplier  uint256  Multiplied with fixed token amounts (uint256 to avoid overflow)
     */
    function _depositForTestAccountsPxGmx(uint256 multiplier) internal {
        uint256 tLen = testAccounts.length;
        uint256[] memory tokenAmounts = new uint256[](tLen);
        tokenAmounts[0] = 1e18 * multiplier;
        tokenAmounts[1] = 2e18 * multiplier;
        tokenAmounts[2] = 3e18 * multiplier;
        uint256 total = tokenAmounts[0] + tokenAmounts[1] + tokenAmounts[2];

        _mintGmx(total);
        GMX.approve(address(pirexGmxGlp), total);

        // Iterate over test accounts and mint pxGLP for each to kick off reward accrual
        for (uint256 i; i < tLen; ++i) {
            uint256 tokenAmount = tokenAmounts[i];
            address testAccount = testAccounts[i];

            pirexGmxGlp.depositGmx(tokenAmount, testAccount);
        }
    }

    /**
        @notice Mint pxGLP for test accounts
        @param  multiplier  uint256  Multiplied with fixed token amounts (uint256 to avoid overflow)
        @param  useETH      bool     Whether or not to use ETH as the source asset for minting GLP
     */
    function _depositForTestAccountsPxGlp(uint256 multiplier, bool useETH)
        internal
    {
        uint256 tLen = testAccounts.length;
        uint256[] memory tokenAmounts = new uint256[](tLen);

        // Conditionally set ETH or WBTC amounts and call the appropriate method for acquiring
        if (useETH) {
            tokenAmounts[0] = 1 ether * multiplier;
            tokenAmounts[1] = 2 ether * multiplier;
            tokenAmounts[2] = 3 ether * multiplier;

            vm.deal(
                address(this),
                tokenAmounts[0] + tokenAmounts[1] + tokenAmounts[2]
            );
        } else {
            tokenAmounts[0] = 1e8 * multiplier;
            tokenAmounts[1] = 2e8 * multiplier;
            tokenAmounts[2] = 3e8 * multiplier;
            uint256 wBtcTotalAmount = tokenAmounts[0] +
                tokenAmounts[1] +
                tokenAmounts[2];

            _mintWbtc(wBtcTotalAmount);
            WBTC.approve(address(pirexGmxGlp), wBtcTotalAmount);
        }

        // Iterate over test accounts and mint pxGLP for each to kick off reward accrual
        for (uint256 i; i < tLen; ++i) {
            uint256 tokenAmount = tokenAmounts[i];
            address testAccount = testAccounts[i];

            // Call the appropriate method based on the type of currency
            if (useETH) {
                pirexGmxGlp.depositGlpWithETH{value: tokenAmount}(
                    1,
                    testAccount
                );
            } else {
                pirexGmxGlp.depositGlpWithERC20(
                    address(WBTC),
                    tokenAmount,
                    1,
                    testAccount
                );
            }
        }
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

    /**
        @notice Encode error for role-related reversion tests
        @param  caller  address  Method caller
        @param  role    bytes32  Role
        @return         bytes    Error bytes
     */
    function _encodeRoleError(address caller, bytes32 role)
        internal
        pure
        returns (bytes memory)
    {
        return
            bytes(
                abi.encodePacked(
                    "AccessControl: account ",
                    Strings.toHexString(uint160(caller), 20),
                    " is missing role ",
                    Strings.toHexString(uint256(role), 32)
                )
            );
    }

    function _getExpiry(uint256 index) internal view returns (uint256) {
        uint256 duration = pirexFutures.durations(index);

        return duration + ((block.timestamp / duration) * duration);
    }
}
