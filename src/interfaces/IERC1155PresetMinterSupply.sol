// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IERC1155PresetMinterSupply {
    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external;
}
