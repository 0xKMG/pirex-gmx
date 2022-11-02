// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IV3SwapRouter} from "src/interfaces/IV3SwapRouter.sol";
import {IWETH} from "src/interfaces/IWETH.sol";

contract UniswapETHToGMX {
    using SafeTransferLib for ERC20;

    IV3SwapRouter public constant SWAP_ROUTER =
        IV3SwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    IWETH public constant WETH =
        IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    ERC20 public constant GMX =
        ERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);

    constructor() {
        // Approve the Uniswap V3 router to manage our base reward (inbound swap token)
        ERC20(address(WETH)).safeApprove(
            address(SWAP_ROUTER),
            type(uint256).max
        );
    }

    function swap() external payable {
        // Deposit value for WETH
        WETH.deposit{value: msg.value}();

        SWAP_ROUTER.exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: address(GMX),
                fee: 3000,
                recipient: msg.sender,
                amountIn: ERC20(address(WETH)).balanceOf(address(this)),
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            })
        );
    }
}
