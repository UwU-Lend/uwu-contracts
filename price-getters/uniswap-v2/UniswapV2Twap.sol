//SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import {IERC20Metadata} from "./interfaces/IERC20Metadata.sol";
import {IUniswapV2Twap} from "./interfaces/IUniswapV2Twap.sol";

contract UniswapV2Twap is IUniswapV2Twap {
  using FixedPoint for *;

  uint public constant PERIOD = 10;

  IUniswapV2Pair public immutable pair;
  address public immutable token0;
  address public immutable token1;
  uint public price0CumulativeLast;
  uint public price1CumulativeLast;
  uint32 public blockTimestampLast;

  // NOTE: binary fixed point numbers
  // range: [0, 2**112 - 1]
  // resolution: 1 / 2**112
  FixedPoint.uq112x112 public price0Average;
  FixedPoint.uq112x112 public price1Average;

  address public owner;
  address public keeper;

  constructor(IUniswapV2Pair _pair) public {
    pair = _pair;
    token0 = _pair.token0();
    token1 = _pair.token1();
    price0CumulativeLast = _pair.price0CumulativeLast();
    price1CumulativeLast = _pair.price1CumulativeLast();
    (, , blockTimestampLast) = _pair.getReserves();
    owner = msg.sender;
  }

  function update() external onlyKeeper {
    (
      uint price0Cumulative,
      uint price1Cumulative,
      uint32 blockTimestamp
    ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
    uint32 timeElapsed = blockTimestamp - blockTimestampLast;

    require(timeElapsed >= PERIOD, "time elapsed < min period");

    // NOTE: overflow is desired
    /*
    |----b-------------------------a---------|
    0                                     2**256 - 1
    b - a is preserved even if b overflows
    */
    // NOTE: uint -> uint224 cuts off the bits above uint224
    // max uint
    // 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    // max uint244
    // 0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    price0Average = FixedPoint.uq112x112(
      uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
    );
    price1Average = FixedPoint.uq112x112(
      uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
    );

    price0CumulativeLast = price0Cumulative;
    price1CumulativeLast = price1Cumulative;
    blockTimestampLast = blockTimestamp;
  }

  function consult(address token, uint amountIn) external view override returns (uint amountOut, uint8 decimalsOut) {
    require(token == token0 || token == token1, "invalid token");

    if (token == token0) {
      // NOTE: using FixedPoint for *
      // NOTE: mul returns uq144x112
      // NOTE: decode144 decodes uq144x112 to uint144
      amountOut = price0Average.mul(amountIn).decode144();
      decimalsOut = IERC20Metadata(token1).decimals();
    } else {
      amountOut = price1Average.mul(amountIn).decode144();
      decimalsOut = IERC20Metadata(token0).decimals();
    }
  }

  function ownerTransfer(address newOwner) external onlyOwner {
    require(newOwner != address(0), "invalid new owner");
    owner = newOwner;
  }

  function setKeeper(address _keeper) external onlyOwner {
    keeper = _keeper;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, "not owner");
    _;
  }

  modifier onlyKeeper() {
    require(msg.sender == keeper, "only keeper");
    _;
  }
}
