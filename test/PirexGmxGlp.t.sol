// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {Vault} from "src/external/Vault.sol";
import {IRewardDistributor} from "src/interfaces/IRewardDistributor.sol";
import {Helper} from "./Helper.t.sol";

contract PirexGmxGlpTest is Helper {
    event DepositGmx(
        address indexed caller,
        address indexed receiver,
        uint256 amount
    );
    event DepositGlp(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 minShares,
        uint256 amount,
        uint256 assets
    );
    event RedeemGlp(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 minRedemption,
        uint256 amount,
        uint256 redemption
    );
    event InitiateMigration(address newContract);
    event CompleteMigration(address oldContract);
    event ClaimRewards(
        uint256 wethRewards,
        uint256 esGmxRewards,
        uint256 gmxWethRewards,
        uint256 glpWethRewards,
        uint256 gmxEsGmxRewards,
        uint256 glpEsGmxRewards
    );

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
    function _depositGlpWithETH(uint256 etherAmount, address receiver)
        internal
        returns (uint256)
    {
        vm.deal(address(this), etherAmount);

        uint256 assets = pirexGmxGlp.depositGlpWithETH{value: etherAmount}(
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

    /*//////////////////////////////////////////////////////////////
                        setPirexRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to caller not being owner
     */
    function testCannotSetPirexRewardsUnauthorized() external {
        address _pirexRewards = address(this);

        vm.prank(testAccounts[0]);
        vm.expectRevert("UNAUTHORIZED");

        pirexGmxGlp.setPirexRewards(_pirexRewards);
    }

    /**
        @notice Test tx reversion due to _pirexRewards being zero
     */
    function testCannotSetPirexRewardsZeroAddress() external {
        address invalidPirexRewards = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.setPirexRewards(invalidPirexRewards);
    }

    /**
        @notice Test setting pirexRewards
     */
    function testSetPirexRewards() external {
        address pirexRewardsBefore = address(pirexGmxGlp.pirexRewards());
        address _pirexRewards = address(this);

        assertTrue(pirexRewardsBefore != _pirexRewards);

        vm.expectEmit(false, false, false, true, address(pirexGmxGlp));

        emit SetPirexRewards(_pirexRewards);

        pirexGmxGlp.setPirexRewards(_pirexRewards);

        assertEq(_pirexRewards, address(pirexGmxGlp.pirexRewards()));
    }

    /*//////////////////////////////////////////////////////////////
                        depositGmx TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion if contract is paused
     */
    function testCannotDepositGmxPaused() external {
        pirexGmxGlp.setPauseState(true);

        uint256 gmxAmount = 1;
        address receiver = address(this);

        _mintGmx(gmxAmount);

        vm.expectRevert("Pausable: paused");

        pirexGmxGlp.depositGmx(gmxAmount, receiver);
    }

    /**
        @notice Test tx reversion due to msg.value being zero
     */
    function testCannotDepositGmxZeroValue() external {
        uint256 invalidGmxAmount = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.depositGmx(invalidGmxAmount, receiver);
    }

    /**
        @notice Test tx reversion due to receiver being the zero address
     */
    function testCannotDepositGmxZeroReceiver() external {
        uint256 gmxAmount = 1e18;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.depositGmx(gmxAmount, invalidReceiver);
    }

    /**
        @notice Test tx reversion due to insufficient GMX balance
     */
    function testCannotDepositGmxInsufficientBalance() external {
        uint256 invalidGmxAmount = 1e18;
        uint256 mintAmount = invalidGmxAmount / 2;
        address receiver = address(this);

        // Mint less token than the amount specified for staking
        _mintGmx(mintAmount);

        vm.expectRevert("TRANSFER_FROM_FAILED");

        pirexGmxGlp.depositGmx(invalidGmxAmount, receiver);
    }

    /**
        @notice Test depositing GMX for pxGMX
        @param  gmxAmount  uint256  Amount of GMX
     */
    function testDepositGmx(uint256 gmxAmount) external {
        vm.assume(gmxAmount > 1e15);
        vm.assume(gmxAmount < 1e22);

        address receiver = address(this);

        uint256 premintGMXBalance = GMX.balanceOf(receiver);

        _mintGmx(gmxAmount);

        uint256 previousGMXBalance = GMX.balanceOf(receiver);
        uint256 previousPxGmxBalance = pxGmx.balanceOf(receiver);
        uint256 previousStakedGMXBalance = REWARD_TRACKER_GMX.balanceOf(
            address(pirexGmxGlp)
        );

        assertEq(previousGMXBalance - premintGMXBalance, gmxAmount);

        GMX.approve(address(pirexGmxGlp), gmxAmount);

        vm.expectEmit(true, true, false, false, address(pirexGmxGlp));

        emit DepositGmx(address(this), receiver, gmxAmount);

        pirexGmxGlp.depositGmx(gmxAmount, receiver);

        assertEq(previousGMXBalance - GMX.balanceOf(receiver), gmxAmount);
        assertEq(pxGmx.balanceOf(receiver) - previousPxGmxBalance, gmxAmount);
        assertEq(
            REWARD_TRACKER_GMX.balanceOf(address(pirexGmxGlp)) -
                previousStakedGMXBalance,
            gmxAmount
        );
    }

    /*//////////////////////////////////////////////////////////////
                        depositGlpWithETH TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion if contract is paused
     */
    function testCannotDepositGlpWithETHPaused() external {
        pirexGmxGlp.setPauseState(true);

        uint256 etherAmount = 1;
        uint256 minShares = 1;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);

        vm.expectRevert("Pausable: paused");

        pirexGmxGlp.depositGlpWithETH{value: etherAmount}(minShares, receiver);
    }

    /**
        @notice Test tx reversion due to msg.value being zero
     */
    function testCannotDepositGlpWithETHZeroValue() external {
        uint256 minShares = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.depositGlpWithETH{value: 0}(minShares, receiver);
    }

    /**
        @notice Test tx reversion due to minShares being zero
     */
    function testCannotDepositGlpWithETHZeroMinShares() external {
        uint256 etherAmount = 1 ether;
        uint256 invalidMinShares = 0;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.depositGlpWithETH{value: etherAmount}(
            invalidMinShares,
            receiver
        );
    }

    /**
        @notice Test tx reversion due to receiver being the zero address
     */
    function testCannotDepositGlpWithETHZeroReceiver() external {
        uint256 etherAmount = 1 ether;
        uint256 minShares = 1;
        address invalidReceiver = address(0);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.depositGlpWithETH{value: etherAmount}(
            minShares,
            invalidReceiver
        );
    }

    /**
        @notice Test tx reversion due to minShares being GT than actual GLP amount
     */
    function testCannotDepositGlpWithETHExcessiveMinShares() external {
        uint256 etherAmount = 1 ether;
        uint256 invalidMinShares = _calculateMinGlpAmount(
            address(0),
            etherAmount,
            18
        ) * 2;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(bytes("GlpManager: insufficient GLP output"));

        pirexGmxGlp.depositGlpWithETH{value: etherAmount}(
            invalidMinShares,
            receiver
        );
    }

    /**
        @notice Test depositing pxGLP with ETH
        @param  etherAmount  uint256  Amount of ether in wei units
     */
    function testDepositGlpWithETH(uint256 etherAmount) external {
        vm.assume(etherAmount > 0.001 ether);
        vm.assume(etherAmount < 1_000 ether);
        vm.deal(address(this), etherAmount);

        uint256 minShares = 1;
        address receiver = address(this);
        uint256 minGlpAmount = _calculateMinGlpAmount(
            address(0),
            etherAmount,
            18
        );
        uint256 premintETHBalance = address(this).balance;
        uint256 premintPxGlpUserBalance = pxGlp.balanceOf(receiver);
        uint256 premintGlpPirexBalance = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        );

        assertEq(premintETHBalance, etherAmount);

        vm.expectEmit(true, true, true, false, address(pirexGmxGlp));

        // Cannot test the `asset` member of the event since it's not known until after
        emit DepositGlp(
            address(this),
            receiver,
            address(0),
            minShares,
            etherAmount,
            0
        );

        uint256 assets = pirexGmxGlp.depositGlpWithETH{value: etherAmount}(
            minShares,
            receiver
        );
        uint256 pxGlpReceivedByUser = pxGlp.balanceOf(receiver) -
            premintPxGlpUserBalance;
        uint256 glpReceivedByPirex = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        ) - premintGlpPirexBalance;

        assertEq(address(this).balance, premintETHBalance - etherAmount);
        assertGt(pxGlpReceivedByUser, 0);
        assertEq(pxGlpReceivedByUser, glpReceivedByPirex);
        assertEq(glpReceivedByPirex, assets);
        assertGe(pxGlpReceivedByUser, minGlpAmount);
        assertGe(glpReceivedByPirex, minGlpAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        depositGlpWithERC20 TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion if contract is paused
     */
    function testCannotDepositGlpWithERC20TokenPaused() external {
        pirexGmxGlp.setPauseState(true);

        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 minShares = 1;
        address receiver = address(this);

        _mintWbtc(tokenAmount);
        WBTC.approve(address(pirexGmxGlp), tokenAmount);

        vm.expectRevert("Pausable: paused");

        pirexGmxGlp.depositGlpWithERC20(
            token,
            tokenAmount,
            minShares,
            receiver
        );
    }

    /**
        @notice Test tx reversion due to token being the zero address
     */
    function testCannotDepositGlpWithERC20TokenZeroAddress() external {
        address invalidToken = address(0);
        uint256 tokenAmount = 1;
        uint256 minShares = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.depositGlpWithERC20(
            invalidToken,
            tokenAmount,
            minShares,
            receiver
        );
    }

    /**
        @notice Test tx reversion due to token amount being zero
     */
    function testCannotDepositGlpWithERC20TokenZeroAmount() external {
        address token = address(WBTC);
        uint256 invalidTokenAmount = 0;
        uint256 minShares = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.depositGlpWithERC20(
            token,
            invalidTokenAmount,
            minShares,
            receiver
        );
    }

    /**
        @notice Test tx reversion due to minShares being zero
     */
    function testCannotDepositGlpWithERC20MinSharesZeroAmount() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 invalidMinShares = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.depositGlpWithERC20(
            token,
            tokenAmount,
            invalidMinShares,
            receiver
        );
    }

    /**
        @notice Test tx reversion due to receiver being the zero address
     */
    function testCannotDepositGlpWithERC20ReceiverZeroAddress() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 minShares = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.depositGlpWithERC20(
            token,
            tokenAmount,
            minShares,
            invalidReceiver
        );
    }

    /**
        @notice Test tx reversion due to token not being whitelisted by GMX
     */
    function testCannotDepositGlpWithERC20InvalidToken() external {
        address invalidToken = address(this);
        uint256 tokenAmount = 1;
        uint256 minShares = 1;
        address receiver = address(this);

        vm.expectRevert(
            abi.encodeWithSelector(
                PirexGmxGlp.InvalidToken.selector,
                invalidToken
            )
        );

        pirexGmxGlp.depositGlpWithERC20(
            invalidToken,
            tokenAmount,
            minShares,
            receiver
        );
    }

    /**
        @notice Test tx reversion due to minShares being GT than actual GLP amount
     */
    function testCannotDepositGlpWithERC20ExcessiveMinShares() external {
        uint256 tokenAmount = 1e8;
        address token = address(WBTC);
        uint256 invalidMinShares = _calculateMinGlpAmount(
            token,
            tokenAmount,
            8
        ) * 2;
        address receiver = address(this);

        _mintWbtc(tokenAmount);
        WBTC.approve(address(pirexGmxGlp), tokenAmount);

        vm.expectRevert(bytes("GlpManager: insufficient GLP output"));

        pirexGmxGlp.depositGlpWithERC20(
            token,
            tokenAmount,
            invalidMinShares,
            receiver
        );
    }

    /**
        @notice Test depositing pxGLP with whitelisted ERC20 tokens
        @param  tokenAmount  uint256  Token amount
     */
    function testDepositGlpWithERC20(uint256 tokenAmount) external {
        vm.assume(tokenAmount > 1e5);
        vm.assume(tokenAmount < 100e8);

        _mintWbtc(tokenAmount);

        address token = address(WBTC);
        uint256 minShares = 1;
        address receiver = address(this);
        uint256 minGlpAmount = _calculateMinGlpAmount(token, tokenAmount, 8);
        uint256 premintWBTCBalance = WBTC.balanceOf(address(this));
        uint256 premintPxGlpUserBalance = pxGlp.balanceOf(receiver);
        uint256 premintGlpPirexBalance = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        );

        assertTrue(WBTC.balanceOf(address(this)) == tokenAmount);

        WBTC.approve(address(pirexGmxGlp), tokenAmount);

        vm.expectEmit(true, true, true, false, address(pirexGmxGlp));

        // Cannot test the `asset` member of the event since it's not known until after
        emit DepositGlp(
            address(this),
            receiver,
            token,
            minShares,
            tokenAmount,
            0
        );

        uint256 assets = pirexGmxGlp.depositGlpWithERC20(
            token,
            tokenAmount,
            minShares,
            receiver
        );
        uint256 pxGlpReceivedByUser = pxGlp.balanceOf(receiver) -
            premintPxGlpUserBalance;
        uint256 glpReceivedByPirex = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        ) - premintGlpPirexBalance;

        assertEq(
            WBTC.balanceOf(address(this)),
            premintWBTCBalance - tokenAmount
        );
        assertGt(pxGlpReceivedByUser, 0);
        assertEq(pxGlpReceivedByUser, glpReceivedByPirex);
        assertEq(glpReceivedByPirex, assets);
        assertGe(pxGlpReceivedByUser, minGlpAmount);
        assertGe(glpReceivedByPirex, minGlpAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        redeemPxGlpForETH TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion if contract is paused
     */
    function testCannotRedeemPxGlpForETHPaused() external {
        uint256 etherAmount = 1 ether;
        address receiver = address(this);

        uint256 assets = _depositGlpWithETH(etherAmount, receiver);
        uint256 minRedemption = _calculateMinRedemptionAmount(
            address(WETH),
            assets
        );

        // Pause after deposit
        pirexGmxGlp.setPauseState(true);

        vm.expectRevert("Pausable: paused");

        pirexGmxGlp.redeemPxGlpForETH(assets, minRedemption, receiver);
    }

    /**
        @notice Test tx reversion due to msg.value being zero
     */
    function testCannotRedeemPxGlpForETHZeroValue() external {
        uint256 invalidAmount = 0;
        uint256 minRedemption = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.redeemPxGlpForETH(invalidAmount, minRedemption, receiver);
    }

    /**
        @notice Test tx reversion due to minRedemption being zero
     */
    function testCannotRedeemPxGlpForETHZeroMinRedemption() external {
        uint256 amount = 1;
        uint256 invalidMinRedemption = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.redeemPxGlpForETH(amount, invalidMinRedemption, receiver);
    }

    /**
        @notice Test tx reversion due to receiver being the zero address
     */
    function testCannotRedeemPxGlpForETHZeroReceiver() external {
        uint256 amount = 1;
        uint256 minRedemption = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.redeemPxGlpForETH(amount, minRedemption, invalidReceiver);
    }

    /**
        @notice Test tx reversion due to minShares being GT than actual GLP amount
     */
    function testCannotRedeemPxGlpForETHExcessiveMinRedemption() external {
        uint256 etherAmount = 1 ether;
        address receiver = address(this);

        uint256 assets = _depositGlpWithETH(etherAmount, receiver);
        uint256 invalidMinRedemption = _calculateMinRedemptionAmount(
            address(WETH),
            assets
        ) * 2;

        vm.expectRevert(bytes("GlpManager: insufficient output"));

        pirexGmxGlp.redeemPxGlpForETH(assets, invalidMinRedemption, receiver);
    }

    /**
        @notice Test redeeming back ETH from pxGLP
        @param  etherAmount  uint256  Amount of ether in wei units
     */
    function testRedeemPxGlpForETH(uint256 etherAmount) external {
        vm.assume(etherAmount > 0.1 ether);
        vm.assume(etherAmount < 1_000 ether);

        address token = address(WETH);
        address receiver = address(this);

        // Mint pxGLP with ETH before attempting to redeem back into ETH
        uint256 assets = _depositGlpWithETH(etherAmount, receiver);

        uint256 previousETHBalance = receiver.balance;
        uint256 previousPxGlpUserBalance = pxGlp.balanceOf(receiver);
        uint256 previousGlpPirexBalance = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        );

        // Calculate the minimum redemption amount then perform the redemption
        uint256 minRedemption = _calculateMinRedemptionAmount(token, assets);

        vm.expectEmit(true, true, true, false, address(pirexGmxGlp));

        emit RedeemGlp(
            address(this),
            receiver,
            address(0),
            minRedemption,
            etherAmount,
            0
        );

        uint256 redeemed = pirexGmxGlp.redeemPxGlpForETH(
            assets,
            minRedemption,
            receiver
        );

        assertGt(redeemed, minRedemption);
        assertEq(receiver.balance - previousETHBalance, redeemed);
        assertEq(previousPxGlpUserBalance - pxGlp.balanceOf(receiver), assets);
        assertEq(
            previousGlpPirexBalance -
                FEE_STAKED_GLP.balanceOf(address(pirexGmxGlp)),
            assets
        );
    }

    /*//////////////////////////////////////////////////////////////
                        redeemPxGlpForERC20 TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion if contract is paused
     */
    function testCannotRedeemPxGlpForERC20TokenPaused() external {
        uint256 etherAmount = 1 ether;
        address receiver = address(this);
        address token = address(WBTC);

        uint256 assets = _depositGlpWithETH(etherAmount, receiver);
        uint256 minRedemption = _calculateMinRedemptionAmount(token, assets);

        // Pause after deposit
        pirexGmxGlp.setPauseState(true);

        vm.expectRevert("Pausable: paused");

        pirexGmxGlp.redeemPxGlpForERC20(token, assets, minRedemption, receiver);
    }

    /**
        @notice Test tx reversion due to token being the zero address
     */
    function testCannotRedeemPxGlpForERC20TokenZeroAddress() external {
        address invalidToken = address(0);
        uint256 amount = 1;
        uint256 minRedemption = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.redeemPxGlpForERC20(
            invalidToken,
            amount,
            minRedemption,
            receiver
        );
    }

    /**
        @notice Test tx reversion due to msg.value being zero
     */
    function testCannotRedeemPxGlpForERC20ZeroValue() external {
        address token = address(WBTC);
        uint256 invalidAmount = 0;
        uint256 minRedemption = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.redeemPxGlpForERC20(
            token,
            invalidAmount,
            minRedemption,
            receiver
        );
    }

    /**
        @notice Test tx reversion due to minRedemption being zero
     */
    function testCannotRedeemPxGlpForERC20ZeroMinRedemption() external {
        address token = address(WBTC);
        uint256 amount = 1;
        uint256 invalidMinRedemption = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmxGlp.ZeroAmount.selector);

        pirexGmxGlp.redeemPxGlpForERC20(
            token,
            amount,
            invalidMinRedemption,
            receiver
        );
    }

    /**
        @notice Test tx reversion due to receiver being the zero address
     */
    function testCannotRedeemPxGlpForERC20ZeroReceiver() external {
        address token = address(WBTC);
        uint256 amount = 1;
        uint256 minRedemption = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.redeemPxGlpForERC20(
            token,
            amount,
            minRedemption,
            invalidReceiver
        );
    }

    /**
        @notice Test tx reversion due to token not being whitelisted by GMX
     */
    function testCannotRedeemPxGlpForERC20InvalidToken() external {
        address invalidToken = address(this);
        uint256 amount = 1;
        uint256 minRedemption = 1;
        address receiver = address(this);

        vm.expectRevert(
            abi.encodeWithSelector(
                PirexGmxGlp.InvalidToken.selector,
                invalidToken
            )
        );

        pirexGmxGlp.redeemPxGlpForERC20(
            invalidToken,
            amount,
            minRedemption,
            receiver
        );
    }

    /**
        @notice Test tx reversion due to minRedemption being GT than actual token amount
     */
    function testCannotRedeemPxGlpForERC20ExcessiveMinRedemption() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1e8;
        address receiver = address(this);

        uint256 assets = _depositGlpWithERC20(tokenAmount, receiver);
        uint256 invalidMinRedemption = _calculateMinRedemptionAmount(
            token,
            assets
        ) * 2;

        vm.expectRevert(bytes("GlpManager: insufficient output"));

        pirexGmxGlp.redeemPxGlpForERC20(
            token,
            assets,
            invalidMinRedemption,
            receiver
        );
    }

    /**
        @notice Test redeeming back to whitelisted ERC20 tokens from pxGLP
        @param  tokenAmount  uint256  Token amount
     */
    function testRedeemPxGlpForERC20(uint256 tokenAmount) external {
        vm.assume(tokenAmount > 1e5);
        vm.assume(tokenAmount < 100e8);

        address token = address(WBTC);
        address receiver = address(this);

        // Deposit using ERC20 to receive some pxGLP for redemption tests later
        uint256 assets = _depositGlpWithERC20(tokenAmount, receiver);

        uint256 previousWBTCBalance = WBTC.balanceOf(receiver);
        uint256 previousPxGlpUserBalance = pxGlp.balanceOf(receiver);
        uint256 previousGlpPirexBalance = FEE_STAKED_GLP.balanceOf(
            address(pirexGmxGlp)
        );

        // Calculate the minimum redemption amount then perform the redemption
        uint256 minRedemption = _calculateMinRedemptionAmount(token, assets);

        vm.expectEmit(true, true, true, false, address(pirexGmxGlp));

        emit RedeemGlp(
            address(this),
            receiver,
            token,
            minRedemption,
            tokenAmount,
            0
        );

        uint256 redeemed = pirexGmxGlp.redeemPxGlpForERC20(
            token,
            assets,
            minRedemption,
            receiver
        );

        assertGt(redeemed, minRedemption);
        assertEq(WBTC.balanceOf(receiver) - previousWBTCBalance, redeemed);
        assertEq(previousPxGlpUserBalance - pxGlp.balanceOf(receiver), assets);
        assertEq(
            previousGlpPirexBalance -
                FEE_STAKED_GLP.balanceOf(address(pirexGmxGlp)),
            assets
        );
    }

    /*//////////////////////////////////////////////////////////////
                        calculateRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test calculating WETH and esGMX rewards produced by GMX and GLP
        @param  secondsElapsed  uint32  Seconds to forward timestamp
        @param  wbtcAmount      uint40  Amount of WBTC used for minting GLP
        @param  gmxAmount       uint80  Amount of GMX to mint and deposit
     */
    function testCalculateRewards(
        uint32 secondsElapsed,
        uint40 wbtcAmount,
        uint80 gmxAmount
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(wbtcAmount > 1);
        vm.assume(wbtcAmount < 100e8);
        vm.assume(gmxAmount != 0);
        vm.assume(gmxAmount < 1000000e18);

        address pirexRewardsAddr = address(pirexRewards);

        _depositGlpWithERC20(wbtcAmount, address(this));
        _depositGmx(gmxAmount, address(this));

        // Ensure pirexRewards has a zero WETH and pxGMX balance to test balance changes
        assertEq(0, WETH.balanceOf(pirexRewardsAddr));
        assertEq(0, pxGmx.balanceOf(pirexRewardsAddr));

        vm.warp(block.timestamp + secondsElapsed);

        uint256 expectedWETHRewardsGmx = pirexGmxGlp.calculateRewards(
            true,
            true
        );
        uint256 expectedWETHRewardsGlp = pirexGmxGlp.calculateRewards(
            true,
            false
        );
        uint256 expectedEsGmxRewardsGmx = pirexGmxGlp.calculateRewards(
            false,
            true
        );
        uint256 expectedEsGmxRewardsGlp = pirexGmxGlp.calculateRewards(
            false,
            false
        );
        uint256 expectedWETHRewards = expectedWETHRewardsGmx +
            expectedWETHRewardsGlp;
        uint256 expectedEsGmxRewards = expectedEsGmxRewardsGmx +
            expectedEsGmxRewardsGlp;

        vm.prank(pirexRewardsAddr);

        (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = pirexGmxGlp.claimRewards();
        address wethAddr = address(WETH);
        address pxGlpAddr = address(pxGlp);
        address pxGmxAddr = address(pxGmx);

        assertEq(pxGmxAddr, address(producerTokens[0]));
        assertEq(pxGlpAddr, address(producerTokens[1]));
        assertEq(pxGmxAddr, address(producerTokens[2]));
        assertEq(pxGlpAddr, address(producerTokens[3]));
        assertEq(wethAddr, address(rewardTokens[0]));
        assertEq(wethAddr, address(rewardTokens[1]));
        assertEq(pxGmxAddr, address(rewardTokens[2]));
        assertEq(pxGmxAddr, address(rewardTokens[3]));
        assertEq(expectedWETHRewardsGmx, rewardAmounts[0]);
        assertEq(expectedWETHRewardsGlp, rewardAmounts[1]);
        assertEq(expectedEsGmxRewardsGmx, rewardAmounts[2]);
        assertEq(expectedEsGmxRewardsGlp, rewardAmounts[3]);
        assertEq(WETH.balanceOf(pirexRewardsAddr), expectedWETHRewards);
        assertEq(pxGmx.balanceOf(pirexRewardsAddr), expectedEsGmxRewards);
        assertGt(expectedWETHRewards, 0);
        assertGt(expectedEsGmxRewards, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        claimRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not pirexRewards
     */
    function testCannotClaimRewardsNotPirexRewards() external {
        vm.prank(testAccounts[0]);
        vm.expectRevert(PirexGmxGlp.NotPirexRewards.selector);

        pirexGmxGlp.claimRewards();
    }

    /**
        @notice Test claiming both WETH and esGMX rewards
        @param  secondsElapsed  uint32  Seconds to forward timestamp
        @param  wbtcAmount      uint40  Amount of WBTC used for minting GLP
        @param  gmxAmount       uint80  Amount of GMX to mint and deposit
     */
    function testClaimRewards(
        uint32 secondsElapsed,
        uint40 wbtcAmount,
        uint80 gmxAmount
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(wbtcAmount > 1);
        vm.assume(wbtcAmount < 100e8);
        vm.assume(gmxAmount != 0);
        vm.assume(gmxAmount < 1000000e18);

        address pirexRewardsAddr = address(pirexRewards);

        _depositGlpWithERC20(wbtcAmount, address(this));
        _depositGmx(gmxAmount, address(this));

        // Forward timestamp to produce rewards
        vm.warp(block.timestamp + secondsElapsed);

        // Ensure pirexRewards has a zero WETH balance to test balance changes
        assertEq(0, WETH.balanceOf(pirexRewardsAddr));
        assertEq(0, pxGmx.balanceOf(pirexRewardsAddr));

        uint256 previousStakedGmxBalance = REWARD_TRACKER_GMX.balanceOf(
            address(pirexGmxGlp)
        );

        uint256 expectedWETHRewardsGmx = pirexGmxGlp.calculateRewards(
            true,
            true
        );
        uint256 expectedWETHRewardsGlp = pirexGmxGlp.calculateRewards(
            true,
            false
        );
        uint256 expectedEsGmxRewardsGmx = pirexGmxGlp.calculateRewards(
            false,
            true
        );
        uint256 expectedEsGmxRewardsGlp = pirexGmxGlp.calculateRewards(
            false,
            false
        );
        uint256 expectedWETHRewards = expectedWETHRewardsGmx +
            expectedWETHRewardsGlp;
        uint256 expectedEsGmxRewards = expectedEsGmxRewardsGmx +
            expectedEsGmxRewardsGlp;

        vm.expectEmit(false, false, false, true, address(pirexGmxGlp));

        // Limited variable counts due to stack-too-deep issue
        emit ClaimRewards(
            expectedWETHRewards,
            expectedEsGmxRewards,
            expectedWETHRewardsGmx,
            expectedWETHRewardsGlp,
            expectedEsGmxRewardsGmx,
            expectedEsGmxRewardsGlp
        );

        // Impersonate pirexRewards and claim WETH rewards
        vm.prank(pirexRewardsAddr);

        (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = pirexGmxGlp.claimRewards();

        assertEq(address(pxGmx), address(producerTokens[0]));
        assertEq(address(pxGlp), address(producerTokens[1]));
        assertEq(address(pxGmx), address(producerTokens[2]));
        assertEq(address(pxGlp), address(producerTokens[3]));
        assertEq(address(WETH), address(rewardTokens[0]));
        assertEq(address(WETH), address(rewardTokens[1]));
        assertEq(address(pxGmx), address(rewardTokens[2]));
        assertEq(address(pxGmx), address(rewardTokens[3]));
        assertEq(expectedWETHRewardsGmx, rewardAmounts[0]);
        assertEq(expectedWETHRewardsGlp, rewardAmounts[1]);
        assertEq(expectedEsGmxRewardsGmx, rewardAmounts[2]);
        assertEq(expectedEsGmxRewardsGlp, rewardAmounts[3]);
        assertGt(expectedWETHRewards, 0);
        assertGt(expectedEsGmxRewards, 0);
        assertEq(WETH.balanceOf(pirexRewardsAddr), expectedWETHRewards);
        assertEq(pxGmx.balanceOf(pirexRewardsAddr), expectedEsGmxRewards);

        // Claiming esGMX rewards should also be staked immediately
        assertEq(
            REWARD_TRACKER_GMX.balanceOf(address(pirexGmxGlp)),
            previousStakedGmxBalance + expectedEsGmxRewards
        );
    }

    /*//////////////////////////////////////////////////////////////
                        compoundMultiplierPoints TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion if contract is paused
     */
    function testCannotCompoundMultiplierPointsPaused() external {
        pirexGmxGlp.setPauseState(true);

        vm.expectRevert("Pausable: paused");

        pirexGmxGlp.compoundMultiplierPoints();
    }

    /**
        @notice Test compounding multiplier points
        @param  gmxAmount  uint256  Amount of GMX
     */
    function testCompoundMultiplierPoints(uint256 gmxAmount) external {
        vm.assume(gmxAmount > 1e15);
        vm.assume(gmxAmount < 1e22);

        // Mint then deposit some GMX in order to gain multiplier points (MP) later on
        address receiver = address(this);

        _mintGmx(gmxAmount);

        uint256 preDepositStakedGMXBalance = REWARD_TRACKER_GMX.balanceOf(
            address(pirexGmxGlp)
        );

        GMX.approve(address(pirexGmxGlp), gmxAmount);

        pirexGmxGlp.depositGmx(gmxAmount, receiver);

        uint256 postDepositStakedGMXBalance = REWARD_TRACKER_GMX.balanceOf(
            address(pirexGmxGlp)
        );

        assertEq(
            postDepositStakedGMXBalance - preDepositStakedGMXBalance,
            gmxAmount
        );

        // Time skip to accrue some multiplier points
        vm.warp(block.timestamp + 1 hours);

        uint256 claimableMp = REWARD_TRACKER_MP.claimable(address(pirexGmxGlp));

        assertGt(claimableMp, 0);

        pirexGmxGlp.compoundMultiplierPoints();

        uint256 postCompoundStakedGMXBalance = REWARD_TRACKER_GMX.balanceOf(
            address(pirexGmxGlp)
        );

        // Compounded MP should be reflected in the latest staked amount of GMX
        assertEq(
            postCompoundStakedGMXBalance,
            postDepositStakedGMXBalance + claimableMp
        );
    }

    /*//////////////////////////////////////////////////////////////
                        setPauseState TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to caller not being owner
     */
    function testCannotSetPauseStateUnauthorized() external {
        vm.prank(testAccounts[0]);

        vm.expectRevert("UNAUTHORIZED");

        pirexGmxGlp.setPauseState(true);
    }

    /**
        @notice Test tx reversion if unpausing when not paused
     */
    function testCannotSetPauseStateNotPaused() external {
        assertEq(pirexGmxGlp.paused(), false);

        vm.expectRevert("Pausable: not paused");

        pirexGmxGlp.setPauseState(false);
    }

    /**
        @notice Test tx reversion if pausing when paused
     */
    function testCannotSetPauseStatePaused() external {
        pirexGmxGlp.setPauseState(true);

        assertEq(pirexGmxGlp.paused(), true);

        vm.expectRevert("Pausable: paused");

        pirexGmxGlp.setPauseState(true);
    }

    /**
        @notice Test setting pause state
     */
    function testSetPauseState() external {
        assertEq(pirexGmxGlp.paused(), false);

        pirexGmxGlp.setPauseState(true);

        assertEq(pirexGmxGlp.paused(), true);

        pirexGmxGlp.setPauseState(false);

        assertEq(pirexGmxGlp.paused(), false);
    }

    /*//////////////////////////////////////////////////////////////
                        initiateMigration TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion if contract is not paused
     */
    function testCannotInitiateMigrationNotPaused() external {
        assertEq(pirexGmxGlp.paused(), false);

        address newContract = address(this);

        vm.expectRevert("Pausable: not paused");

        pirexGmxGlp.initiateMigration(newContract);
    }

    /**
        @notice Test tx reversion due to caller not being owner
     */
    function testCannotInitiateMigrationUnauthorized() external {
        pirexGmxGlp.setPauseState(true);

        address newContract = address(this);

        vm.prank(testAccounts[0]);

        vm.expectRevert("UNAUTHORIZED");

        pirexGmxGlp.initiateMigration(newContract);
    }

    /**
        @notice Test tx reversion due to newContract being zero
     */
    function testCannotInitiateMigrationZeroAddress() external {
        pirexGmxGlp.setPauseState(true);

        address invalidNewContract = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.initiateMigration(invalidNewContract);
    }

    /**
        @notice Test initiating migration
     */
    function testInitiateMigration() external {
        pirexGmxGlp.setPauseState(true);

        address oldContract = address(pirexGmxGlp);
        address newContract = address(this);

        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), address(0));

        vm.expectEmit(false, false, false, true, address(pirexGmxGlp));

        emit InitiateMigration(newContract);

        pirexGmxGlp.initiateMigration(newContract);

        // Should properly set the pendingReceivers state
        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), newContract);
    }

    /*//////////////////////////////////////////////////////////////
                        completeMigration TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion if contract is not paused
     */
    function testCannotCompleteMigrationNotPaused() external {
        assertEq(pirexGmxGlp.paused(), false);

        address oldContract = address(this);

        vm.expectRevert("Pausable: not paused");

        pirexGmxGlp.completeMigration(oldContract);
    }

    /**
        @notice Test tx reversion due to caller not being owner
     */
    function testCannotCompleteMigrationUnauthorized() external {
        pirexGmxGlp.setPauseState(true);

        address oldContract = address(pirexGmxGlp);

        vm.prank(testAccounts[0]);

        vm.expectRevert("UNAUTHORIZED");

        pirexGmxGlp.completeMigration(oldContract);
    }

    /**
        @notice Test tx reversion due to oldContract being zero
     */
    function testCannotCompleteMigrationZeroAddress() external {
        pirexGmxGlp.setPauseState(true);

        address invalidOldContract = address(0);

        vm.expectRevert(PirexGmxGlp.ZeroAddress.selector);

        pirexGmxGlp.completeMigration(invalidOldContract);
    }

    /**
        @notice Test tx reversion due to the caller not being the assigned new contract
     */
    function testCannotCompleteMigrationInvalidNewContract() external {
        pirexGmxGlp.setPauseState(true);

        address oldContract = address(pirexGmxGlp);
        address newContract = address(this);

        pirexGmxGlp.initiateMigration(newContract);

        // Deploy a test contract but not being assigned as the migration target
        PirexGmxGlp newPirexGmxGlp = new PirexGmxGlp(
            address(pxGmx),
            address(pxGlp),
            address(pirexRewards)
        );

        vm.expectRevert("RewardRouter: transfer not signalled");

        newPirexGmxGlp.completeMigration(oldContract);
    }

    /**
        @notice Test completing migration
     */
    function testCompleteMigration() external {
        // Perform GMX deposit for balance tests after migration
        uint256 gmxAmount = 1e18;
        address receiver = address(this);
        address oldContract = address(pirexGmxGlp);

        _mintGmx(gmxAmount);

        GMX.approve(oldContract, gmxAmount);
        pirexGmxGlp.depositGmx(gmxAmount, receiver);

        // Perform GLP deposit for balance tests after migration
        uint256 etherAmount = 1 ether;

        vm.deal(address(this), etherAmount);

        pirexGmxGlp.depositGlpWithETH{value: etherAmount}(1, receiver);

        // Time skip to bypass the cooldown duration
        vm.warp(block.timestamp + 1 days);

        // Store the staked balances for later validations
        uint256 oldStakedGmxBalance = REWARD_TRACKER_GMX.balanceOf(oldContract);
        uint256 oldStakedGlpBalance = FEE_STAKED_GLP.balanceOf(oldContract);
        uint256 oldEsGmxClaimable = pirexGmxGlp.calculateRewards(false, true) +
            pirexGmxGlp.calculateRewards(false, false);
        uint256 oldMpBalance = REWARD_TRACKER_MP.claimable(oldContract);

        // Pause the contract before proceeding
        pirexGmxGlp.setPauseState(true);

        // Deploy the new contract for migration tests
        PirexGmxGlp newPirexGmxGlp = new PirexGmxGlp(
            address(pxGmx),
            address(pxGlp),
            address(pirexRewards)
        );

        address newContract = address(newPirexGmxGlp);

        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), address(0));

        pirexGmxGlp.initiateMigration(newContract);

        // Should properly set the pendingReceivers state
        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), newContract);

        vm.expectEmit(false, false, false, true, address(newPirexGmxGlp));

        emit CompleteMigration(oldContract);

        // Complete the migration using the new contract
        newPirexGmxGlp.completeMigration(oldContract);

        // Should properly clear the pendingReceivers state
        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), address(0));

        // Confirm that the token balances and claimables for old contract are correct
        assertEq(REWARD_TRACKER_GMX.balanceOf(oldContract), 0);
        assertEq(FEE_STAKED_GLP.balanceOf(oldContract), 0);
        assertEq(STAKED_GMX.claimable(oldContract), 0);
        assertEq(FEE_STAKED_GLP.claimable(oldContract), 0);
        assertEq(REWARD_TRACKER_MP.claimable(oldContract), 0);

        // Confirm that the staked token balances for new contract are correct
        // For Staked GMX balance, due to compounding in the migration,
        // all pending claimable esGMX and MP are automatically staked
        assertEq(
            REWARD_TRACKER_GMX.balanceOf(newContract),
            oldStakedGmxBalance + oldEsGmxClaimable + oldMpBalance
        );
        assertEq(FEE_STAKED_GLP.balanceOf(newContract), oldStakedGlpBalance);
    }
}
