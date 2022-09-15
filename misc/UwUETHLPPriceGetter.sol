// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {IERC20} from "./interfaces/IERC20.sol";
import {IPriceGetter} from "./interfaces/IPriceGetter.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

contract UwUETHLPPriceGetter {
  using SafeMath for uint256;

  IERC20 public immutable token;
  IERC20 public immutable pool;
  AggregatorV3Interface public immutable aggregator;

  constructor(address _token, address _pool, address _aggregator) {
    token = IERC20(_token);
    pool = IERC20(_pool);
    aggregator = AggregatorV3Interface(_aggregator);
  }

  function getPrice() external view returns (uint256 price) {
    (, int256 answer,,,) = aggregator.latestRoundData();
    price = token.balanceOf(address(pool)).mul(2).mul(uint256(answer)).div(pool.totalSupply());
  }
}