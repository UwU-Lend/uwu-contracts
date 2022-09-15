//SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

import {FullMath} from './libraries/FullMath.sol';
import {IERC20Metadata} from "./interfaces/IERC20Metadata.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IUniswapV2Twap} from "./interfaces/IUniswapV2Twap.sol";
import {IPriceGetter} from "./interfaces/IPriceGetter.sol";

contract UniswapV2Oracle is IPriceGetter {
  IERC20Metadata public immutable token;
  IUniswapV2Twap public immutable twap;
  AggregatorV3Interface public immutable aggregator;

  constructor(IERC20Metadata _token, IUniswapV2Twap _twap, AggregatorV3Interface _aggregator) public {
    twap = _twap;
    token = _token;
    aggregator = _aggregator;
  }

  function getPrice() external view override returns (uint256 price) {
    (uint amountOut, uint8 decimalsOut) = twap.consult(address(token), 10 ** uint256(token.decimals()));
    (, int256 answer,,,) = aggregator.latestRoundData();
    price = FullMath.mulDiv(amountOut, uint256(answer), 10 ** uint256(decimalsOut));
  }
}