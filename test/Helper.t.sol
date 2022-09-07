// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {PxGmx} from "src/PxGmx.sol";
import {PxGlp} from "src/PxGlp.sol";
import {PirexRewards} from "src/PirexRewards.sol";
import {PirexFees} from "src/PirexFees.sol";
import {AutoPxGmx} from "src/vaults/AutoPxGmx.sol";
import {IRewardRouterV2} from "src/interfaces/IRewardRouterV2.sol";
import {IVaultReader} from "src/interfaces/IVaultReader.sol";
import {IGlpManager} from "src/interfaces/IGlpManager.sol";
import {IReader} from "src/interfaces/IReader.sol";
import {IGMX} from "src/interfaces/IGMX.sol";
import {ITimelock} from "src/interfaces/ITimelock.sol";
import {IWBTC} from "src/interfaces/IWBTC.sol";
import {Vault} from "src/external/Vault.sol";
import {RewardTracker} from "src/external/RewardTracker.sol";
import {DelegateRegistry} from "src/external/DelegateRegistry.sol";

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

    address internal constant POSITION_ROUTER =
        0x3D6bA331e3D9702C5e8A8d254e5d8a285F223aba;
    uint256 internal constant FEE_BPS = 25;
    uint256 internal constant TAX_BPS = 50;
    uint256 internal constant BPS_DIVISOR = 10_000;
    uint256 internal constant SLIPPAGE = 30;
    uint256 internal constant PRECISION = 1e30;
    uint256 internal constant EXPANDED_GLP_DECIMALS = 18;
    uint256 internal constant INFO_USDG_AMOUNT = 1e18;

    PirexGmxGlp internal immutable pirexGmxGlp;
    PxGmx internal immutable pxGmx;
    AutoPxGmx internal immutable autoPxGmx;
    PxGlp internal immutable pxGlp;
    PirexRewards internal immutable pirexRewards;
    PirexFees internal immutable pirexFees;
    DelegateRegistry internal immutable delegateRegistry;
    uint256 internal immutable feeMax;

    address[3] internal testAccounts = [
        0x6Ecbe1DB9EF729CBe972C83Fb886247691Fb6beb,
        0xE36Ea790bc9d7AB70C55260C66D52b1eca985f84,
        0xE834EC434DABA538cd1b9Fe1582052B880BD7e63
    ];

    PirexGmxGlp.Fees[3] internal feeTypes;

    bytes internal constant UNAUTHORIZED_ERROR = "UNAUTHORIZED";
    bytes internal constant NOT_OWNER_ERROR =
        "Ownable: caller is not the owner";

    event SetPirexRewards(address pirexRewards);
    event SetFeeRecipient(PirexFees.FeeRecipient f, address recipient);
    event SetTreasuryPercent(uint8 _treasuryPercent);
    event DistributeFees(address token, uint256 amount);
    event DepositGmx(
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 postFeeAmount,
        uint256 feeAmount
    );
    event DepositGlp(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 minUsdg,
        uint256 minGlp,
        uint256 amount,
        uint256 assets,
        uint256 mintAmount,
        uint256 feeAmount
    );
    event RedeemGlp(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 minRedemption,
        uint256 amount,
        uint256 redemption,
        uint256 burnAmount,
        uint256 feeAmount
    );

    // For testing ETH transfers
    receive() external payable {}

    constructor() {
        // Deploying our own delegateRegistry since no official one exists yet in Arbitrum
        delegateRegistry = new DelegateRegistry();

        // Use normal (non-upgradeable) instance for most tests (outside the upgrade test)
        pirexRewards = new PirexRewards();
        pirexRewards.initialize();
        pxGmx = new PxGmx(address(pirexRewards));
        pxGlp = new PxGlp(address(pirexRewards));
        pirexFees = new PirexFees(testAccounts[0], testAccounts[1]);
        pirexGmxGlp = new PirexGmxGlp(
            address(pxGmx),
            address(pxGlp),
            address(pirexFees),
            address(pirexRewards),
            address(delegateRegistry)
        );
        autoPxGmx = new AutoPxGmx(
            address(pxGmx),
            "Autocompounding pxGMX",
            "apxGMX",
            address(pirexGmxGlp)
        );

        pxGmx.grantRole(pxGmx.MINTER_ROLE(), address(pirexGmxGlp));
        pxGlp.grantRole(pxGlp.MINTER_ROLE(), address(pirexGmxGlp));
        pirexGmxGlp.setPirexRewards(address(pirexRewards));
        pirexRewards.setProducer(address(pirexGmxGlp));

        // Unpause after completing the setup
        pirexGmxGlp.setPauseState(false);

        feeMax = pirexGmxGlp.FEE_MAX();
        feeTypes[0] = PirexGmxGlp.Fees.Deposit;
        feeTypes[1] = PirexGmxGlp.Fees.Redemption;
        feeTypes[2] = PirexGmxGlp.Fees.Reward;
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
                pirexGmxGlp.depositGlpETH{value: tokenAmount}(
                    1,
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

    /**
        @notice Get minimum price for whitelisted token
        @param  token  address    Token
        @return        uint256[]  Vault token info for token
     */
    function _getVaultTokenInfo(address token)
        internal
        view
        returns (uint256[] memory)
    {
        address[] memory tokens = new address[](1);
        tokens[0] = token;

        return
            VAULT_READER.getVaultTokenInfoV4(
                address(VAULT),
                POSITION_ROUTER,
                address(WETH),
                INFO_USDG_AMOUNT,
                tokens
            );
    }

    /**
        @notice Get GLP price
        @param  minPrice  bool     Whether to use minimum or maximum price
        @return           uint256  GLP price
     */
    function _getGlpPrice(bool minPrice) internal view returns (uint256) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(FEE_STAKED_GLP);
        uint256 aum = GLP_MANAGER.getAums()[minPrice ? 0 : 1];
        uint256 glpSupply = READER.getTokenBalancesWithSupplies(
            address(0),
            tokens
        )[1];

        return (aum * 10**EXPANDED_GLP_DECIMALS) / glpSupply;
    }

    /**
        @notice Get GLP buying fees
        @param  tokenAmount  uint256    Token amount
        @param  info         uint256[]  Token info
        @param  incremental  bool       Whether the operation would increase USDG supply
        @return              uint256    GLP buying fees
     */
    function _getFees(
        uint256 tokenAmount,
        uint256[] memory info,
        bool incremental
    ) internal view returns (uint256) {
        uint256 initialAmount = info[2];
        uint256 usdgDelta = ((tokenAmount * info[10]) / PRECISION);
        uint256 nextAmount = initialAmount + usdgDelta;
        if (!incremental) {
            nextAmount = usdgDelta > initialAmount
                ? 0
                : initialAmount - usdgDelta;
        }
        uint256 targetAmount = (info[4] * USDG.totalSupply()) /
            VAULT.totalTokenWeights();

        if (targetAmount == 0) {
            return FEE_BPS;
        }

        uint256 initialDiff = initialAmount > targetAmount
            ? initialAmount - targetAmount
            : targetAmount - initialAmount;
        uint256 nextDiff = nextAmount > targetAmount
            ? nextAmount - targetAmount
            : targetAmount - nextAmount;

        if (nextDiff < initialDiff) {
            uint256 rebateBps = (TAX_BPS * initialDiff) / targetAmount;

            return rebateBps > FEE_BPS ? 0 : FEE_BPS - rebateBps;
        }

        uint256 averageDiff = (initialDiff + nextDiff) / 2;

        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }

        return FEE_BPS + (TAX_BPS * averageDiff) / targetAmount;
    }

    /**
        @notice Calculate the minimum amount of GLP received
        @param  token     address  Token address
        @param  amount    uint256  Amount of tokens
        @param  decimals  uint256  Token decimals for expansion purposes
        @return           uint256  Minimum GLP amount with slippage and decimal expansion
     */
    function _calculateMinGlpAmount(
        address token,
        uint256 amount,
        uint256 decimals
    ) internal view returns (uint256) {
        uint256[] memory info = _getVaultTokenInfo(token);
        uint256 glpAmount = (amount * info[10]) / _getGlpPrice(true);
        uint256 minGlp = (glpAmount *
            (BPS_DIVISOR - _getFees(amount, info, true))) / BPS_DIVISOR;
        uint256 minGlpWithSlippage = (minGlp * (BPS_DIVISOR - SLIPPAGE)) /
            BPS_DIVISOR;

        // Expand min GLP amount decimals based on the input token's decimals
        return
            decimals == EXPANDED_GLP_DECIMALS
                ? minGlpWithSlippage
                : 10**(EXPANDED_GLP_DECIMALS - decimals) * minGlpWithSlippage;
    }

    /**
        @notice Calculate the minimum amount of token to be redeemed from selling GLP
        @param  token     address  Token address
        @param  amount    uint256  Amount of tokens
        @return           uint256  Minimum GLP amount with slippage and decimal expansion
     */
    function _calculateMinRedemptionAmount(address token, uint256 amount)
        internal
        view
        returns (uint256)
    {
        uint256[] memory info = _getVaultTokenInfo(token);
        uint256 usdgAmount = (amount * _getGlpPrice(false)) / PRECISION;
        uint256 redemptionAmount = VAULT.getRedemptionAmount(token, usdgAmount);
        uint256 minToken = (redemptionAmount *
            (BPS_DIVISOR - _getFees(redemptionAmount, info, false))) /
            BPS_DIVISOR;
        uint256 minTokenWithSlippage = (minToken * (BPS_DIVISOR - SLIPPAGE)) /
            BPS_DIVISOR;

        return minTokenWithSlippage;
    }

    /**
        @notice Deposit ETH for pxGLP for testing purposes
        @param  etherAmount  uint256  Amount of ETH
        @param  receiver     address  Receiver of pxGLP
        @return              uint256  Amount of pxGLP minted
     */
    function _depositGlpETH(uint256 etherAmount, address receiver)
        internal
        returns (uint256)
    {
        vm.deal(address(this), etherAmount);

        uint256 assets = pirexGmxGlp.depositGlpETH{value: etherAmount}(
            1,
            1,
            receiver
        );

        // Time skip to bypass the cooldown duration
        vm.warp(block.timestamp + 1 hours);

        return assets;
    }

    /**
        @notice Deposit ERC20 token (WBTC) for pxGLP for testing purposes
        @param  tokenAmount  uint256  Amount of token
        @param  receiver     address  Receiver of pxGLP
        @return              uint256  Amount of pxGLP minted
     */
    function _depositGlpWithERC20(uint256 tokenAmount, address receiver)
        internal
        returns (uint256)
    {
        _mintWbtc(tokenAmount);

        WBTC.approve(address(pirexGmxGlp), tokenAmount);

        uint256 assets = pirexGmxGlp.depositGlpWithERC20(
            address(WBTC),
            tokenAmount,
            1,
            receiver
        );

        // Time skip to bypass the cooldown duration
        vm.warp(block.timestamp + 1 hours);

        return assets;
    }

    /**
        @notice Deposit GMX for pxGMX
        @param  tokenAmount  uint256  Amount of token
        @param  receiver     address  Receiver of pxGMX
     */
    function _depositGmx(uint256 tokenAmount, address receiver) internal {
        _mintGmx(tokenAmount);
        GMX.approve(address(pirexGmxGlp), tokenAmount);
        pirexGmxGlp.depositGmx(tokenAmount, receiver);
    }
}
