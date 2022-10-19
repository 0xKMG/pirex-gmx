// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PirexGmx} from "src/PirexGmx.sol";
import {PxGmx} from "src/PxGmx.sol";
import {PxERC20} from "src/PxERC20.sol";
import {PirexRewards} from "src/PirexRewards.sol";
import {PirexFees} from "src/PirexFees.sol";
import {GlobalState} from "src/Common.sol";
import {AutoPxGmx} from "src/vaults/AutoPxGmx.sol";
import {AutoPxGlp} from "src/vaults/AutoPxGlp.sol";
import {IRewardRouterV2} from "src/interfaces/IRewardRouterV2.sol";
import {IVaultReader} from "src/interfaces/IVaultReader.sol";
import {IGlpManager} from "src/interfaces/IGlpManager.sol";
import {IReader} from "src/interfaces/IReader.sol";
import {IGMX} from "src/interfaces/IGMX.sol";
import {ITimelock} from "src/interfaces/ITimelock.sol";
import {IWBTC} from "src/interfaces/IWBTC.sol";
import {IVault} from "src/interfaces/IVault.sol";
import {IRewardDistributor} from "src/interfaces/IRewardDistributor.sol";
import {RewardTracker} from "src/external/RewardTracker.sol";
import {IStakedGlp} from "src/interfaces/IStakedGlp.sol";
import {DelegateRegistry} from "src/external/DelegateRegistry.sol";
import {HelperEvents} from "./HelperEvents.sol";
import {HelperState} from "./HelperState.sol";

