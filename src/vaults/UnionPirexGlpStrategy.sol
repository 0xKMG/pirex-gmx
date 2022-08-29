// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {UnionPirexGlpStaking} from "src/vaults/UnionPirexGlpStaking.sol";
import {PirexRewards} from "src/PirexRewards.sol";
import {PxGlp} from "src/PxGlp.sol";
import {PxGmx} from "src/PxGmx.sol";

contract UnionPirexGlpStrategy is UnionPirexGlpStaking {
    PirexRewards public immutable pirexRewards;

    error ZeroAddress();

    constructor(
        address _pirexRewards,
        address pxGlp,
        address _distributor,
        address _vault
    ) UnionPirexGlpStaking(pxGlp, _distributor, _vault) {
        if (_pirexRewards == address(0)) revert ZeroAddress();

        pirexRewards = PirexRewards(_pirexRewards);
    }

    function setRewardRecipient(ERC20 producerToken, ERC20 rewardToken)
        external
        onlyOwner
    {
        pirexRewards.setRewardRecipient(
            producerToken,
            rewardToken,
            distributor
        );
    }

    /**
        @notice Claim rewards from PirexGmxGlp and transfer them to the distributor
     */
    function claimRewards() external {
        pirexRewards.claim(token, address(this));
    }
}
