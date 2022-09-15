// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IERC20Metadata} from "./interfaces/IERC20Metadata.sol";

contract UniswapV3Twap {
  IUniswapV3Pool public immutable pool;

  constructor(address _pool) {
    require(_pool != address(0), "!pool");
    pool = IUniswapV3Pool(_pool);
  }

  function estimateAmountOut(
    address tokenIn,
    uint128 amountIn,
    uint32 secondsAgo
  ) external view returns (uint amountOut, uint8 decimalsOut) {
    address token0 = pool.token0();
    address token1 = pool.token1();
    require(tokenIn == token0 || tokenIn == token1, "!token");
    address tokenOut = tokenIn == token0 ? token1 : token0;
    (int24 tick,) = OracleLibrary.consult(address(pool), secondsAgo);
    amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
    decimalsOut = IERC20Metadata(tokenOut).decimals();
  }
}