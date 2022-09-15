// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICurveLpContract {
  function token() external view returns(address);
  function coins(uint256 index) external view returns(address);
  function balances(uint256 index) external view returns(uint256);
  function lp_price() external view returns(uint256);
}