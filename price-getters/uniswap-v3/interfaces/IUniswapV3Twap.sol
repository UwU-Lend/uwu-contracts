// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IUniswapV3Twap {
  // function token0() external view returns (address);
  // function token1() external view returns (address);
  function estimateAmountOut(address tokenIn, uint128 amountIn, uint32 secondsAgo) external view returns (uint amountOut, uint8 decimalsOut);
}