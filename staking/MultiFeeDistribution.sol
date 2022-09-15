// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IStakingRewards.sol";
import "./interfaces/IMultiFeeDistribution.sol";
import "./interfaces/IChefIncentivesController.sol";

contract MultiFeeDistribution is IMultiFeeDistribution, Ownable {
  using SafeMath for uint;
  using SafeERC20 for IERC20;

  event Locked(address indexed user, uint amount);
  event WithdrawnExpiredLocks(address indexed user, uint amount);
  event Minted(address indexed user, uint amount);
  event ExitedEarly(address indexed user, uint amount, uint penaltyAmount);
  event Withdrawn(address indexed user, uint amount);
  event RewardPaid(address indexed user, address indexed rewardsToken, uint reward);

  struct Reward {
    uint periodFinish;
    uint rewardRate;
    uint lastUpdateTime;
    uint rewardPerTokenStored;
    uint balance;
  }
  struct Balances {
    uint locked; // balance lock tokens
    uint earned; // balance reward tokens earned
  }
  struct LockedBalance {
    uint amount;
    uint unlockTime;
  }
  struct RewardData {
    address token;
    uint amount;
  }

  uint public constant rewardsDuration = 86400 * 7; // reward interval 7 days;
  uint public constant rewardLookback = 86400;
  uint public constant lockDuration = rewardsDuration * 8; // 56 days
  uint public constant vestingDuration = rewardsDuration * 4; // 28 days

  // Addresses approved to call mint
  mapping(address => bool) public minters;
  bool public mintersAreSet;

  // user -> reward token -> amount
  mapping(address => mapping(address => uint)) public userRewardPerTokenPaid;
  mapping(address => mapping(address => uint)) public rewards;

  IChefIncentivesController public incentivesController;
  IERC20 public immutable stakingToken;
  IERC20 public immutable rewardToken;
  address public immutable rewardTokenVault;
  address public teamRewardVault;
  uint public teamRewardFee = 2000; // 1% = 100
  IStakingRewards public stakingRewards;
  bool public stakingRewardsAreSet;
  address[] public rewardTokens;
  mapping(address => Reward) public rewardData;

  uint public lockedSupply;

  // Private mappings for balance data
  mapping(address => Balances) private balances;
  mapping(address => LockedBalance[]) private userLocks; // stake UwU-ETH LP tokens
  mapping(address => LockedBalance[]) private userEarnings; // vesting UwU tokens

  mapping(address => address) public exitDelegatee;

  constructor(address _stakingToken, address _rewardToken, address _rewardTokenVault) Ownable() {
    stakingToken = IERC20(_stakingToken);
    rewardToken = IERC20(_rewardToken);
    rewardTokenVault = _rewardTokenVault;
    rewardTokens.push(_rewardToken);
    rewardData[_rewardToken].lastUpdateTime = block.timestamp;
  }

  function setTeamRewardVault(address vault) external onlyOwner {
    require(vault != address(0), "address zero");
    teamRewardVault = vault;
  }

  function setTeamRewardFee(uint fee) external onlyOwner {
    require(fee <= 10000, "fee too high");
    teamRewardFee = fee;
  }

  function setStakingRewards(address _stakingRewards) external onlyOwner {
    require(!stakingRewardsAreSet, 'stakingRewards already set');
    stakingRewards = IStakingRewards(_stakingRewards);
    stakingRewardsAreSet = true;
  }

  function setMinters(address[] memory _minters) external onlyOwner {
    require(!mintersAreSet, 'minter already set');
    for (uint i; i < _minters.length; i++) {
      minters[_minters[i]] = true;
    }
    mintersAreSet = true;
  }

  function setIncentivesController(IChefIncentivesController _controller) external onlyOwner {
    incentivesController = _controller;
  }

   // Add a new reward token to be distributed to stakers
  function addReward(address _rewardsToken) external onlyOwner {
    require(rewardData[_rewardsToken].lastUpdateTime == 0);
    rewardTokens.push(_rewardsToken);
    rewardData[_rewardsToken].lastUpdateTime = block.timestamp;
    rewardData[_rewardsToken].periodFinish = block.timestamp;
  }

  // Information on a user's locked balances
  function lockedBalances(address user) view external returns (
    uint total,
    uint unlockable,
    uint locked,
    LockedBalance[] memory lockData
  ) {
    LockedBalance[] storage locks = userLocks[user];
    uint idx;
    for (uint i = 0; i < locks.length; i++) {
      if (locks[i].unlockTime > block.timestamp) {
        if (idx == 0) {
          lockData = new LockedBalance[](locks.length - i);
        }
        lockData[idx] = locks[i];
        idx++;
        locked = locked.add(locks[i].amount);
      } else {
        unlockable = unlockable.add(locks[i].amount);
      }
    }
    return (balances[user].locked, unlockable, locked, lockData);
  }

  // Information on the "earned" balances of a user
  function earnedBalances(address user) view external returns (uint total, LockedBalance[] memory earningsData) {
    LockedBalance[] storage earnings = userEarnings[user];
    uint idx;
    for (uint i = 0; i < earnings.length; i++) {
      if (earnings[i].unlockTime > block.timestamp) {
        if (idx == 0) {
          earningsData = new LockedBalance[](earnings.length - i);
        }
        earningsData[idx] = earnings[i];
        idx++;
        total = total.add(earnings[i].amount);
      }
    }
    return (total, earningsData);
  }

  function withdrawableBalance(address user) view public returns (
    uint amount,
    uint penaltyAmount,
    uint amountWithoutPenalty
  ) {
    Balances storage bal = balances[user];
    uint earned = bal.earned;
    if (earned > 0) {
      uint length = userEarnings[user].length;
      for (uint i = 0; i < length; i++) {
        uint earnedAmount = userEarnings[user][i].amount;
        if (earnedAmount == 0) continue;
        if (userEarnings[user][i].unlockTime > block.timestamp) {
          break;
        }
        amountWithoutPenalty = amountWithoutPenalty.add(earnedAmount);
      }
      penaltyAmount = earned.sub(amountWithoutPenalty).div(2);
    }
    amount = earned.sub(penaltyAmount);
    // return (amount, penaltyAmount);
  }

  // Address and claimable amount of all reward tokens for the given account
  function claimableRewards(address account) external view returns (RewardData[] memory rewards) {
    rewards = new RewardData[](rewardTokens.length);
    for (uint i = 0; i < rewards.length; i++) {
      rewards[i].token = rewardTokens[i];
      rewards[i].amount = _earned(account, rewards[i].token, balances[account].locked, _rewardPerToken(rewardTokens[i], lockedSupply)).div(1e12);
    }
    return rewards;
  }

  // Lock tokens to receive rewards
  // Locked tokens cannot be withdrawn for lockDuration and are eligible to receive stakingReward rewards
  function lock(uint amount, address onBehalfOf) external {
    require(amount > 0, "amount = 0");
    _updateReward(onBehalfOf);
    Balances storage bal = balances[onBehalfOf];
    lockedSupply = lockedSupply.add(amount);
    bal.locked = bal.locked.add(amount);
    uint unlockTime = block.timestamp.div(rewardsDuration).mul(rewardsDuration).add(lockDuration);
    uint idx = userLocks[onBehalfOf].length;
    if (idx == 0 || userLocks[onBehalfOf][idx-1].unlockTime < unlockTime) {
      userLocks[onBehalfOf].push(LockedBalance({amount: amount, unlockTime: unlockTime}));
    } else {
      userLocks[onBehalfOf][idx-1].amount = userLocks[onBehalfOf][idx-1].amount.add(amount);
    }
    stakingToken.safeTransferFrom(msg.sender, address(this), amount);
    emit Locked(onBehalfOf, amount);
    if (address(stakingRewards) != address(0)) {
      stakingRewards.lock(onBehalfOf, amount);
    }
  }

  // Withdraw all currently locked tokens where the unlock time has passed
  function withdrawExpiredLocks() external {
    _updateReward(msg.sender);
    LockedBalance[] storage locks = userLocks[msg.sender];
    Balances storage bal = balances[msg.sender];
    uint amount;
    uint length = locks.length;
    if (locks[length-1].unlockTime <= block.timestamp) {
      amount = bal.locked;
      delete userLocks[msg.sender];
    } else {
      for (uint i = 0; i < length; i++) {
        if (locks[i].unlockTime > block.timestamp) break;
        amount = amount.add(locks[i].amount);
        delete locks[i];
      }
    }
    require(amount > 0, 'amount = 0');
    bal.locked = bal.locked.sub(amount);
    lockedSupply = lockedSupply.sub(amount);
    stakingToken.safeTransfer(msg.sender, amount);
    emit WithdrawnExpiredLocks(msg.sender, amount);
    if (address(stakingRewards) != address(0)) {
      stakingRewards.withdraw(msg.sender, amount);
    }
  }

  function mint(address user, uint amount) external {
    require(minters[msg.sender], '!minter');
    if (amount == 0) return;
    _updateReward(user);
    rewardToken.safeTransferFrom(rewardTokenVault, address(this), amount);
    if (user == address(this)) {
      // minting to this contract adds the new tokens as incentives for lockers
      _notifyReward(address(rewardToken), amount);
      return;
    }
    Balances storage bal = balances[user];
    bal.earned = bal.earned.add(amount);
    uint unlockTime = block.timestamp.div(rewardsDuration).mul(rewardsDuration).add(vestingDuration);
    LockedBalance[] storage earnings = userEarnings[user];
    uint idx = earnings.length;
    if (idx == 0 || earnings[idx-1].unlockTime < unlockTime) {
      earnings.push(LockedBalance({amount: amount, unlockTime: unlockTime}));
    } else {
      earnings[idx-1].amount = earnings[idx-1].amount.add(amount);
    }
    emit Minted(user, amount);
  }

  // Delegate exit
  function delegateExit(address delegatee) external {
    exitDelegatee[msg.sender] = delegatee;
  }

  // Withdraw full unlocked balance and optionally claim pending rewards
  function exitEarly(address onBehalfOf) external {
    require(onBehalfOf == msg.sender || exitDelegatee[onBehalfOf] == msg.sender);
    _updateReward(onBehalfOf);
    (uint amount, uint penaltyAmount,) = withdrawableBalance(onBehalfOf);
    delete userEarnings[onBehalfOf];
    Balances storage bal = balances[onBehalfOf];
    bal.earned = 0;
    rewardToken.safeTransfer(onBehalfOf, amount);
    if (penaltyAmount > 0) {
      incentivesController.claim(address(this), new address[](0));
      _notifyReward(address(rewardToken), penaltyAmount);
    }
    emit ExitedEarly(onBehalfOf, amount, penaltyAmount);
  }

  // Withdraw staked tokens
  function withdraw() public {
    _updateReward(msg.sender);
    Balances storage bal = balances[msg.sender];
    uint earned = bal.earned;
    uint amount;
    if (earned > 0) {
      uint length = userEarnings[msg.sender].length;
      for (uint i = 0; i < length; i++) {
        uint earnedAmount = userEarnings[msg.sender][i].amount;
        if (earnedAmount == 0) continue;
        if (userEarnings[msg.sender][i].unlockTime > block.timestamp) {
          break;
        }
        amount = amount.add(earnedAmount);
        delete userEarnings[msg.sender][i];
      }
      if (userEarnings[msg.sender].length == 0) {
        delete userEarnings[msg.sender];
      }
    }
    if (amount > 0) {
      rewardToken.safeTransfer(msg.sender, amount);
      emit Withdrawn(msg.sender, amount);
    }
  }

  // Transfer rewards to wallet
  function getReward(address[] memory _rewardTokens) public {
    _updateReward(msg.sender);
    _getReward(_rewardTokens);
  }

  function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint) {
    uint periodFinish = rewardData[_rewardsToken].periodFinish;
    return block.timestamp < periodFinish ? block.timestamp : periodFinish;
  }

  function _getReward(address[] memory _rewardTokens) internal {
    uint length = _rewardTokens.length;
    for (uint i; i < length; i++) {
      address token = _rewardTokens[i];
      uint reward = rewards[msg.sender][token].div(1e12);
      if (token != address(rewardToken)) {
        // for rewards other than rewardToken, every 24 hours we check if new
        // rewards were sent to the contract or accrued via uToken interest
        Reward storage r = rewardData[token];
        uint periodFinish = r.periodFinish;
        require(periodFinish > 0, "Unknown reward token");
        uint balance = r.balance;
        if (periodFinish < block.timestamp.add(rewardsDuration - rewardLookback)) {
          uint unseen = IERC20(token).balanceOf(address(this)).sub(balance);
          if (unseen > 0) {
            _notifyReward(token, unseen);
            balance = balance.add(unseen);
          }
        }
        r.balance = balance.sub(reward);
      }
      if (reward == 0) continue;
      rewards[msg.sender][token] = 0;
      IERC20(token).safeTransfer(msg.sender, reward);
      emit RewardPaid(msg.sender, token, reward);
    }
  }

  function _rewardPerToken(address _rewardsToken, uint _supply) internal view returns (uint) {
    if (_supply == 0) {
      return rewardData[_rewardsToken].rewardPerTokenStored;
    }
    return rewardData[_rewardsToken].rewardPerTokenStored.add(
      lastTimeRewardApplicable(_rewardsToken)
      .sub(rewardData[_rewardsToken].lastUpdateTime)
      .mul(rewardData[_rewardsToken].rewardRate)
      .mul(1e18).div(_supply)
    );
  }

  function _earned(
    address _user,
    address _rewardsToken,
    uint _balance,
    uint _currentRewardPerToken
  ) internal view returns (uint) {
    return _balance.mul(
      _currentRewardPerToken.sub(userRewardPerTokenPaid[_user][_rewardsToken])
    ).div(1e18).add(rewards[_user][_rewardsToken]);
  }

  function _notifyReward(address _rewardsToken, uint _reward) internal {
    uint reward = _adjustReward(_rewardsToken, _reward);
    Reward storage r = rewardData[_rewardsToken];
    if (block.timestamp >= r.periodFinish) {
      r.rewardRate = reward.mul(1e12).div(rewardsDuration);
    } else {
      uint remaining = r.periodFinish.sub(block.timestamp);
      uint leftover = remaining.mul(r.rewardRate).div(1e12);
      r.rewardRate = reward.add(leftover).mul(1e12).div(rewardsDuration);
    }
    r.lastUpdateTime = block.timestamp;
    r.periodFinish = block.timestamp.add(rewardsDuration);
  }

  function _updateReward(address account) internal {
    uint length = rewardTokens.length;
    for (uint i = 0; i < length; i++) {
      address token = rewardTokens[i];
      Reward storage r = rewardData[token];
      uint rpt = _rewardPerToken(token, lockedSupply);
      r.rewardPerTokenStored = rpt;
      r.lastUpdateTime = lastTimeRewardApplicable(token);
      if (account != address(this)) {
        rewards[account][token] = _earned(account, token, balances[account].locked, rpt);
        userRewardPerTokenPaid[account][token] = rpt;
      }
    }
  }

  function _adjustReward(address _rewardsToken, uint reward) internal returns (uint adjustedAmount) {
    if (reward > 0 && teamRewardVault != address(0) && _rewardsToken != address(rewardToken)) {
      uint fee = reward.div(10000).mul(teamRewardFee);
      adjustedAmount = reward.sub(fee);
      IERC20(_rewardsToken).safeTransfer(teamRewardVault, fee);
    } else {
      adjustedAmount = reward;
    }
  }
}