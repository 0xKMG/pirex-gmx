// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {UnionPirexGlpStaking} from "src/vaults/UnionPirexGlpStaking.sol";
import {PirexRewards} from "src/PirexRewards.sol";
import {PxGlp} from "src/PxGlp.sol";
import {PxGmx} from "src/PxGmx.sol";

contract UnionPirexGlpStrategy is UnionPirexGlpStaking {
    PirexRewards public immutable pirexRewards;

    ERC20 public constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    constructor(
        address _pirexRewards,
        address pxGlp,
        address pxGmx,
        address _distributor,
        address _vault
    ) UnionPirexGlpStaking(pxGlp, pxGmx, _distributor, _vault) {
        if (_pirexRewards == address(0)) revert ZeroAddress();

        pirexRewards = PirexRewards(_pirexRewards);

        afterDistributorSet(_distributor);
    }

    /**
        @notice Claim rewards from PirexGmxGlp and transfer them to the distributor
     */
    function claimRewards() external {
        // To be used for calculating actual amount of extra reward token (pxGMX)
        uint256 extraTokenBalance = ERC20(extraToken).balanceOf(address(this));

        // Claim yields from the pxGLP side
        pirexRewards.claim(ERC20(token), address(this));
        // Claim yields from the pxGMX side
        pirexRewards.claim(ERC20(extraToken), address(this));

        uint256 rewardAmount = ERC20(extraToken).balanceOf(address(this)) -
            extraTokenBalance;

        if (rewardAmount != 0) {
            _notifyExtraReward(rewardAmount);
        }
    }

    /**
        @notice Set distributor as the reward recipient (only for WETH rewards)
        @notice For pxGMX rewards, it can be directly handled by the contract itself
     */
    function afterDistributorSet(address _distributor) internal override {
        // WETH from pxGLP
        pirexRewards.setRewardRecipient(ERC20(token), WETH, _distributor);

        // WETH from pxGMX
        pirexRewards.setRewardRecipient(ERC20(extraToken), WETH, _distributor);
    }
}
