//SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

interface IUniswapV2Twap {
  function consult(address tokenIn, uint amountIn) external view returns (uint amountOut, uint8 decimalsOut);
}