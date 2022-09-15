// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStakingRewards {
  function lock(address who, uint _amount) external;
  function withdraw(address who, uint _amount) external;
}