contract Helper is Test, HelperEvents, HelperState {
    IRewardRouterV2 internal constant REWARD_ROUTER_V2 =
        IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    IStakedGlp internal constant STAKED_GLP =
        IStakedGlp(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);
    IVaultReader internal constant VAULT_READER =
        IVaultReader(0xfebB9f4CAC4cD523598fE1C5771181440143F24A);
    IReader internal constant READER =
        IReader(0x22199a49A999c351eF7927602CFB187ec3cae489);
    address internal constant POSITION_ROUTER =
        0x3D6bA331e3D9702C5e8A8d254e5d8a285F223aba;
    IWBTC internal constant WBTC =
        IWBTC(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    uint256 internal constant FEE_BPS = 25;
    uint256 internal constant TAX_BPS = 50;
    uint256 internal constant BPS_DIVISOR = 10_000;
    uint256 internal constant SLIPPAGE = 30;
    uint256 internal constant PRECISION = 1e30;
    uint256 internal constant EXPANDED_GLP_DECIMALS = 18;
    uint256 internal constant INFO_USDG_AMOUNT = 1e18;
    bytes internal constant UNAUTHORIZED_ERROR = "UNAUTHORIZED";
    bytes internal constant NOT_OWNER_ERROR =
        "Ownable: caller is not the owner";
    // Arbitrary addresses used for testing fees
    address internal constant treasuryAddress =
        0xfCd72e7a92dE3a8D7611a17c85fff70d1BF44daD;
    address internal constant contributorsAddress =
        0xdEe242Fd5355D26ab571AE8efB9A6BB92f7c1a07;

    // Used as admin on upgradable contracts
    // We should not use any of the testAccounts as they won't be able to be used on related tests
    // due to the limitation of admin role in these proxy contracts
    address internal constant proxyAdmin =
        0x37c80252Ce544Be11F5bc24B0722DB8d483D0a4d;

    RewardTracker internal immutable rewardTrackerGmx;
    RewardTracker internal immutable rewardTrackerGlp;
    RewardTracker internal immutable rewardTrackerMp;
    RewardTracker internal immutable feeStakedGlp;
    RewardTracker internal immutable stakedGmx;
    IGlpManager internal immutable glpManager;
    IVault internal immutable vault;
    IGMX internal immutable gmx;
    ERC20 internal immutable weth;
    IERC20 internal immutable usdg;
    address internal immutable bnGmx;
    address internal immutable esGmx;
    PirexGmx internal immutable pirexGmx;
    PxGmx internal immutable pxGmx;
    AutoPxGmx internal immutable autoPxGmx;
    AutoPxGlp internal immutable autoPxGlp;
    PxERC20 internal immutable pxGlp;
    PirexRewards internal immutable pirexRewards;
    PirexFees internal immutable pirexFees;
    DelegateRegistry internal immutable delegateRegistry;

    address[3] internal testAccounts = [
        0x6Ecbe1DB9EF729CBe972C83Fb886247691Fb6beb,
        0xE36Ea790bc9d7AB70C55260C66D52b1eca985f84,
        0xE834EC434DABA538cd1b9Fe1582052B880BD7e63
    ];

    // For testing ETH transfers
    receive() external payable {}

    constructor() {
        // Deploying our own delegateRegistry since no official one exists yet in Arbitrum
        delegateRegistry = new DelegateRegistry();

        rewardTrackerGmx = RewardTracker(REWARD_ROUTER_V2.feeGmxTracker());
        rewardTrackerGlp = RewardTracker(REWARD_ROUTER_V2.feeGlpTracker());
        rewardTrackerMp = RewardTracker(REWARD_ROUTER_V2.bonusGmxTracker());
        feeStakedGlp = RewardTracker(REWARD_ROUTER_V2.stakedGlpTracker());
        stakedGmx = RewardTracker(REWARD_ROUTER_V2.stakedGmxTracker());
        glpManager = IGlpManager(REWARD_ROUTER_V2.glpManager());
        gmx = IGMX(REWARD_ROUTER_V2.gmx());
        weth = ERC20(REWARD_ROUTER_V2.weth());
        bnGmx = REWARD_ROUTER_V2.bnGmx();
        esGmx = REWARD_ROUTER_V2.esGmx();
        vault = IVault(glpManager.vault());
        usdg = IERC20(glpManager.usdg());

        // Deploy the upgradable pirexRewards contract instance
        // Note that we are using special address as admin so that less prank calls are needed
        // to call methods in most PirexRewards tests (as admin can't fallback on the proxy impl. methods)
        PirexRewards pirexRewardsImplementation = new PirexRewards();
        TransparentUpgradeableProxy pirexRewardsProxy = new TransparentUpgradeableProxy(
            address(pirexRewardsImplementation),
            proxyAdmin, // Admin address
            abi.encodeWithSelector(PirexRewards.initialize.selector)
        );
        address pirexRewardsProxyAddr = address(pirexRewardsProxy);
        pirexRewards = PirexRewards(pirexRewardsProxyAddr);

        pxGmx = new PxGmx(address(pirexRewardsProxyAddr));
        pxGlp = new PxERC20(
            address(pirexRewardsProxyAddr),
            "Pirex GLP",
            "pxGLP",
            18
        );
        pirexFees = new PirexFees(treasuryAddress, contributorsAddress);
        pirexGmx = new PirexGmx(
            address(pxGmx),
            address(pxGlp),
            address(pirexFees),
            address(pirexRewardsProxyAddr),
            address(delegateRegistry),
            address(REWARD_ROUTER_V2),
            address(STAKED_GLP)
        );
        autoPxGmx = new AutoPxGmx(
            address(pxGmx),
            "Autocompounding pxGMX",
            "apxGMX",
            address(pirexGmx),
            address(pirexRewardsProxyAddr)
        );
        autoPxGlp = new AutoPxGlp(
            address(pxGlp),
            address(pxGmx),
            "Autocompounding pxGLP",
            "apxGLP",
            address(pirexGmx),
            address(pirexRewardsProxyAddr)
        );

        pxGmx.grantRole(pxGmx.MINTER_ROLE(), address(pirexGmx));
        pxGlp.grantRole(pxGlp.MINTER_ROLE(), address(pirexGmx));
        pxGlp.grantRole(pxGlp.BURNER_ROLE(), address(pirexGmx));
        pirexRewards.setProducer(address(pirexGmx));

        // Unpause after completing the setup
        pirexGmx.setPauseState(false);

        feeMax = pirexGmx.FEE_MAX();
        feeTypes[0] = PirexGmx.Fees.Deposit;
        feeTypes[1] = PirexGmx.Fees.Redemption;
        feeTypes[2] = PirexGmx.Fees.Reward;
        feeDenominator = pirexGmx.FEE_DENOMINATOR();
        delegationSpace = pirexGmx.delegationSpace();
        feePercentDenominator = pirexFees.FEE_PERCENT_DENOMINATOR();
        maxTreasuryFeePercent = pirexFees.MAX_TREASURY_FEE_PERCENT();
        treasuryFeePercent = pirexFees.treasuryFeePercent();
        treasury = pirexFees.treasury();
        contributors = pirexFees.contributors();
    }

    /**
        @notice Mint WBTC for testing ERC20 GLP minting
        @param  amount    uint256  WBTC amount
        @param  receiver  address  WBTC receiver
     */
    function _mintWbtc(uint256 amount, address receiver) internal {
        // Set self to l2Gateway
        vm.store(
            address(WBTC),
            bytes32(uint256(204)),
            bytes32(uint256(uint160(address(this))))
        );

        WBTC.bridgeMint(receiver, amount);
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
        vm.prank(address(pirexGmx));

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
        vm.prank(address(pirexGmx));

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
            _depositGmxForTestAccounts(true, address(this), multiplier);
        } else {
            _depositGlpForTestAccounts(true, address(this), multiplier, useETH);
        }
    }

    /**
        @notice Deposit GMX and mint pxGMX for test accounts
        @param  separateCaller  bool       Whether to separate depositor (depositGmx caller) and receiver
        @param  caller          address    Account calling the minting, approving, and depositing methods
        @param  multiplier      uint256    Multiplied with fixed token amounts (uint256 to avoid overflow)
        @return depositAmounts  uint256[]  GMX deposited and pxGMX minted for each test account
     */
    function _depositGmxForTestAccounts(
        bool separateCaller,
        address caller,
        uint256 multiplier
    ) internal returns (uint256[] memory depositAmounts) {
        uint256 tLen = testAccounts.length;
        depositAmounts = new uint256[](tLen);
        depositAmounts[0] = 1e18 * multiplier;
        depositAmounts[1] = 2e18 * multiplier;
        depositAmounts[2] = 3e18 * multiplier;

        // Iterate over test accounts and mint pxGLP for each to kick off reward accrual
        for (uint256 i; i < tLen; ++i) {
            uint256 depositAmount = depositAmounts[i];
            address testAccount = testAccounts[i];

            caller = separateCaller ? caller : testAccount;

            _mintApproveGmx(
                depositAmount,
                caller,
                address(pirexGmx),
                depositAmount
            );

            (uint256 postFeeAmount, uint256 feeAmount) = _computeAssetAmounts(
                PirexGmx.Fees.Deposit,
                depositAmount
            );

            vm.prank(caller);
            vm.expectEmit(true, true, false, true, address(pirexGmx));

            emit DepositGmx(
                caller,
                testAccount,
                depositAmount,
                postFeeAmount,
                feeAmount
            );

            (
                uint256 deposited,
                uint256 depositPostFeeAmount,
                uint256 depositFeeAmount
            ) = pirexGmx.depositGmx(depositAmount, testAccount);

            assertEq(deposited, depositPostFeeAmount + feeAmount);
            assertEq(postFeeAmount, depositPostFeeAmount);
            assertEq(feeAmount, depositFeeAmount);
        }
    }

    /**
        @notice Deposit GLP and mint pxGLP for test accounts
        @param  separateCaller  bool       Whether to separate depositor (depositGmx caller) and receiver
        @param  caller          address    Account calling the minting, approving, and depositing methods
        @param  multiplier      uint256    Multiplied with fixed token amounts (uint256 to avoid overflow)
        @param  useETH          bool       Whether or not to use ETH as the source asset for minting GLP
        @return depositAmounts  uint256[]  GLP deposited for each test account
     */
    function _depositGlpForTestAccounts(
        bool separateCaller,
        address caller,
        uint256 multiplier,
        bool useETH
    ) internal returns (uint256[] memory depositAmounts) {
        uint256 tLen = testAccounts.length;

        // Only used locally to track token amounts used to mint GLP
        uint256[] memory tokenAmounts = new uint256[](tLen);

        depositAmounts = new uint256[](tLen);

        // Iterate over test accounts and mint pxGLP for each to kick off reward accrual
        for (uint256 i; i < tLen; ++i) {
            address testAccount = testAccounts[i];
            caller = separateCaller ? caller : testAccount;
            uint256 deposited;
            uint256 depositPostFeeAmount;
            uint256 depositFeeAmount;

            // Conditionally set ETH or WBTC amounts and call the appropriate method for acquiring
            if (useETH) {
                tokenAmounts[0] = 1 ether * multiplier;
                tokenAmounts[1] = 2 ether * multiplier;
                tokenAmounts[2] = 3 ether * multiplier;
                uint256 total = tokenAmounts[0] +
                    tokenAmounts[1] +
                    tokenAmounts[2];

                vm.deal(caller, total);
                vm.prank(caller);
                vm.expectEmit(true, true, true, false, address(pirexGmx));

                emit DepositGlp(
                    caller,
                    testAccount,
                    address(0),
                    total,
                    1,
                    1,
                    0,
                    0,
                    0
                );

                (deposited, depositPostFeeAmount, depositFeeAmount) = pirexGmx
                    .depositGlpETH{value: total}(1, 1, testAccount);
            } else {
                tokenAmounts[0] = 1e8 * multiplier;
                tokenAmounts[1] = 2e8 * multiplier;
                tokenAmounts[2] = 3e8 * multiplier;
                uint256 wBtcTotalAmount = tokenAmounts[0] +
                    tokenAmounts[1] +
                    tokenAmounts[2];

                _mintWbtc(wBtcTotalAmount, caller);

                vm.prank(caller);

                WBTC.approve(address(pirexGmx), wBtcTotalAmount);

                vm.prank(caller);
                vm.expectEmit(true, true, true, false, address(pirexGmx));

                emit DepositGlp(
                    caller,
                    testAccount,
                    address(WBTC),
                    wBtcTotalAmount,
                    1,
                    1,
                    0,
                    0,
                    0
                );

                (deposited, depositPostFeeAmount, depositFeeAmount) = pirexGmx
                    .depositGlp(
                        address(WBTC),
                        wBtcTotalAmount,
                        1,
                        1,
                        testAccount
                    );
            }

            depositAmounts[i] = deposited;
            (uint256 postFeeAmount, uint256 feeAmount) = _computeAssetAmounts(
                PirexGmx.Fees.Deposit,
                deposited
            );

            assertEq(deposited, depositPostFeeAmount + feeAmount);
            assertEq(postFeeAmount, depositPostFeeAmount);
            assertEq(feeAmount, depositFeeAmount);
        }
    }

    /**
        @notice Mint GMX for pxGMX related tests
        @param  amount            uint256  GMX amount
        @param  receiver          address  GMX receiver
        @param  spender           address  GMX spender
        @param  spenderAllowance  uint256  GMX spender allowance
     */
    function _mintApproveGmx(
        uint256 amount,
        address receiver,
        address spender,
        uint256 spenderAllowance
    ) internal {
        vm.prank(receiver);

        gmx.approve(spender, spenderAllowance);

        // Simulate minting for GMX by impersonating the admin in the timelock contract
        // Using the current values as they do change based on which block is pinned for tests
        ITimelock gmxTimeLock = ITimelock(gmx.gov());
        address timelockAdmin = gmxTimeLock.admin();

        vm.startPrank(timelockAdmin);

        gmxTimeLock.signalMint(address(gmx), receiver, amount);

        vm.warp(block.timestamp + gmxTimeLock.buffer() + 1 hours);

        gmxTimeLock.processMint(address(gmx), receiver, amount);

        vm.stopPrank();
    }

    /**
        @notice Mint fsGLP and approve pirexGmx with a transfer allowance
        @param  ethAmount  uint256  ETH amount used to mint fsGLP
        @param  receiver   address  fsGLP receiver
        @return fsGlp      uint256  fsGLP mint/approval amount
     */
    function _mintAndApproveFsGlp(uint256 ethAmount, address receiver)
        internal
        returns (uint256 fsGlp)
    {
        assertEq(0, feeStakedGlp.balanceOf(receiver));

        vm.deal(receiver, ethAmount);
        vm.startPrank(receiver);

        fsGlp = REWARD_ROUTER_V2.mintAndStakeGlpETH{value: ethAmount}(1, 1);

        vm.warp(block.timestamp + 1 hours);

        STAKED_GLP.approve(address(pirexGmx), fsGlp);

        vm.stopPrank();

        assertEq(fsGlp, feeStakedGlp.balanceOf(receiver));
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
                address(vault),
                POSITION_ROUTER,
                address(weth),
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
        tokens[0] = address(feeStakedGlp);
        uint256 aum = glpManager.getAums()[minPrice ? 0 : 1];
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
        uint256 targetAmount = (info[4] * usdg.totalSupply()) /
            vault.totalTokenWeights();

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
        // Perform identical formula with GMX Vault's due to potential rounding error issue
        // and without slippage to get exact amount of expected GLP
        uint256[] memory info = _getVaultTokenInfo(token);
        uint256 afterFees = (amount *
            (BPS_DIVISOR - _getFees(amount, info, true))) / BPS_DIVISOR;
        uint256 usdgAfterFees = (afterFees * info[10]) / PRECISION;
        address[] memory tokens = new address[](1);
        tokens[0] = address(feeStakedGlp);
        uint256 aum = glpManager.getAums()[0];
        uint256 glpSupply = READER.getTokenBalancesWithSupplies(
            address(0),
            tokens
        )[1];

        uint256 minGlp = (usdgAfterFees * glpSupply) /
            ((aum * 10**EXPANDED_GLP_DECIMALS) / PRECISION);

        // Expand min GLP amount decimals based on the input token's decimals
        return
            decimals == EXPANDED_GLP_DECIMALS
                ? minGlp
                : 10**(EXPANDED_GLP_DECIMALS - decimals) * minGlp;
    }

    /**
        @notice Calculate the minimum token output amount from redeeming GLP
        @param  token   address  Token address
        @param  amount  uint256  Amount of tokens
        @return         uint256  Minimum GLP amount with slippage and decimal expansion
     */
    function _calculateMinOutAmount(address token, uint256 amount)
        internal
        view
        returns (uint256)
    {
        uint256[] memory info = _getVaultTokenInfo(token);
        uint256 usdgAmount = (amount * _getGlpPrice(false)) / PRECISION;
        uint256 redemptionAmount = vault.getRedemptionAmount(token, usdgAmount);
        uint256 minToken = (redemptionAmount *
            (BPS_DIVISOR - _getFees(redemptionAmount, info, false))) /
            BPS_DIVISOR;
        uint256 minTokenWithSlippage = (minToken * (BPS_DIVISOR - SLIPPAGE)) /
            BPS_DIVISOR;

        return minTokenWithSlippage;
    }

    /**
        @notice Deposit ETH for pxGLP for testing purposes
        @param  etherAmount     uint256  Amount of ETH
        @param  receiver        address  Receiver of pxGLP
        @param  secondsElapsed  uint32   Seconds to forward timestamp
        @return postFeeAmount   uint256  pxGLP minted for the receiver
        @return feeAmount       uint256  pxGLP distributed as fees
     */
    function _depositGlpETHWithTimeSkip(
        uint256 etherAmount,
        address receiver,
        uint256 secondsElapsed
    ) internal returns (uint256 postFeeAmount, uint256 feeAmount) {
        vm.deal(address(this), etherAmount);

        (, postFeeAmount, feeAmount) = pirexGmx.depositGlpETH{
            value: etherAmount
        }(1, 1, receiver);

        vm.warp(block.timestamp + secondsElapsed);
    }

    /**
        @notice Deposit ETH for pxGLP for testing purposes
        @param  etherAmount    uint256  Amount of ETH
        @param  receiver       address  Receiver of pxGLP
        @return postFeeAmount  uint256  pxGLP minted for the receiver
        @return feeAmount      uint256  pxGLP distributed as fees
     */
    function _depositGlpETH(uint256 etherAmount, address receiver)
        internal
        returns (uint256 postFeeAmount, uint256 feeAmount)
    {
        // Use the standard 1-hour time skip
        return _depositGlpETHWithTimeSkip(etherAmount, receiver, 1 hours);
    }

    /**
        @notice Deposit ERC20 token (WBTC) for pxGLP for testing purposes
        @param  tokenAmount    uint256  Amount of token
        @param  receiver       address  Receiver of pxGLP
        @return deposited      uint256  GLP deposited
        @return postFeeAmount  uint256  pxGLP minted for the receiver
        @return feeAmount      uint256  pxGLP distributed as fees
     */
    function _depositGlp(uint256 tokenAmount, address receiver)
        internal
        returns (
            uint256 deposited,
            uint256 postFeeAmount,
            uint256 feeAmount
        )
    {
        _mintWbtc(tokenAmount, address(this));
        WBTC.approve(address(pirexGmx), tokenAmount);

        (deposited, postFeeAmount, feeAmount) = pirexGmx.depositGlp(
            address(WBTC),
            tokenAmount,
            1,
            1,
            receiver
        );

        // Time skip to bypass the cooldown duration
        vm.warp(block.timestamp + 1 hours);
    }

    /**
        @notice Deposit GMX for pxGMX
        @param  tokenAmount  uint256  Amount of token
        @param  receiver     address  Receiver of pxGMX
     */
    function _depositGmx(uint256 tokenAmount, address receiver) internal {
        _mintApproveGmx(
            tokenAmount,
            address(this),
            address(pirexGmx),
            tokenAmount
        );
        pirexGmx.depositGmx(tokenAmount, receiver);
    }

    /**
        @notice Precise calculations for bnGMX rewards (i.e. multiplier points)
        @param  account  address  Account with bnGMX rewards
        @return          uint256  bnGMX amount
     */
    function calculateBnGmxRewards(address account)
        public
        view
        returns (uint256)
    {
        address distributor = rewardTrackerMp.distributor();
        uint256 pendingRewards = IRewardDistributor(distributor)
            .pendingRewards();
        uint256 distributorBalance = ERC20(bnGmx).balanceOf(distributor);
        uint256 blockReward = pendingRewards > distributorBalance
            ? distributorBalance
            : pendingRewards;
        uint256 precision = rewardTrackerMp.PRECISION();
        uint256 cumulativeRewardPerToken = rewardTrackerMp
            .cumulativeRewardPerToken() +
            ((blockReward * precision) / rewardTrackerMp.totalSupply());

        if (cumulativeRewardPerToken == 0) return 0;

        return
            rewardTrackerMp.claimableReward(account) +
            ((rewardTrackerMp.stakedAmounts(account) *
                (cumulativeRewardPerToken -
                    rewardTrackerMp.previousCumulatedRewardPerToken(account))) /
                precision);
    }

    /**
        @notice Compute post-fee asset and fee amounts from a fee type and total assets
        @param  f              Fees     Fee type
        @param  assets         uint256  GMX/GLP/WETH asset amount
        @return postFeeAmount  uint256  Post-fee asset amount (for mint/burn/claim/etc.)
        @return feeAmount      uint256  Fee amount
     */
    function _computeAssetAmounts(PirexGmx.Fees f, uint256 assets)
        internal
        view
        returns (uint256 postFeeAmount, uint256 feeAmount)
    {
        feeAmount = (assets * pirexGmx.fees(f)) / pirexGmx.FEE_DENOMINATOR();
        postFeeAmount = assets - feeAmount;
    }

    /**
        @notice Calculate the WETH/esGMX rewards for either GMX or GLP
        @param  account  address  Whether to calculate WETH or esGMX rewards
        @param  isWeth   bool     Whether to calculate WETH or esGMX rewards
        @param  useGmx   bool     Whether the calculation should be for GMX
        @return         uint256   Amount of WETH/esGMX rewards
     */
    function _calculateRewards(
        address account,
        bool isWeth,
        bool useGmx
    ) internal view returns (uint256) {
        RewardTracker r;

        if (isWeth) {
            r = useGmx ? rewardTrackerGmx : rewardTrackerGlp;
        } else {
            r = useGmx ? stakedGmx : feeStakedGlp;
        }

        address distributor = r.distributor();
        uint256 pendingRewards = IRewardDistributor(distributor)
            .pendingRewards();
        uint256 distributorBalance = (isWeth ? weth : ERC20(esGmx)).balanceOf(
            distributor
        );
        uint256 blockReward = pendingRewards > distributorBalance
            ? distributorBalance
            : pendingRewards;
        uint256 precision = r.PRECISION();
        uint256 cumulativeRewardPerToken = r.cumulativeRewardPerToken() +
            ((blockReward * precision) / r.totalSupply());

        if (cumulativeRewardPerToken == 0) return 0;

        return
            r.claimableReward(account) +
            ((r.stakedAmounts(account) *
                (cumulativeRewardPerToken -
                    r.previousCumulatedRewardPerToken(account))) / precision);
    }

    /**
        @notice Getter for a producer token's global state
    */
    function _getGlobalState(ERC20 producerToken)
        internal
        view
        returns (
            uint256 lastUpdate,
            uint256 lastSupply,
            uint256 rewards
        )
    {
        GlobalState memory globalState = pirexRewards.producerTokens(
            producerToken
        );

        return (
            globalState.lastUpdate,
            globalState.lastSupply,
            globalState.rewards
        );
    }

    /**
        @notice Calculate the global rewards accrued since the last update
        @param  producerToken  ERC20    Producer token
        @return                uint256  Global rewards
    */
    function _calculateGlobalRewards(ERC20 producerToken)
        internal
        view
        returns (uint256)
    {
        (
            uint256 lastUpdate,
            uint256 lastSupply,
            uint256 rewards
        ) = _getGlobalState(producerToken);

        return rewards + (block.timestamp - lastUpdate) * lastSupply;
    }

    /**
        @notice Calculate a user's rewards since the last update
        @param  producerToken  ERC20    Producer token contract
        @param  user           address  User
        @return                uint256  User rewards
    */
    function _calculateUserRewards(ERC20 producerToken, address user)
        internal
        view
        returns (uint256)
    {
        (
            uint256 lastUpdate,
            uint256 lastBalance,
            uint256 rewards
        ) = pirexRewards.getUserState(producerToken, user);

        return rewards + lastBalance * (block.timestamp - lastUpdate);
    }
}
