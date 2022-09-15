// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {IPriceGetter} from "./interfaces/IPriceGetter.sol";
import {ICurveLpContract} from "./interfaces/ICurveLpContract.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {HomoraMath} from "./utils/HomoraMath.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract CurveFairPriceGetter is IPriceGetter {
  using SafeMath for uint256;

  IERC20 private immutable crvLpToken;
  ICurveLpContract private immutable crvLpContract;
  mapping(address => AggregatorV3Interface) private tokenToAggregator;

  constructor(
    address _crvLpContract,
    address[2] memory tokens,
    address[2] memory aggregators
  ) {
    crvLpContract = ICurveLpContract(_crvLpContract);
    address token0 = crvLpContract.coins(0);
    address token1 = crvLpContract.coins(1);
    require(tokens[0] != tokens[1], "!token");
    require(tokens[0] == token0 || tokens[0] == token1, "!token");
    require(tokens[1] == token0 || tokens[1] == token1, "!token");
    require(tokens.length == aggregators.length, "!equal");
    for (uint i = 0; i < tokens.length; i++) {
      tokenToAggregator[tokens[i]] = AggregatorV3Interface(aggregators[i]);
    }
    crvLpToken = IERC20(crvLpContract.token());
  }

  function getPrice() external view returns (uint256 price) {
    address token0 = crvLpContract.coins(0); // ETH
    address token1 = crvLpContract.coins(1); // CRV
    uint256 balance0 = crvLpContract.balances(0); // 10 ** 18
    uint256 balance1 = crvLpContract.balances(1); // 10 ** 18
    (, int256 price0,,,) = tokenToAggregator[token0].latestRoundData(); // 10 ** 8
    (, int256 price1,,,) = tokenToAggregator[token1].latestRoundData(); // 10 ** 8
    uint256 K = balance0.mul(balance1);
    uint256 P = uint256(price0).mul(10 ** 10).div(uint256(price1).mul(10 ** 10));
    uint256 fp0 = HomoraMath.sqrt(K.div(P));
    uint256 fp1 = HomoraMath.sqrt(K.mul(P));
    uint256 fairPrice = (fp0.mul(uint256(price0).mul(10 ** 10)).add(fp1.mul(uint256(price1).mul(10 ** 10)))).div(crvLpToken.totalSupply());
    uint256 lpPrice = crvLpContract.lp_price().mul(uint256(price0).mul(10 ** 10)).div(10 ** 18); // 10 ** 18
    uint256 fivePercentDiff = fairPrice.div(100).mul(5); // 10 ** 18
    if (fairPrice > lpPrice) {
      if((fairPrice - lpPrice) < fivePercentDiff) {
        price = lpPrice;
      } else {
        price = fairPrice;
      }
    } else {
      if((lpPrice - fairPrice) < fivePercentDiff) {
        price = lpPrice;
      } else {
        price = fairPrice;
      }
    }
    price = price.div(10 ** 10);
  }
}