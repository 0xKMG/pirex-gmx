// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import {PirexGlp} from "src/PirexGlp.sol";
import {IRewardRouterV2} from "src/interface/IRewardRouterV2.sol";
import {IVaultReader} from "src/interface/IVaultReader.sol";
import {IGlpManager} from "src/interface/IGlpManager.sol";
import {IReader} from "src/interface/IReader.sol";
import {IWBTC} from "src/interface/IWBTC.sol";
import {Vault} from "src/external/Vault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract PirexGlpTest is Test {
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

    address internal constant POSITION_ROUTER =
        0x3D6bA331e3D9702C5e8A8d254e5d8a285F223aba;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    uint256 internal constant FEE_BPS = 25;
    uint256 internal constant TAX_BPS = 50;
    uint256 internal constant BPS_DIVISOR = 10_000;
    uint256 internal constant SLIPPAGE = 30;
    uint256 internal constant PRECISION = 1e30;
    uint256 internal constant EXPANDED_GLP_DECIMALS = 1e18;
    uint256 internal constant INFO_USDG_AMOUNT = 1e18;

    event Mint(
        address indexed caller,
        uint256 indexed minShares,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 assets
    );

    constructor() {
        pirexGlp = new PirexGlp();
    }

    /**
        @notice Get minimum price for whitelisted token
        @param  token  address  Token
        @return uint256[]  Vault token info for ETH
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
        @return uint256  GLP price
     */
    function _getGlpPrice() internal view returns (uint256) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(FEE_STAKED_GLP);
        uint256 aum = GLP_MANAGER.getAums()[0];
        uint256 glpSupply = READER.getTokenBalancesWithSupplies(
            address(0),
            tokens
        )[1];

        return (aum * EXPANDED_GLP_DECIMALS) / glpSupply;
    }

    /**
        @notice Get GLP buying fees
        @return uint256  GLP buying fees
     */
    function _getFees(uint256 etherAmount, uint256[] memory info)
        internal
        view
        returns (uint256)
    {
        uint256 initialAmount = info[2];
        uint256 nextAmount = initialAmount +
            ((etherAmount * info[10]) / PRECISION);
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
        @notice Calculate the minimum amount of GLP received for ETH
        @param  token     address  Token address
        @param  amount    uint256  Amount of tokens
        @param  decimals  uint256  Token decimals for expansion purposes
     */
    function _calculateMinGlpAmount(
        address token,
        uint256 amount,
        uint256 decimals
    ) internal view returns (uint256) {
        uint256[] memory info = _getVaultTokenInfo(token);
        uint256 glpAmount = (amount * info[10]) / _getGlpPrice();
        uint256 minGlp = (glpAmount * (BPS_DIVISOR - _getFees(amount, info))) /
            BPS_DIVISOR;
        uint256 minGlpWithSlippage = (minGlp * (BPS_DIVISOR - SLIPPAGE)) /
            BPS_DIVISOR;

        // Expand min GLP amount decimals based on the input token's decimals
        return
            decimals == 18
                ? minGlpWithSlippage
                : 10**(18 - decimals) * minGlpWithSlippage;
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

    /*//////////////////////////////////////////////////////////////
                        GMX-related TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test for verifying correctness of GLP buy minimum calculation
        @param  etherAmount  uint256  Amount of ether in wei units
     */
    function testMintAndStakeGlpETH(uint256 etherAmount) public {
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
        uint256 premintPxGlp = pirexGlp.balanceOf(receiver);
        uint256 premintTotalAssets = pirexGlp.totalAssets();

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
        uint256 pxGlpReceived = pirexGlp.balanceOf(receiver) - premintPxGlp;
        uint256 totalAssetsIncrease = pirexGlp.totalAssets() -
            premintTotalAssets;

        assertEq(address(this).balance, premintETHBalance - etherAmount);
        assertGt(pxGlpReceived, 0);
        assertEq(pxGlpReceived, totalAssetsIncrease);
        assertEq(totalAssetsIncrease, assets);
        assertGe(pxGlpReceived, minGlpAmount);
        assertGe(totalAssetsIncrease, minGlpAmount);
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

        vm.expectRevert(abi.encodeWithSelector(PirexGlp.InvalidToken.selector, invalidToken));

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
        uint256 premintPxGlp = pirexGlp.balanceOf(receiver);
        uint256 premintTotalAssets = pirexGlp.totalAssets();

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
        uint256 pxGlpReceived = pirexGlp.balanceOf(receiver) - premintPxGlp;
        uint256 totalAssetsIncrease = pirexGlp.totalAssets() -
            premintTotalAssets;

        assertEq(
            WBTC.balanceOf(address(this)),
            premintWBTCBalance - tokenAmount
        );
        assertGt(pxGlpReceived, 0);
        assertEq(pxGlpReceived, totalAssetsIncrease);
        assertEq(totalAssetsIncrease, assets);
        assertGe(pxGlpReceived, minGlpAmount);
        assertGe(totalAssetsIncrease, minGlpAmount);
    }
}
