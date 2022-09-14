// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract PirexFees is Ownable {
    using SafeTransferLib for ERC20;

    // Types of fee recipients
    enum FeeRecipient {
        Treasury,
        Contributors
    }

    uint8 public constant PERCENT_DENOMINATOR = 100;

    // Configurable fee recipient percent-share
    uint8 public treasuryPercent = 75;

    // Configurable fee recipient addresses
    address public treasury;
    address public contributors;

    event SetFeeRecipient(FeeRecipient f, address recipient);
    event SetTreasuryPercent(uint8 _treasuryPercent);
    event DistributeFees(
        ERC20 indexed token,
        uint256 distribution,
        uint256 treasuryDistribution,
        uint256 contributorsDistribution
    );

    error ZeroAddress();
    error InvalidFeePercent();

    /**
        @param  _treasury      address  Redacted treasury
        @param  _contributors  address  Pirex contributor multisig
     */
    constructor(address _treasury, address _contributors) {
        if (_treasury == address(0)) revert ZeroAddress();
        if (_contributors == address(0)) revert ZeroAddress();

        treasury = _treasury;
        contributors = _contributors;
    }

    /**
        @notice Set a fee recipient address
        @param  f          enum     FeeRecipient enum
        @param  recipient  address  Fee recipient address
     */
    function setFeeRecipient(FeeRecipient f, address recipient)
        external
        onlyOwner
    {
        if (recipient == address(0)) revert ZeroAddress();

        emit SetFeeRecipient(f, recipient);

        if (f == FeeRecipient.Treasury) {
            treasury = recipient;
            return;
        }

        contributors = recipient;
    }

    /**
        @notice Set treasury fee percent
        @param  _treasuryPercent  uint8  Treasury fee percent
     */
    function setTreasuryPercent(uint8 _treasuryPercent) external onlyOwner {
        // Treasury fee percent should never exceed 75
        if (_treasuryPercent > 75) revert InvalidFeePercent();

        treasuryPercent = _treasuryPercent;

        emit SetTreasuryPercent(_treasuryPercent);
    }

    /**
        @notice Distribute fees
        @param  token  address  Fee token
     */
    function distributeFees(ERC20 token) external {
        uint256 distribution = token.balanceOf(address(this));
        uint256 treasuryDistribution = (distribution * treasuryPercent) /
            PERCENT_DENOMINATOR;
        uint256 contributorsDistribution = distribution - treasuryDistribution;

        emit DistributeFees(
            token,
            distribution,
            treasuryDistribution,
            contributorsDistribution
        );

        // Favoring push over pull to reduce accounting complexity for different tokens
        token.safeTransfer(treasury, treasuryDistribution);
        token.safeTransfer(contributors, contributorsDistribution);
    }
}
