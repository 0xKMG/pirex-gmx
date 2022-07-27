// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {PirexGlp} from "src/PirexGlp.sol";
import {Vault} from "src/external/Vault.sol";
import {Helper} from "./Helper.t.sol";

contract PirexGlpTest is Test, Helper {
    event Mint(
        address indexed caller,
        uint256 indexed minShares,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 assets
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
                WETH,
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

        uint256 assets = pirexGlp.mintWithETH{value: etherAmount}(1, receiver);

        // Time skip to bypass the cooldown duration
        vm.warp(block.timestamp + 1 hours);

        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                        GMX-related TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test for verifying correctness of GLP buy minimum calculation
        @param  etherAmount  uint256  Amount of ether in wei units
     */
    function testMintAndStakeGlpETH(uint256 etherAmount) external {
        vm.assume(etherAmount > 0.001 ether);
        vm.assume(etherAmount < 1_000 ether);
        vm.deal(address(this), etherAmount);

        assertEq(address(this).balance, etherAmount);
        assertEq(FEE_STAKED_GLP.balanceOf(address(this)), 0);

        uint256 minGlpWithSlippage = _calculateMinGlpAmount(
            address(0),
            etherAmount,
            18
        );
        uint256 glpAmount = REWARD_ROUTER_V2.mintAndStakeGlpETH{
            value: etherAmount
        }(0, minGlpWithSlippage);

        assertEq(address(this).balance, 0);
        assertGt(minGlpWithSlippage, 0);
        assertGt(glpAmount, minGlpWithSlippage);
    }

    /*//////////////////////////////////////////////////////////////
                        mintWithETH TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to msg.value being zero
     */
    function testCannotMintWithETHZeroValue() external {
        uint256 minShares = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGlp.ZeroAmount.selector);

        pirexGlp.mintWithETH{value: 0}(minShares, receiver);
    }

    /**
        @notice Test tx reversion due to minShares being zero
     */
    function testCannotMintWithETHZeroMinShares() external {
        uint256 etherAmount = 1 ether;
        uint256 invalidMinShares = 0;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGlp.ZeroAmount.selector);

        pirexGlp.mintWithETH{value: etherAmount}(invalidMinShares, receiver);
    }

    /**
        @notice Test tx reversion due to receiver being the zero address
     */
    function testCannotMintWithETHZeroReceiver() external {
        uint256 etherAmount = 1 ether;
        uint256 minShares = 1;
        address invalidReceiver = address(0);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGlp.ZeroAddress.selector);

        pirexGlp.mintWithETH{value: etherAmount}(minShares, invalidReceiver);
    }

    /**
        @notice Test tx reversion due to minShares being GT than actual GLP amount
     */
    function testCannotMintWithETHExcessiveMinShares() external {
        uint256 etherAmount = 1 ether;
        uint256 invalidMinShares = _calculateMinGlpAmount(
            address(0),
            etherAmount,
            18
        ) * 2;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(bytes("GlpManager: insufficient GLP output"));

        pirexGlp.mintWithETH{value: etherAmount}(invalidMinShares, receiver);
    }

    /**
        @notice Test minting pxGLP with ETH
        @param  etherAmount  uint256  Amount of ether in wei units
     */
    function testMintWithETH(uint256 etherAmount) external {
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
            address(pirexGlp)
        );

        assertEq(premintETHBalance, etherAmount);

        vm.expectEmit(true, true, true, false, address(pirexGlp));

        // Cannot test the `asset` member of the event since it's not known until after
        emit Mint(
            address(this),
            minShares,
            receiver,
            address(0),
            etherAmount,
            0
        );

        uint256 assets = pirexGlp.mintWithETH{value: etherAmount}(
            minShares,
            receiver
        );
        uint256 pxGlpReceivedByUser = pxGlp.balanceOf(receiver) -
            premintPxGlpUserBalance;
        uint256 glpReceivedByPirex = FEE_STAKED_GLP.balanceOf(
            address(pirexGlp)
        ) - premintGlpPirexBalance;

        assertEq(address(this).balance, premintETHBalance - etherAmount);
        assertGt(pxGlpReceivedByUser, 0);
        assertEq(pxGlpReceivedByUser, glpReceivedByPirex);
        assertEq(glpReceivedByPirex, assets);
        assertGe(pxGlpReceivedByUser, minGlpAmount);
        assertGe(glpReceivedByPirex, minGlpAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        mintWithERC20 TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to token being the zero address
     */
    function testCannotMintWithERC20TokenZeroAddress() external {
        address invalidToken = address(0);
        uint256 tokenAmount = 1;
        uint256 minShares = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGlp.ZeroAddress.selector);

        pirexGlp.mintWithERC20(invalidToken, tokenAmount, minShares, receiver);
    }

    /**
        @notice Test tx reversion due to token amount being zero
     */
    function testCannotMintWithERC20TokenZeroAmount() external {
        address token = address(WBTC);
        uint256 invalidTokenAmount = 0;
        uint256 minShares = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGlp.ZeroAmount.selector);

        pirexGlp.mintWithERC20(token, invalidTokenAmount, minShares, receiver);
    }

    /**
        @notice Test tx reversion due to minShares being zero
     */
    function testCannotMintWithERC20MinSharesZeroAmount() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 invalidMinShares = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGlp.ZeroAmount.selector);

        pirexGlp.mintWithERC20(token, tokenAmount, invalidMinShares, receiver);
    }

    /**
        @notice Test tx reversion due to receiver being the zero address
     */
    function testCannotMintWithERC20ReceiverZeroAddress() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 minShares = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGlp.ZeroAddress.selector);

        pirexGlp.mintWithERC20(token, tokenAmount, minShares, invalidReceiver);
    }

    /**
        @notice Test tx reversion due to token not being whitelisted by GMX
     */
    function testCannotMintWithERC20InvalidToken() external {
        address invalidToken = address(this);
        uint256 tokenAmount = 1;
        uint256 minShares = 1;
        address receiver = address(this);

        vm.expectRevert(
            abi.encodeWithSelector(PirexGlp.InvalidToken.selector, invalidToken)
        );

        pirexGlp.mintWithERC20(invalidToken, tokenAmount, minShares, receiver);
    }

    /**
        @notice Test tx reversion due to minShares being GT than actual GLP amount
     */
    function testCannotMintWithERC20ExcessiveMinShares() external {
        uint256 tokenAmount = 1e8;
        address token = address(WBTC);
        uint256 invalidMinShares = _calculateMinGlpAmount(
            token,
            tokenAmount,
            8
        ) * 2;
        address receiver = address(this);

        _mintWbtc(tokenAmount);
        WBTC.approve(address(pirexGlp), tokenAmount);

        vm.expectRevert(bytes("GlpManager: insufficient GLP output"));

        pirexGlp.mintWithERC20(token, tokenAmount, invalidMinShares, receiver);
    }

    /**
        @notice Test tx reversion due to receiver being the zero address
        @param  tokenAmount  uint256  Token amount
     */
    function testMintWithERC20(uint256 tokenAmount) external {
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
            address(pirexGlp)
        );

        assertTrue(WBTC.balanceOf(address(this)) == tokenAmount);

        WBTC.approve(address(pirexGlp), tokenAmount);

        vm.expectEmit(true, true, true, false, address(pirexGlp));

        // Cannot test the `asset` member of the event since it's not known until after
        emit Mint(address(this), minShares, receiver, token, tokenAmount, 0);

        uint256 assets = pirexGlp.mintWithERC20(
            token,
            tokenAmount,
            minShares,
            receiver
        );
        uint256 pxGlpReceivedByUser = pxGlp.balanceOf(receiver) -
            premintPxGlpUserBalance;
        uint256 glpReceivedByPirex = FEE_STAKED_GLP.balanceOf(
            address(pirexGlp)
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
                        redeemForETH TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion due to msg.value being zero
     */
    function testCannotRedeemForETHZeroValue() external {
        vm.expectRevert(PirexGlp.ZeroAmount.selector);

        pirexGlp.redeemForETH(0, 1, address(this));
    }

    /**
        @notice Test tx reversion due to minRedemption being zero
     */
    function testCannotRedeemForETHZeroMinRedemption() external {
        vm.expectRevert(PirexGlp.ZeroAmount.selector);

        pirexGlp.redeemForETH(1, 0, address(this));
    }

    /**
        @notice Test tx reversion due to receiver being the zero address
     */
    function testCannotRedeemForETHZeroReceiver() external {
        vm.expectRevert(PirexGlp.ZeroAddress.selector);

        pirexGlp.redeemForETH(1, 1, address(0));
    }

    /**
        @notice Test tx reversion due to minShares being GT than actual GLP amount
     */
    function testCannotRedeemForETHExcessiveMinRedemption() external {
        uint256 etherAmount = 1 ether;
        address receiver = address(this);

        uint256 assets = _depositGlpWithETH(etherAmount, receiver);
        uint256 invalidMinRedemption = _calculateMinRedemptionAmount(
            WETH,
            assets
        ) * 2;

        vm.expectRevert(bytes("GlpManager: insufficient output"));

        pirexGlp.redeemForETH(assets, invalidMinRedemption, address(this));
    }

    /**
        @notice Test redeeming back ETH from pxGLP
        @param  etherAmount  uint256  Amount of ether in wei units
     */
    function testRedeemForETH(uint256 etherAmount) external {
        vm.assume(etherAmount > 0.1 ether);
        vm.assume(etherAmount < 1_000 ether);

        address token = WETH;
        address receiver = address(this);

        // Mint pxGLP with ETH before attempting to redeem back into ETH
        uint256 assets = _depositGlpWithETH(etherAmount, receiver);

        // Calculate the minimum redemption amount then perform the redemption
        uint256 minRedemption = _calculateMinRedemptionAmount(token, assets);
        uint256 redeemed = pirexGlp.redeemForETH(
            assets,
            minRedemption,
            receiver
        );

        assertGt(redeemed, minRedemption);
        assertEq(address(this).balance, redeemed);
    }
}
