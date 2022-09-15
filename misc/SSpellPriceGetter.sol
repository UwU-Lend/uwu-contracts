// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPriceGetter} from "./interfaces/IPriceGetter.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

contract SSpellPriceGetter is IPriceGetter {
  using SafeMath for uint256;

  IERC20 public immutable spell;
  IERC20 public immutable sSpell;
  AggregatorV3Interface public immutable aggregator;

  constructor() {
    spell = IERC20(0x090185f2135308BaD17527004364eBcC2D37e5F6); // Abracadabra.money: SPELL Token
    sSpell = IERC20(0x26FA3fFFB6EfE8c1E69103aCb4044C26B9A106a9); // Abracadabra.money: sSPELL Token
    aggregator = AggregatorV3Interface(0x8c110B94C5f1d347fAcF5E1E938AB2db60E3c9a8); // SPELL / USD chainlink aggregator
  }

  function getPrice() external view returns (uint256 price) {
    (, int256 answer,,,) = aggregator.latestRoundData();
    price = spell.balanceOf(address(sSpell)).mul(1e8).div(sSpell.totalSupply()).mul(uint256(answer)).div(1e8);
  }
}