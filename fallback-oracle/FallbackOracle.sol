// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracleGetter} from "./interfaces/IPriceOracleGetter.sol";
import {IPriceGetter} from "./interfaces/IPriceGetter.sol";

contract FallbackOracle is IPriceOracleGetter, Ownable {
  mapping (address => IPriceGetter) private assetToPriceGetter;

  constructor(address[] memory assets, address[] memory getters) {
    _setAssetPriceGetterBatch(assets, getters);
  }

  function getAssetPrice(address asset) external view returns (uint256) {
    require(address(assetToPriceGetter[asset]) != address(0), '!exists');
    return assetToPriceGetter[asset].getPrice();
  }

  function setAssetPriceGetter(address asset, address getter) external onlyOwner {
    assetToPriceGetter[asset] = IPriceGetter(getter);
  }

  function setAssetPriceGetterBatch(address[] calldata assets, address[] calldata getters) external onlyOwner {
    _setAssetPriceGetterBatch(assets, getters);
  }

  function _setAssetPriceGetterBatch(address[] memory assets, address[] memory getters) internal {
    require(assets.length == getters.length, '!equal');
    for (uint i = 0; i < assets.length; i++) {
      assetToPriceGetter[assets[i]] = IPriceGetter(getters[i]);
    }
  }
}