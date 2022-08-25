// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {PirexFees} from "src/PirexFees.sol";
import {PirexGmxGlp} from "src/PirexGmxGlp.sol";
import {Helper} from "./Helper.t.sol";

contract PirexFeesTest is Test, Helper {
    uint8 public constant MAX_TREASURY_PERCENT = 75;
    bytes public constant ACCESS_ERROR = "Ownable: caller is not the owner";

    event SetFeeRecipient(PirexFees.FeeRecipient f, address recipient);
    event SetTreasuryPercent(uint8 _treasuryPercent);
    event DistributeFees(address token, uint256 amount);
    event DepositGmx(
        address indexed caller,
        address indexed receiver,
        uint256 gmxAmount,
        uint256 feeAmount
    );

    /*//////////////////////////////////////////////////////////////
                        setFeeRecipient TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion if caller is not authorized
     */
    function testCannotSetFeeRecipientNotAuthorized() external {
        vm.expectRevert(ACCESS_ERROR);
        vm.prank(testAccounts[0]);
        pirexFees.setFeeRecipient(
            PirexFees.FeeRecipient.Contributors,
            address(this)
        );
    }

    /**
        @notice Test tx reversion if the recipient is the zero address
     */
    function testCannotSetFeeRecipientZeroAddress() external {
        vm.expectRevert(PirexFees.ZeroAddress.selector);
        pirexFees.setFeeRecipient(
            PirexFees.FeeRecipient.Contributors,
            address(0)
        );
    }

    /**
        @notice Test setting the fee recipient
        @param  fVal  uint8  Integer representation of the recipient enum
     */
    function testSetFeeRecipient(uint8 fVal) external {
        vm.assume(fVal <= uint8(type(PirexFees.FeeRecipient).max));

        PirexFees.FeeRecipient f = PirexFees.FeeRecipient(fVal);
        address recipient = testAccounts[0];

        vm.expectEmit(false, false, false, true);
        emit SetFeeRecipient(f, recipient);

        pirexFees.setFeeRecipient(f, recipient);
        assertEq(
            (
                f == PirexFees.FeeRecipient.Treasury
                    ? pirexFees.treasury()
                    : pirexFees.contributors()
            ),
            recipient
        );
    }

    /*//////////////////////////////////////////////////////////////
                        setTreasuryPercent TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion if caller is not authorized
     */
    function testCannotSetTreasuryPercentNotAuthorized() external {
        vm.expectRevert(ACCESS_ERROR);
        vm.prank(testAccounts[0]);
        pirexFees.setTreasuryPercent(MAX_TREASURY_PERCENT);
    }

    /**
        @notice Test tx reversion if the treasury percent is invalid
     */
    function testCannotSetTreasuryPercentInvalidFeePercent() external {
        // The percentage is invalid if > maxTreasuryPercent
        vm.expectRevert(PirexFees.InvalidFeePercent.selector);
        pirexFees.setTreasuryPercent(MAX_TREASURY_PERCENT + 1);
    }

    /**
        @notice Test setting the treasury percent
        @param  percent  uint8  Treasury percent
     */
    function testSetTreasuryPercent(uint8 percent) external {
        vm.assume(percent <= MAX_TREASURY_PERCENT);

        vm.expectEmit(false, false, false, true);
        emit SetTreasuryPercent(percent);

        pirexFees.setTreasuryPercent(percent);
        assertEq(pirexFees.treasuryPercent(), percent);
    }

    /*//////////////////////////////////////////////////////////////
                        distributeFees TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test distributing fees for the depositGmx function
        @param  depositFee  uint256  Deposit fee percent
        @param  gmxAmount   uint96   GMX amount
     */
    function testDistributeFeesDepositGmx(uint24 depositFee, uint96 gmxAmount)
        external
    {
        vm.assume(depositFee != 0);
        vm.assume(depositFee < pirexGmxGlp.FEE_MAX());
        vm.assume(gmxAmount != 0);
        vm.assume(gmxAmount < 100000e18);

        address receiver = address(this);

        pirexGmxGlp.setFee(PirexGmxGlp.Fees.Deposit, depositFee);

        assertEq(depositFee, pirexGmxGlp.fees(PirexGmxGlp.Fees.Deposit));

        uint256 feePercentDenominator = pirexFees.PERCENT_DENOMINATOR();
        uint256 treasuryPercent = pirexFees.treasuryPercent();
        uint256 expectedFeeAmount = (gmxAmount *
            pirexGmxGlp.fees(PirexGmxGlp.Fees.Deposit)) /
            pirexGmxGlp.FEE_DENOMINATOR();
        uint256 expectedMintAmount = gmxAmount - expectedFeeAmount;
        uint256 expectedFeeAmountTreasury = (expectedFeeAmount *
            treasuryPercent) / feePercentDenominator;
        uint256 expectedFeeAmountContributors = expectedFeeAmount -
            expectedFeeAmountTreasury;

        assertEq(0, pxGmx.balanceOf(receiver));
        assertEq(0, pxGmx.balanceOf(pirexFees.treasury()));
        assertEq(0, pxGmx.balanceOf(pirexFees.contributors()));

        _mintGmx(gmxAmount);
        GMX.approve(address(pirexGmxGlp), gmxAmount);

        vm.expectEmit(true, true, false, true, address(pirexGmxGlp));

        emit DepositGmx(address(this), receiver, gmxAmount, expectedFeeAmount);

        pirexGmxGlp.depositGmx(gmxAmount, receiver);

        assertEq(expectedMintAmount, pxGmx.balanceOf(receiver));
        assertEq(
            expectedFeeAmountTreasury,
            pxGmx.balanceOf(pirexFees.treasury())
        );
        assertEq(
            expectedFeeAmountContributors,
            pxGmx.balanceOf(pirexFees.contributors())
        );
        assertEq(
            expectedFeeAmountTreasury + expectedFeeAmountContributors,
            expectedFeeAmount
        );
        assertEq(expectedMintAmount + expectedFeeAmount, gmxAmount);
    }
}
