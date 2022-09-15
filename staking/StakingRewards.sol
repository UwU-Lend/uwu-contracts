// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakingRewards is Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint;

  IERC20 public immutable rewardToken;

  // Duration of rewards to be paid out (in seconds)
  uint public duration;
  // Timestamp of when the rewards finish
  uint public finishAt;
  // Minimum of last updated time and reward finish time
  uint public updatedAt;
  // Reward to be paid out per second
  uint public rewardRate;
  // Sum of (reward rate * dt * 1e18 / total supply)
  uint public rewardPerTokenStored;
  // User address => rewardPerTokenStored
  mapping(address => uint) public userRewardPerTokenPaid;
  // User address => rewards to be claimed
  mapping(address => uint) public rewards;

  // Total staked
  uint public totalSupply;
  // User address => staked amount
  mapping(address => uint) public balanceOf;

  address public multiFeeDistribution;
  bool public multiFeeDistributionAreSet;


  constructor (address _rewardToken) {
    rewardToken = IERC20(_rewardToken);
  }

  function lock(address who, uint _amount) external onlyMultiFeeDistribution {
    require(_amount > 0, "amount = 0");
    _updateReward(who);
    balanceOf[who] = balanceOf[who].add(_amount);
    totalSupply = totalSupply.add(_amount);
  }

  function withdraw(address who, uint _amount) external onlyMultiFeeDistribution {
    require(_amount > 0, "amount = 0");
    require(balanceOf[who] >= _amount, "balance < amount");
    _updateReward(who);
    balanceOf[who] = balanceOf[who].sub(_amount);
    totalSupply = totalSupply.sub(_amount);
  }

  function getReward() external {
    _updateReward(msg.sender);
    uint reward = rewards[msg.sender];
    if (reward > 0) {
      rewards[msg.sender] = 0;
      rewardToken.transfer(msg.sender, reward);
    }
  }

  function setRewardsDuration(uint _duration) external onlyOwner {
    require(finishAt < block.timestamp, "reward duration not finished");
    duration = _duration;
  }

  function notifyRewardAmount(uint _amount) external onlyOwner {
    _updateReward(address(0));
    if (block.timestamp >= finishAt) {
      rewardRate = _amount.div(duration);
    } else {
      uint remainingRewards = finishAt.sub(block.timestamp).mul(rewardRate);
      rewardRate = _amount.add(remainingRewards).div(duration);
    }
    require(rewardRate > 0, "reward rate = 0");
    require(
      rewardRate.mul(duration) <= rewardToken.balanceOf(address(this)),
      "reward amount > balance"
    );
    finishAt = block.timestamp.add(duration);
    updatedAt = block.timestamp;
  }

  function setMultiFeeDistribution(address _distribution) external onlyOwner {
    require(!multiFeeDistributionAreSet, 'multi fee distribution are set');
    multiFeeDistribution = _distribution;
    multiFeeDistributionAreSet = true;
  }

  function earned(address _account) public view returns (uint) {
    return balanceOf[_account]
      .mul(rewardPerToken().sub(userRewardPerTokenPaid[_account]))
      .div(1e18)
      .add(rewards[_account]);
  }

  function rewardPerToken() public view returns (uint) {
    if (totalSupply == 0) { return rewardPerTokenStored; }
    return rewardPerTokenStored.add(
      lastTimeRewardApplicable().sub(updatedAt)
      .mul(rewardRate)
      .mul(1e18)
      .div(totalSupply));
  }

  function lastTimeRewardApplicable() public view returns (uint) {
    return _min(finishAt, block.timestamp);
  }

  function _updateReward(address _account) private {
    rewardPerTokenStored = rewardPerToken();
    updatedAt = lastTimeRewardApplicable();
    if (_account != address(0)) {
      rewards[_account] = earned(_account);
      userRewardPerTokenPaid[_account] = rewardPerTokenStored;
    }
  }

  function _min(uint x, uint y) private pure returns (uint) {
    return x <= y ? x : y;
  }

  modifier onlyMultiFeeDistribution {
    require(multiFeeDistribution == msg.sender, '!multiFeeDistribution');
    _;
  }
}