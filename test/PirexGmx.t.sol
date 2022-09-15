// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexGmx} from "src/PirexGmx.sol";
import {IRewardDistributor} from "src/interfaces/IRewardDistributor.sol";
import {IWETH} from "src/interfaces/IWETH.sol";
import {DelegateRegistry} from "src/external/DelegateRegistry.sol";
import {Helper} from "./Helper.sol";

contract PirexGmxTest is Test, Helper {
    bytes32 internal constant DEFAULT_DELEGATION_SPACE = bytes32("gmx.eth");
    bytes internal constant PAUSED_ERROR = "Pausable: paused";
    bytes internal constant NOT_PAUSED_ERROR = "Pausable: not paused";
    bytes internal constant INSUFFICIENT_OUTPUT_ERROR =
        "GlpManager: insufficient output";
    bytes internal constant INSUFFICIENT_GLP_OUTPUT_ERROR =
        "GlpManager: insufficient GLP output";

    /**
        @notice Get an address that is unauthorized (i.e. not owner)
        @return unauthorizedCaller  address  Unauthorized caller
     */
    function _getUnauthorizedCaller()
        internal
        returns (address unauthorizedCaller)
    {
        unauthorizedCaller = testAccounts[0];

        assertTrue(unauthorizedCaller != pirexGmx.owner());
    }

    /**
        @notice Pause and verify pause state for contract
     */
    function _pauseContract() internal {
        pirexGmx.setPauseState(true);

        assertEq(true, pirexGmx.paused());
    }

    /**
        @notice Set fee and verify contract state
        @param  f    enum     Fee type
        @param  fee  uint256  Fee
     */
    function _setFee(PirexGmx.Fees f, uint256 fee) internal {
        pirexGmx.setFee(f, fee);

        assertEq(fee, pirexGmx.fees(f));
    }

    /*//////////////////////////////////////////////////////////////
                            setFee TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetFeeUnauthorized() external {
        address unauthorizedCaller = _getUnauthorizedCaller();
        uint256 fee = 1;

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.setFee(PirexGmx.Fees.Deposit, fee);
    }

    /**
        @notice Test tx reversion: fee is invalid
     */
    function testCannotSetFeeInvalidFee() external {
        uint256 invalidFee = feeMax + 1;

        for (uint256 i; i < feeTypes.length; ++i) {
            vm.expectRevert(PirexGmx.InvalidFee.selector);

            pirexGmx.setFee(feeTypes[i], invalidFee);
        }
    }

    /**
        @notice Test tx success: set fees for each type
        @param  depositFee     uint24  Deposit fee
        @param  redemptionFee  uint24  Redemption fee
        @param  rewardFee      uint24  Reward fee
     */
    function testSetFee(
        uint24 depositFee,
        uint24 redemptionFee,
        uint24 rewardFee
    ) external {
        vm.assume(depositFee != 0);
        vm.assume(depositFee <= feeMax);
        vm.assume(redemptionFee != 0);
        vm.assume(redemptionFee < feeMax);
        vm.assume(rewardFee != 0);
        vm.assume(rewardFee < feeMax);

        PirexGmx.Fees depositFeeType = feeTypes[0];
        PirexGmx.Fees redemptionFeeType = feeTypes[1];
        PirexGmx.Fees rewardFeeType = feeTypes[2];

        assertEq(0, pirexGmx.fees(depositFeeType));
        assertEq(0, pirexGmx.fees(redemptionFeeType));
        assertEq(0, pirexGmx.fees(rewardFeeType));

        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetFee(depositFeeType, depositFee);

        pirexGmx.setFee(depositFeeType, depositFee);

        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetFee(redemptionFeeType, redemptionFee);

        pirexGmx.setFee(redemptionFeeType, redemptionFee);

        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetFee(rewardFeeType, rewardFee);

        pirexGmx.setFee(rewardFeeType, rewardFee);

        assertEq(depositFee, pirexGmx.fees(depositFeeType));
        assertEq(redemptionFee, pirexGmx.fees(redemptionFeeType));
        assertEq(rewardFee, pirexGmx.fees(rewardFeeType));
    }

    /*//////////////////////////////////////////////////////////////
                        setContract TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetContractNotAuthorized() external {
        address unauthorizedCaller = _getUnauthorizedCaller();
        address contractAddress = address(this);

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.setContract(
            PirexGmx.Contracts.RewardRouterV2,
            contractAddress
        );
    }

    /**
        @notice Test tx reversion: contractAddress is the zero address
     */
    function testCannotSetContractZeroAddress() external {
        address invalidContractAddress = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.setContract(
            PirexGmx.Contracts.RewardRouterV2,
            invalidContractAddress
        );
    }

    /**
        @notice Test tx success: set gmxRewardRouterV2 to a new contract address
     */
    function testSetContractRewardRouterV2() external {
        address currentContractAddress = address(pirexGmx.gmxRewardRouterV2());
        address contractAddress = address(this);

        // Validate existing state
        assertFalse(currentContractAddress == contractAddress);

        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetContract(PirexGmx.Contracts.RewardRouterV2, contractAddress);

        pirexGmx.setContract(
            PirexGmx.Contracts.RewardRouterV2,
            contractAddress
        );

        assertEq(contractAddress, address(pirexGmx.gmxRewardRouterV2()));
    }

    /**
        @notice Test tx success: set rewardTrackerGmx to a new contract address
     */
    function testSetContractRewardTrackerGmx() external {
        address currentContractAddress = address(pirexGmx.rewardTrackerGmx());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetContract(PirexGmx.Contracts.RewardTrackerGmx, contractAddress);

        pirexGmx.setContract(
            PirexGmx.Contracts.RewardTrackerGmx,
            contractAddress
        );

        assertEq(contractAddress, address(pirexGmx.rewardTrackerGmx()));
    }

    /**
        @notice Test tx success: set rewardTrackerGlp to a new contract address
     */
    function testSetContractRewardTrackerGlp() external {
        address currentContractAddress = address(pirexGmx.rewardTrackerGlp());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetContract(PirexGmx.Contracts.RewardTrackerGlp, contractAddress);

        pirexGmx.setContract(
            PirexGmx.Contracts.RewardTrackerGlp,
            contractAddress
        );

        assertEq(contractAddress, address(pirexGmx.rewardTrackerGlp()));
    }

    /**
        @notice Test tx success: set feeStakedGlp to a new contract address
     */
    function testSetContractFeeStakedGlp() external {
        address currentContractAddress = address(pirexGmx.feeStakedGlp());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetContract(PirexGmx.Contracts.FeeStakedGlp, contractAddress);

        pirexGmx.setContract(PirexGmx.Contracts.FeeStakedGlp, contractAddress);

        assertEq(contractAddress, address(pirexGmx.feeStakedGlp()));
    }

    /**
        @notice Test tx success: set stakedGmx to a new contract address
     */
    function testSetContractStakedGmx() external {
        address currentContractAddress = address(pirexGmx.stakedGmx());
        uint256 currentContractAddressAllowance = type(uint256).max;
        address contractAddress = address(this);

        assertFalse(contractAddress == currentContractAddress);
        assertEq(
            currentContractAddressAllowance,
            GMX.allowance(address(pirexGmx), currentContractAddress)
        );

        uint256 expectedCurrentContractAllowance = 0;
        uint256 expectedContractAddressAllowance = type(uint256).max;

        assertFalse(
            currentContractAddressAllowance == expectedCurrentContractAllowance
        );

        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetContract(PirexGmx.Contracts.StakedGmx, contractAddress);

        pirexGmx.setContract(PirexGmx.Contracts.StakedGmx, contractAddress);

        assertEq(contractAddress, address(pirexGmx.stakedGmx()));
        assertEq(
            expectedCurrentContractAllowance,
            GMX.allowance(address(pirexGmx), currentContractAddress)
        );
        assertEq(
            expectedContractAddressAllowance,
            GMX.allowance(address(pirexGmx), contractAddress)
        );
    }

    /**
        @notice Test tx success: set gmxVault to a new contract address
     */
    function testSetContractGmxVault() external {
        address currentContractAddress = address(pirexGmx.gmxVault());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetContract(PirexGmx.Contracts.GmxVault, contractAddress);

        pirexGmx.setContract(PirexGmx.Contracts.GmxVault, contractAddress);

        assertEq(contractAddress, address(pirexGmx.gmxVault()));
    }

    /**
        @notice Test tx success: set glpManager to a new contract address
     */
    function testSetContractGlpManager() external {
        address currentContractAddress = address(pirexGmx.glpManager());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetContract(PirexGmx.Contracts.GlpManager, contractAddress);

        pirexGmx.setContract(PirexGmx.Contracts.GlpManager, contractAddress);

        assertEq(contractAddress, address(pirexGmx.glpManager()));
    }

    /**
        @notice Test tx success: set pirexRewards to a new contract address
     */
    function testSetContractPirexRewards() external {
        address currentContractAddress = address(pirexGmx.pirexRewards());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetContract(PirexGmx.Contracts.PirexRewards, contractAddress);

        pirexGmx.setContract(PirexGmx.Contracts.PirexRewards, contractAddress);

        assertEq(contractAddress, address(pirexGmx.pirexRewards()));
    }

    /*//////////////////////////////////////////////////////////////
                        depositGmx TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotDepositGmxPaused() external {
        _pauseContract();

        uint256 assets = 1;
        address receiver = address(this);

        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.depositGmx(assets, receiver);
    }

    /**
        @notice Test tx reversion: assets is zero
     */
    function testCannotDepositGmxAssetsZeroAmount() external {
        uint256 invalidAssets = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGmx(invalidAssets, receiver);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotDepositGmxReceiverZeroAddress() external {
        uint256 assets = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.depositGmx(assets, invalidReceiver);
    }

    /**
        @notice Test tx reversion: insufficient GMX balance
        @param  assets      uint80  GMX amount
        @param  mintAmount  uint80  GMX mint amount
     */
    function testCannotDepositGmxInsufficientBalance(
        uint80 assets,
        uint80 mintAmount
    ) external {
        vm.assume(assets != 0);
        vm.assume(mintAmount < assets);

        address receiver = address(this);

        _mintGmx(mintAmount);

        vm.expectRevert("TRANSFER_FROM_FAILED");

        pirexGmx.depositGmx(assets, receiver);
    }

    /**
        @notice Test tx success: deposit GMX for pxGMX
        @param  assets      uint80  GMX amount
        @param  mintAmount  uint80  GMX mint amount
        @param  depositFee  uint24  Deposit fee
     */
    function testDepositGmx(
        uint80 assets,
        uint80 mintAmount,
        uint24 depositFee
    ) external {
        vm.assume(assets != 0);
        vm.assume(assets <= mintAmount);
        vm.assume(depositFee <= feeMax);

        _setFee(PirexGmx.Fees.Deposit, depositFee);
        _mintGmx(mintAmount);
        GMX.approve(address(pirexGmx), assets);

        address caller = address(this);
        address receiver = testAccounts[0];
        (uint256 postFeeAmount, uint256 feeAmount) = _deriveAssetAmounts(
            PirexGmx.Fees.Deposit,
            assets
        );
        uint256 expectedPreDepositGmxBalancePirexGmx = 0;
        uint256 expectedPreDepositGmxBalanceCaller = mintAmount;
        uint256 expectedPreDepositPxGmxBalanceReceiver = 0;

        assertFalse(caller == receiver);
        assertEq(
            expectedPreDepositGmxBalancePirexGmx,
            REWARD_TRACKER_GMX.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPreDepositGmxBalanceCaller, GMX.balanceOf(caller));
        assertEq(
            expectedPreDepositPxGmxBalanceReceiver,
            pxGmx.balanceOf(receiver)
        );

        uint256 expectedPostDepositGmxBalancePirexGmx = expectedPreDepositGmxBalancePirexGmx +
                assets;
        uint256 expectedPostDepositGmxBalanceCaller = expectedPreDepositGmxBalanceCaller -
                assets;
        uint256 expectedPostDepositPxGmxBalanceReceiver = expectedPreDepositPxGmxBalanceReceiver +
                postFeeAmount;

        vm.expectEmit(true, true, false, true, address(pirexGmx));

        emit DepositGmx(caller, receiver, assets, postFeeAmount, feeAmount);

        pirexGmx.depositGmx(assets, receiver);

        assertEq(
            expectedPostDepositGmxBalancePirexGmx,
            REWARD_TRACKER_GMX.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPostDepositGmxBalanceCaller, GMX.balanceOf(caller));
        assertEq(
            expectedPostDepositPxGmxBalanceReceiver,
            pxGmx.balanceOf(receiver)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        depositGlpETH TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotDepositGlpETHPaused() external {
        _pauseContract();

        uint256 etherAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.depositGlpETH{value: etherAmount}(minUsdg, minGlp, receiver);
    }

    /**
        @notice Test tx reversion: msg.value is zero
     */
    function testCannotDepositGlpETHMsgValueZeroAmount() external {
        uint256 invalidEtherAmount = 0;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGlpETH{value: invalidEtherAmount}(
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minUsdg is zero
     */
    function testCannotDepositGlpETHMinUsdgZeroAmount() external {
        uint256 etherAmount = 1 ether;
        uint256 invalidMinUsdg = 0;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGlpETH{value: etherAmount}(
            invalidMinUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is zero
     */
    function testCannotDepositGlpETHMinGlpZeroAmount() external {
        uint256 etherAmount = 1 ether;
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = 0;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGlpETH{value: etherAmount}(
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotDepositGlpETHReceiverZeroAddress() external {
        uint256 etherAmount = 1 ether;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address invalidReceiver = address(0);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.depositGlpETH{value: etherAmount}(
            minUsdg,
            minGlp,
            invalidReceiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is greater than output
     */
    function testCannotDepositGlpETHMinGlpInsufficientGlp() external {
        uint256 etherAmount = 1 ether;
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = _calculateMinGlpAmount(
            address(0),
            etherAmount,
            18
        ) * 2;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(INSUFFICIENT_GLP_OUTPUT_ERROR);

        pirexGmx.depositGlpETH{value: etherAmount}(
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx success: deposit for pxGLP with ETH
        @param  etherAmount  uint80  Ether amount
        @param  dealAmount   uint80  Ether deal amount
        @param  depositFee   uint24  Deposit fee
     */
    function testDepositGlpETH(
        uint80 etherAmount,
        uint80 dealAmount,
        uint24 depositFee
    ) external {
        vm.assume(etherAmount > 1e15);
        vm.assume(etherAmount < 1e22);
        vm.assume(dealAmount > etherAmount);
        vm.assume(depositFee <= feeMax);
        vm.deal(address(this), dealAmount);

        _setFee(PirexGmx.Fees.Deposit, depositFee);

        address caller = address(this);
        uint256 minUsdg = 1;
        uint256 minGlp = _calculateMinGlpAmount(address(0), etherAmount, 18);
        address receiver = testAccounts[0];
        uint256 expectedPreDepositGlpBalancePirexGmx = 0;
        uint256 expectedPreDepositETHBalanceCaller = dealAmount;
        uint256 expectedPreDepositPxGlpBalanceReceiver = 0;

        assertFalse(caller == receiver);
        assertEq(
            expectedPreDepositGlpBalancePirexGmx,
            FEE_STAKED_GLP.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPreDepositETHBalanceCaller, caller.balance);
        assertEq(
            expectedPreDepositPxGlpBalanceReceiver,
            pxGlp.balanceOf(receiver)
        );

        vm.expectEmit(true, true, true, false, address(pirexGmx));

        // Cannot test the `asset` member of the event since it's not known until after
        emit DepositGlp(
            address(this),
            receiver,
            address(0),
            etherAmount,
            minUsdg,
            minGlp,
            0,
            0,
            0
        );

        (uint256 postFeeAmount, uint256 feeAmount) = pirexGmx.depositGlpETH{
            value: etherAmount
        }(minUsdg, minGlp, receiver);
        uint256 assets = postFeeAmount + feeAmount;
        uint256 expectedPostDepositGlpBalancePirexGmx = expectedPreDepositGlpBalancePirexGmx + assets;
        uint256 expectedPostDepositETHBalanceCaller = expectedPreDepositETHBalanceCaller - etherAmount;
        uint256 expectedPostDepositPxGlpBalanceReceiver = expectedPreDepositPxGlpBalanceReceiver + postFeeAmount;

        assertEq(
            expectedPostDepositGlpBalancePirexGmx,
            FEE_STAKED_GLP.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPostDepositETHBalanceCaller, caller.balance);
        assertEq(
            expectedPostDepositPxGlpBalanceReceiver,
            pxGlp.balanceOf(receiver)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        depositGlp TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotDepositGlpPaused() external {
        _pauseContract();

        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.depositGlp(token, tokenAmount, minUsdg, minGlp, receiver);
    }

    /**
        @notice Test tx reversion: token is zero address
     */
    function testCannotDepositGlpTokenZeroAddress() external {
        address invalidToken = address(0);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.depositGlp(
            invalidToken,
            tokenAmount,
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: token is not whitelisted by GMX
     */
    function testCannotDepositGlpInvalidToken() external {
        address invalidToken = address(this);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(
            abi.encodeWithSelector(PirexGmx.InvalidToken.selector, invalidToken)
        );

        pirexGmx.depositGlp(
            invalidToken,
            tokenAmount,
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: token amount is zero
     */
    function testCannotDepositGlpTokenAmountZeroAmount() external {
        address token = address(WBTC);
        uint256 invalidTokenAmount = 0;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGlp(
            token,
            invalidTokenAmount,
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minUsdg is zero
     */
    function testCannotDepositGlpMinUsdgZeroAmount() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 invalidMinUsdg = 0;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGlp(
            token,
            tokenAmount,
            invalidMinUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is zero
     */
    function testCannotDepositGlpMinGlpZeroAmount() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotDepositGlpReceiverZeroAddress() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            minGlp,
            invalidReceiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is greater than output
     */
    function testCannotDepositGlpMinGlpInsufficientGlpOutput() external {
        address token = address(WBTC);
        uint256 tokenAmount = 1e8;
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = _calculateMinGlpAmount(token, tokenAmount, 8) *
            2;
        address receiver = address(this);

        _mintWbtc(tokenAmount);
        WBTC.approve(address(pirexGmx), tokenAmount);

        vm.expectRevert(INSUFFICIENT_GLP_OUTPUT_ERROR);

        pirexGmx.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx success: deposit for pxGLP with whitelisted ERC20 tokens
        @param  tokenAmount  uint40  Token amount
        @param  mintAmount   uint40  Token mint amount
        @param  depositFee   uint24  Deposit fee
     */
    function testDepositGlp(
        uint40 tokenAmount,
        uint40 mintAmount,
        uint24 depositFee
    ) external {
        vm.assume(tokenAmount > 1e7);
        vm.assume(tokenAmount < 100e8);
        vm.assume(mintAmount > tokenAmount);
        vm.assume(depositFee <= feeMax);

        _setFee(PirexGmx.Fees.Deposit, depositFee);
        _mintWbtc(mintAmount);
        WBTC.approve(address(pirexGmx), tokenAmount);

        address caller = address(this);
        address token = address(WBTC);
        uint256 minUsdg = 1;
        uint256 minGlp = _calculateMinGlpAmount(token, tokenAmount, 8);
        address receiver = testAccounts[0];

        // Commented out due to "Stack too deep..." compiler error
        // uint256 expectedPreDepositGlpBalancePirexGmx = 0;
        // uint256 expectedPreDepositWBTCBalanceCaller = mintAmount;
        // uint256 expectedPreDepositPxGlpBalanceReceiver = 0;

        assertFalse(caller == receiver);
        assertEq(0, FEE_STAKED_GLP.balanceOf(address(pirexGmx)));
        assertEq(mintAmount, WBTC.balanceOf(caller));
        assertEq(0, pxGlp.balanceOf(receiver));

        vm.expectEmit(true, true, true, false, address(pirexGmx));

        // Cannot test the `asset` member of the event since it's not known until after
        emit DepositGlp(
            address(this),
            receiver,
            token,
            tokenAmount,
            minUsdg,
            minGlp,
            0,
            0,
            0
        );

        (uint256 postFeeAmount, uint256 feeAmount) = pirexGmx.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            minGlp,
            receiver
        );
        uint256 assets = postFeeAmount + feeAmount;
        uint256 expectedPostDepositGlpBalancePirexGmx = assets;
        uint256 expectedPostDepositWBTCBalanceCaller = mintAmount - tokenAmount;
        uint256 expectedPostDepositPxGlpBalanceReceiver = postFeeAmount;

        assertEq(
            expectedPostDepositGlpBalancePirexGmx,
            FEE_STAKED_GLP.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPostDepositWBTCBalanceCaller, WBTC.balanceOf(caller));
        assertEq(
            expectedPostDepositPxGlpBalanceReceiver,
            pxGlp.balanceOf(receiver)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        redeemPxGlpETH TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotRedeemPxGlpETHPaused() external {
        (uint256 postFeeAmount, uint256 feeAmount) = _depositGlpETH(
            1 ether,
            address(this)
        );
        uint256 assets = postFeeAmount + feeAmount;
        uint256 minOut = _calculateMinOutAmount(address(WETH), assets);
        address receiver = testAccounts[0];

        // Pause after deposit
        _pauseContract();

        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.redeemPxGlpETH(assets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: assets is zero
     */
    function testCannotRedeemPxGlpETHAssetsZeroAmount() external {
        uint256 invalidAssets = 0;
        uint256 minOut = 1;
        address receiver = testAccounts[0];

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.redeemPxGlpETH(invalidAssets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: minOut is zero
     */
    function testCannotRedeemPxGlpETHMinOutZeroAmount() external {
        uint256 assets = 1;
        uint256 invalidMinOut = 0;
        address receiver = testAccounts[0];

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.redeemPxGlpETH(assets, invalidMinOut, receiver);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotRedeemPxGlpETHReceiverZeroAddress() external {
        uint256 assets = 1;
        uint256 minOut = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.redeemPxGlpETH(assets, minOut, invalidReceiver);
    }

    /**
        @notice Test tx reversion: minOut is greater than output
     */
    function testCannotRedeemPxGlpETHMinOutInsufficientOutput() external {
        (uint256 postFeeAmount, uint256 feeAmount) = _depositGlpETH(
            1 ether,
            address(this)
        );
        uint256 assets = postFeeAmount + feeAmount;
        uint256 invalidMinOut = _calculateMinOutAmount(address(WETH), assets) *
            2;
        address receiver = testAccounts[0];

        vm.expectRevert(INSUFFICIENT_OUTPUT_ERROR);

        pirexGmx.redeemPxGlpETH(assets, invalidMinOut, receiver);
    }

    /**
        @notice Test tx success: redeem pxGLP for ETH
        @param  etherAmount    uint80  Amount of ether in wei units
        @param  redemptionFee  uint24  Redemption fee
     */
    function testRedeemPxGlpETH(uint80 etherAmount, uint24 redemptionFee)
        external
    {
        vm.assume(etherAmount > 1e15);
        vm.assume(etherAmount < 1e22);
        vm.assume(redemptionFee != 0);
        vm.assume(redemptionFee <= feeMax);

        _setFee(PirexGmx.Fees.Redemption, redemptionFee);

        // Commented out due to "Stack too deep..." compiler error
        // address caller = address(this);

        (
            uint256 depositPostFeeAmount,
            uint256 depositFeeAmount
        ) = _depositGlpETH(1 ether, address(this));
        uint256 assets = depositPostFeeAmount + depositFeeAmount;
        (uint256 postFeeAmount, uint256 feeAmount) = _deriveAssetAmounts(
            PirexGmx.Fees.Redemption,
            assets
        );
        uint256 minOut = _calculateMinOutAmount(address(WETH), postFeeAmount);
        address receiver = testAccounts[0];
        uint256 pirexGmxBalanceBeforeRedemption = FEE_STAKED_GLP.balanceOf(
            address(pirexGmx)
        );

        // Commented out due to "Stack too deep..." compiler error
        // uint256 expectedPreRedeemGlpBalancePirexGmx = assets;
        // uint256 expectedPreRedeemPxGlpBalanceCaller = assets;
        // uint256 expectedPreRedeemWETHBalanceReceiver = 0;

        assertFalse(address(this) == receiver);
        assertEq(assets, pirexGmxBalanceBeforeRedemption);
        assertEq(assets, pxGlp.balanceOf(address(this)));
        assertEq(0, receiver.balance);

        pxGlp.approve(address(pirexGmx), assets);

        vm.expectEmit(true, true, true, false, address(pirexGmx));

        emit RedeemGlp(
            address(this),
            receiver,
            address(0),
            assets,
            minOut,
            0,
            postFeeAmount,
            feeAmount
        );

        uint256 redeemed = pirexGmx.redeemPxGlpETH(assets, minOut, receiver);
        uint256 expectedPostRedeemGlpBalancePirexGmx = pirexGmxBalanceBeforeRedemption -
                postFeeAmount;
        uint256 expectedPostRedeemPxGlpBalanceCaller = 0;
        uint256 expectedPostRedeemWETHBalanceReceiver = redeemed;

        assertEq(
            expectedPostRedeemGlpBalancePirexGmx,
            FEE_STAKED_GLP.balanceOf(address(pirexGmx))
        );
        assertEq(
            expectedPostRedeemPxGlpBalanceCaller,
            pxGlp.balanceOf(address(this))
        );
        assertEq(expectedPostRedeemWETHBalanceReceiver, receiver.balance);
    }

    /*//////////////////////////////////////////////////////////////
                        redeemPxGlp TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotRedeemPxGlpPaused() external {
        uint256 etherAmount = 1 ether;
        address token = address(WBTC);
        (uint256 postFeeAmount, uint256 feeAmount) = _depositGlpETH(
            etherAmount,
            address(this)
        );
        uint256 assets = postFeeAmount + feeAmount;
        uint256 minOut = _calculateMinOutAmount(token, assets);
        address receiver = testAccounts[0];

        // Pause after deposit
        _pauseContract();

        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.redeemPxGlp(token, assets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: token is zero address
     */
    function testCannotRedeemPxGlpTokenZeroAddress() external {
        address invalidToken = address(0);
        uint256 assets = 1;
        uint256 minOut = 1;
        address receiver = testAccounts[0];

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.redeemPxGlp(invalidToken, assets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: token is not whitelisted by GMX
     */
    function testCannotRedeemPxGlpInvalidToken() external {
        address invalidToken = address(this);
        uint256 assets = 1;
        uint256 minOut = 1;
        address receiver = testAccounts[0];

        vm.expectRevert(
            abi.encodeWithSelector(PirexGmx.InvalidToken.selector, invalidToken)
        );

        pirexGmx.redeemPxGlp(invalidToken, assets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: assets is zero
     */
    function testCannotRedeemPxGlpAssetsZeroAmount() external {
        address token = address(WBTC);
        uint256 invalidAssets = 0;
        uint256 minOut = 1;
        address receiver = testAccounts[0];

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.redeemPxGlp(token, invalidAssets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: minOut is zero
     */
    function testCannotRedeemPxGlpMinOutZeroAmount() external {
        address token = address(WBTC);
        uint256 assets = 1;
        uint256 invalidMinOut = 0;
        address receiver = testAccounts[0];

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.redeemPxGlp(token, assets, invalidMinOut, receiver);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotRedeemPxGlpReceiverZeroAddress() external {
        address token = address(WBTC);
        uint256 assets = 1;
        uint256 minOut = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.redeemPxGlp(token, assets, minOut, invalidReceiver);
    }

    /**
        @notice Test tx reversion: minOut is greater than output amount
     */
    function testCannotRedeemPxGlpMinOutInsufficientOutput() external {
        address token = address(WBTC);
        (uint256 postFeeAmount, uint256 feeAmount) = _depositGlp(
            1e8,
            address(this)
        );
        uint256 assets = postFeeAmount + feeAmount;
        uint256 invalidMinOut = _calculateMinOutAmount(token, assets) * 2;
        address receiver = testAccounts[0];

        vm.expectRevert(INSUFFICIENT_OUTPUT_ERROR);

        pirexGmx.redeemPxGlp(token, assets, invalidMinOut, receiver);
    }

    /**
        @notice Test tx success: redeem pxGLP for whitelisted ERC20 tokens
        @param  tokenAmount    uint40  Token amount
        @param  redemptionFee  uint24  Redemption fee
     */
    function testRedeemPxGlp(uint40 tokenAmount, uint24 redemptionFee)
        external
    {
        vm.assume(tokenAmount > 1e5);
        vm.assume(tokenAmount < 100e8);
        vm.assume(redemptionFee != 0);
        vm.assume(redemptionFee <= feeMax);

        _setFee(PirexGmx.Fees.Redemption, redemptionFee);

        // Commented out due to "Stack too deep..." compiler error
        // address caller = address(this);
        // address token = address(WBTC);

        (uint256 depositPostFeeAmount, uint256 depositFeeAmount) = _depositGlp(
            tokenAmount,
            address(this)
        );
        uint256 assets = depositPostFeeAmount + depositFeeAmount;
        (uint256 postFeeAmount, uint256 feeAmount) = _deriveAssetAmounts(
            PirexGmx.Fees.Redemption,
            assets
        );
        uint256 minOut = _calculateMinOutAmount(address(WBTC), postFeeAmount);
        address receiver = testAccounts[0];
        uint256 pirexGmxBalanceBeforeRedemption = FEE_STAKED_GLP.balanceOf(
            address(pirexGmx)
        );

        // Commented out due to "Stack too deep..." compiler error
        // uint256 expectedPreRedeemGlpBalancePirexGmx = assets;
        // uint256 expectedPreRedeemPxGlpBalanceCaller = assets;
        // uint256 expectedPreRedeemWBTCBalanceReceiver = 0;

        assertFalse(address(this) == receiver);
        assertEq(assets, pirexGmxBalanceBeforeRedemption);
        assertEq(assets, pxGlp.balanceOf(address(this)));
        assertEq(0, WBTC.balanceOf(receiver));

        pxGlp.approve(address(pirexGmx), assets);

        vm.expectEmit(true, true, true, false, address(pirexGmx));

        emit RedeemGlp(
            address(this),
            receiver,
            address(WBTC),
            assets,
            minOut,
            0,
            postFeeAmount,
            feeAmount
        );

        uint256 redeemed = pirexGmx.redeemPxGlp(
            address(WBTC),
            assets,
            minOut,
            receiver
        );
        uint256 expectedPostRedeemGlpBalancePirexGmx = pirexGmxBalanceBeforeRedemption -
                postFeeAmount;
        uint256 expectedPostRedeemPxGlpBalanceCaller = 0;
        uint256 expectedPostRedeemWBTCBalanceReceiver = redeemed;

        assertEq(
            expectedPostRedeemGlpBalancePirexGmx,
            FEE_STAKED_GLP.balanceOf(address(pirexGmx))
        );
        assertEq(
            expectedPostRedeemPxGlpBalanceCaller,
            pxGlp.balanceOf(address(this))
        );
        assertEq(
            expectedPostRedeemWBTCBalanceReceiver,
            WBTC.balanceOf(receiver)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        claimRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not pirexRewards
     */
    function testCannotClaimRewardsNotPirexRewards() external {
        assertTrue(address(this) != pirexGmx.pirexRewards());

        vm.expectRevert(PirexGmx.NotPirexRewards.selector);

        pirexGmx.claimRewards();
    }

    /**
        @notice Test tx success: claim WETH, esGMX, and bnGMX/MP rewards
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
        vm.assume(wbtcAmount > 1e5);
        vm.assume(wbtcAmount < 100e8);
        vm.assume(gmxAmount > 1e15);
        vm.assume(gmxAmount < 1000000e18);

        _depositGlp(wbtcAmount, address(this));
        _depositGmx(gmxAmount, address(this));

        vm.warp(block.timestamp + secondsElapsed);

        // Commented out due to "Stack too deep..." error
        // uint256 expectedWethBalanceBeforeClaim = 0;
        // uint256 expectedEsGmxBalanceBeforeClaim = 0;

        assertEq(0, WETH.balanceOf(address(pirexGmx)));
        assertEq(0, STAKED_GMX.depositBalances(address(pirexGmx), ES_GMX));

        uint256 previousStakedGmxBalance = REWARD_TRACKER_GMX.balanceOf(
            address(pirexGmx)
        );
        uint256 expectedWETHRewardsGmx = pirexGmx.calculateRewards(true, true);
        uint256 expectedWETHRewardsGlp = pirexGmx.calculateRewards(true, false);
        uint256 expectedEsGmxRewardsGmx = pirexGmx.calculateRewards(
            false,
            true
        );
        uint256 expectedEsGmxRewardsGlp = pirexGmx.calculateRewards(
            false,
            false
        );
        uint256 expectedBnGmxRewards = calculateBnGmxRewards(address(pirexGmx));
        uint256 expectedWETHRewards = expectedWETHRewardsGmx +
            expectedWETHRewardsGlp;
        uint256 expectedEsGmxRewards = expectedEsGmxRewardsGmx +
            expectedEsGmxRewardsGlp;

        vm.expectEmit(false, false, false, true, address(pirexGmx));

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
        vm.prank(address(pirexRewards));

        (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = pirexGmx.claimRewards();

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

        // Commented out due to "Stack too deep..." error
        // uint256 expectedWethBalanceAfterClaim = expectedWETHRewards;
        // uint256 expectedEsGmxBalanceAfterClaim = expectedEsGmxRewards;

        assertEq(expectedWETHRewards, WETH.balanceOf(address(pirexGmx)));
        assertEq(
            expectedEsGmxRewards,
            STAKED_GMX.depositBalances(address(pirexGmx), ES_GMX)
        );

        // Claimable reward amounts should all be zero post-claim
        assertEq(0, pirexGmx.calculateRewards(true, true));
        assertEq(0, pirexGmx.calculateRewards(true, false));
        assertEq(0, pirexGmx.calculateRewards(false, true));
        assertEq(0, pirexGmx.calculateRewards(false, false));
        assertEq(0, calculateBnGmxRewards(address(pirexGmx)));

        // Claimed esGMX rewards + MP should also be staked immediately
        assertEq(
            previousStakedGmxBalance +
                expectedEsGmxRewards +
                expectedBnGmxRewards,
            REWARD_TRACKER_GMX.balanceOf(address(pirexGmx))
        );
    }

    /*//////////////////////////////////////////////////////////////
                        claimUserReward TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not pirexRewards
     */
    function testCannotClaimUserRewardNotPirexRewards() external {
        address receiver = address(this);
        address token = address(WETH);
        uint256 amount = 1;

        assertTrue(address(this) != pirexGmx.pirexRewards());

        vm.expectRevert(PirexGmx.NotPirexRewards.selector);

        pirexGmx.claimUserReward(receiver, token, amount);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotClaimUserRewardRecipientZeroAddress() external {
        address invalidReceiver = address(0);
        address token = address(WETH);
        uint256 amount = 1;

        vm.expectRevert(PirexGmx.ZeroAddress.selector);
        vm.prank(address(pirexRewards));

        pirexGmx.claimUserReward(invalidReceiver, token, amount);
    }

    /**
        @notice Test tx reversion: token is zero address
     */
    function testCannotClaimUserRewardTokenZeroAddress() external {
        address receiver = address(this);
        address token = address(0);
        uint256 amount = 1;

        vm.expectRevert(PirexGmx.ZeroAddress.selector);
        vm.prank(address(pirexRewards));

        pirexGmx.claimUserReward(receiver, token, amount);
    }

    /**
        @notice Test tx success: claim user reward
        @param  wethAmount   uint80  Amount of claimable WETH
        @param  pxGmxAmount  uint80  Amount of claimable pxGMX
     */
    function testClaimUserReward(uint80 wethAmount, uint80 pxGmxAmount)
        external
    {
        vm.assume(wethAmount > 0.001 ether);
        vm.assume(wethAmount < 1_000 ether);
        vm.assume(pxGmxAmount != 0);
        vm.assume(pxGmxAmount < 1000000e18);

        address receiver = address(this);
        address tokenWeth = address(WETH);
        address tokenPxGmx = address(pxGmx);

        assertEq(0, WETH.balanceOf(receiver));
        assertEq(0, pxGmx.balanceOf(receiver));

        // Mint and transfers tokens for user claim tests
        vm.deal(address(this), wethAmount);

        IWETH(tokenWeth).depositTo{value: wethAmount}(address(pirexGmx));

        vm.prank(address(pirexGmx));

        pxGmx.mint(address(pirexGmx), pxGmxAmount);

        // Test claim via PirexRewards contract
        vm.startPrank(address(pirexRewards));

        pirexGmx.claimUserReward(receiver, tokenWeth, wethAmount);
        pirexGmx.claimUserReward(receiver, tokenPxGmx, pxGmxAmount);

        vm.stopPrank();

        assertEq(WETH.balanceOf(receiver), wethAmount);
        assertEq(pxGmx.balanceOf(receiver), pxGmxAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        setDelegationSpace TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetDelegationSpaceUnauthorized() external {
        string memory space = "test.eth";
        bool clear = false;
        address unauthorizedCaller = _getUnauthorizedCaller();

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.setDelegationSpace(space, clear);
    }

    /**
        @notice Test tx reversion: space is empty string
     */
    function testCannotSetDelegationSpaceEmptyString() external {
        string memory invalidSpace = "";
        bool clear = false;

        vm.expectRevert(PirexGmx.EmptyString.selector);

        pirexGmx.setDelegationSpace(invalidSpace, clear);
    }

    /**
        @notice Test tx success: set delegation space
        @param  clear  bool  Whether to clear the vote delegate
     */
    function testSetDelegationSpace(bool clear) external {
        DelegateRegistry d = DelegateRegistry(pirexGmx.delegateRegistry());
        address voteDelegate = address(this);

        // Set the vote delegate before clearing it when setting new delegation space
        pirexGmx.setVoteDelegate(voteDelegate);

        assertEq(DEFAULT_DELEGATION_SPACE, pirexGmx.delegationSpace());
        assertEq(
            voteDelegate,
            d.delegation(address(pirexGmx), DEFAULT_DELEGATION_SPACE)
        );

        string memory space = "new.eth";
        bytes32 expectedDelegationSpace = bytes32(bytes(space));
        address expectedVoteDelegate = clear ? address(0) : voteDelegate;

        assertFalse(expectedDelegationSpace == DEFAULT_DELEGATION_SPACE);

        vm.expectEmit(false, false, false, true, address(pirexGmx));

        emit SetDelegationSpace(space, clear);

        pirexGmx.setDelegationSpace(space, clear);

        assertEq(expectedDelegationSpace, pirexGmx.delegationSpace());
        assertEq(
            expectedVoteDelegate,
            d.delegation(address(pirexGmx), DEFAULT_DELEGATION_SPACE)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        setVoteDelegate TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetVoteDelegateUnauthorized() external {
        address unauthorizedCaller = _getUnauthorizedCaller();
        address delegate = address(this);

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.setVoteDelegate(delegate);
    }

    /**
        @notice Test tx reversion: delegate is zero address
     */
    function testCannotSetVoteDelegateDelegateZeroAddress() external {
        address invalidDelegate = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.setVoteDelegate(invalidDelegate);
    }

    /**
        @notice Test tx success: set vote delegate
     */
    function testSetVoteDelegate() external {
        address oldDelegate = delegateRegistry.delegation(
            address(pirexGmx),
            pirexGmx.delegationSpace()
        );
        address newDelegate = address(this);

        assertTrue(oldDelegate != newDelegate);

        vm.expectEmit(false, false, false, true, address(pirexGmx));

        emit SetVoteDelegate(newDelegate);

        pirexGmx.setVoteDelegate(newDelegate);

        address delegate = delegateRegistry.delegation(
            address(pirexGmx),
            pirexGmx.delegationSpace()
        );

        assertEq(delegate, newDelegate);
    }

    /*//////////////////////////////////////////////////////////////
                        clearVoteDelegate TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotClearVoteDelegateUnauthorized() external {
        address unauthorizedCaller = _getUnauthorizedCaller();

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.clearVoteDelegate();
    }

    /**
        @notice Test tx reversion: clear with no delegate set
     */
    function testCannotClearVoteDelegateNoDelegate() external {
        assertEq(
            address(0),
            delegateRegistry.delegation(
                address(pirexGmx),
                pirexGmx.delegationSpace()
            )
        );

        vm.expectRevert("No delegate set");

        pirexGmx.clearVoteDelegate();
    }

    /**
        @notice Test tx success: clear vote delegate
     */
    function testClearVoteDelegate() external {
        pirexGmx.setDelegationSpace("test.eth", false);

        address voteDelegate = address(this);

        // Set the vote delegate before clearing it when setting new delegation space
        pirexGmx.setVoteDelegate(voteDelegate);

        assertEq(
            voteDelegate,
            delegateRegistry.delegation(
                address(pirexGmx),
                pirexGmx.delegationSpace()
            )
        );

        vm.expectEmit(false, false, false, true, address(pirexGmx));

        emit ClearVoteDelegate();

        pirexGmx.clearVoteDelegate();

        assertEq(
            address(0),
            delegateRegistry.delegation(
                address(pirexGmx),
                pirexGmx.delegationSpace()
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        setPauseState TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetPauseStateUnauthorized() external {
        address unauthorizedCaller = _getUnauthorizedCaller();

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.setPauseState(true);
    }

    /**
        @notice Test tx reversion: contract is not paused
     */
    function testCannotSetPauseStateNotPaused() external {
        assertEq(false, pirexGmx.paused());

        vm.expectRevert(NOT_PAUSED_ERROR);

        pirexGmx.setPauseState(false);
    }

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotSetPauseStatePaused() external {
        pirexGmx.setPauseState(true);

        assertEq(true, pirexGmx.paused());

        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.setPauseState(true);
    }

    /**
        @notice Test tx success: set pause state
     */
    function testSetPauseState() external {
        assertEq(false, pirexGmx.paused());

        pirexGmx.setPauseState(true);

        assertEq(true, pirexGmx.paused());

        pirexGmx.setPauseState(false);

        assertEq(false, pirexGmx.paused());
    }

    /*//////////////////////////////////////////////////////////////
                        initiateMigration TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is not paused
     */
    function testCannotInitiateMigrationNotPaused() external {
        assertEq(false, pirexGmx.paused());

        address newContract = address(this);

        vm.expectRevert(NOT_PAUSED_ERROR);

        pirexGmx.initiateMigration(newContract);
    }

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotInitiateMigrationUnauthorized() external {
        _pauseContract();

        address unauthorizedCaller = _getUnauthorizedCaller();
        address newContract = address(this);

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.initiateMigration(newContract);
    }

    /**
        @notice Test tx reversion: newContract is zero address
     */
    function testCannotInitiateMigrationNewContractZeroAddress() external {
        _pauseContract();

        address invalidNewContract = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.initiateMigration(invalidNewContract);
    }

    /**
        @notice Test tx success: initiate migration
     */
    function testInitiateMigration() external {
        _pauseContract();

        address oldContract = address(pirexGmx);
        address newContract = address(this);
        address expectedPendingReceiverBeforeInitation = address(0);

        assertEq(
            expectedPendingReceiverBeforeInitation,
            REWARD_ROUTER_V2.pendingReceivers(oldContract)
        );

        vm.expectEmit(false, false, false, true, address(pirexGmx));

        emit InitiateMigration(newContract);

        pirexGmx.initiateMigration(newContract);

        address expectedPendingReceiverAfterInitation = newContract;

        // Should properly set the pendingReceivers state
        assertEq(
            expectedPendingReceiverAfterInitation,
            REWARD_ROUTER_V2.pendingReceivers(oldContract)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        completeMigration TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is not paused
     */
    function testCannotCompleteMigrationNotPaused() external {
        assertEq(false, pirexGmx.paused());

        address oldContract = address(this);

        vm.expectRevert(NOT_PAUSED_ERROR);

        pirexGmx.completeMigration(oldContract);
    }

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotCompleteMigrationUnauthorized() external {
        _pauseContract();

        address unauthorizedCaller = _getUnauthorizedCaller();
        address oldContract = address(pirexGmx);

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.completeMigration(oldContract);
    }

    /**
        @notice Test tx reversion: oldContract is zero address
     */
    function testCannotCompleteMigrationZeroAddress() external {
        _pauseContract();

        address invalidOldContract = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.completeMigration(invalidOldContract);
    }

    /**
        @notice Test tx reversion due to the caller not being the assigned new contract
     */
    function testCannotCompleteMigrationInvalidNewContract() external {
        _pauseContract();

        address oldContract = address(pirexGmx);
        address newContract = address(this);

        pirexGmx.initiateMigration(newContract);

        assertEq(newContract, REWARD_ROUTER_V2.pendingReceivers(oldContract));

        // Deploy a test contract but not assign it as the migration target
        PirexGmx newPirexGmx = new PirexGmx(
            address(pxGmx),
            address(pxGlp),
            address(pirexFees),
            address(pirexRewards),
            address(delegateRegistry)
        );

        vm.expectRevert("RewardRouter: transfer not signalled");

        newPirexGmx.completeMigration(oldContract);
    }

    /**
        @notice Test completing migration
     */
    function testCompleteMigration() external {
        // Perform GMX deposit for balance tests after migration
        uint256 assets = 1e18;
        address receiver = address(this);
        address oldContract = address(pirexGmx);

        _mintGmx(assets);
        GMX.approve(oldContract, assets);
        pirexGmx.depositGmx(assets, receiver);

        // Perform GLP deposit for balance tests after migration
        uint256 etherAmount = 1 ether;

        vm.deal(address(this), etherAmount);

        pirexGmx.depositGlpETH{value: etherAmount}(1, 1, receiver);

        // Time skip to bypass the cooldown duration
        vm.warp(block.timestamp + 1 days);

        // Store the staked balances for later validations
        uint256 oldStakedGmxBalance = REWARD_TRACKER_GMX.balanceOf(oldContract);
        uint256 oldStakedGlpBalance = FEE_STAKED_GLP.balanceOf(oldContract);
        uint256 oldEsGmxClaimable = pirexGmx.calculateRewards(false, true) +
            pirexGmx.calculateRewards(false, false);
        uint256 oldMpBalance = REWARD_TRACKER_MP.claimable(oldContract);

        // Pause the contract before proceeding
        _pauseContract();

        // Deploy the new contract for migration tests
        PirexGmx newPirexGmx = new PirexGmx(
            address(pxGmx),
            address(pxGlp),
            address(pirexFees),
            address(pirexRewards),
            address(delegateRegistry)
        );

        address newContract = address(newPirexGmx);

        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), address(0));

        pirexGmx.initiateMigration(newContract);

        // Should properly set the pendingReceivers state
        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), newContract);

        vm.expectEmit(false, false, false, true, address(newPirexGmx));

        emit CompleteMigration(oldContract);

        // Complete the migration using the new contract
        newPirexGmx.completeMigration(oldContract);

        // Should properly clear the pendingReceivers state
        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), address(0));

        // Confirm that the token balances and claimables for old contract are correct
        assertEq(0, REWARD_TRACKER_GMX.balanceOf(oldContract));
        assertEq(0, FEE_STAKED_GLP.balanceOf(oldContract));
        assertEq(0, STAKED_GMX.claimable(oldContract));
        assertEq(0, FEE_STAKED_GLP.claimable(oldContract));
        assertEq(0, REWARD_TRACKER_MP.claimable(oldContract));

        // Confirm that the staked token balances for new contract are correct
        // For Staked GMX balance, due to compounding in the migration,
        // all pending claimable esGMX and MP are automatically staked
        assertEq(
            oldStakedGmxBalance + oldEsGmxClaimable + oldMpBalance,
            REWARD_TRACKER_GMX.balanceOf(newContract)
        );
        assertEq(oldStakedGlpBalance, FEE_STAKED_GLP.balanceOf(newContract));
    }
}
