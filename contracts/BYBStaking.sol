//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IRewarder {
    function transferRewards(address _to, uint _amount) external returns (uint);
}

contract BYBStaking is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint256 amount;
        uint256 shares;
        uint256 rewardDebt;
        uint256 pendingRewards;
        uint256 depositedAt;
        uint256 claimedAt;
        uint256 unlockedAt;
    }

    struct PoolInfo {
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 accEulerPerShare;
        uint256 totalSupply;
        uint256 rewardsAmount;
        uint256 lockupDuration;
    }

    IERC20 public immutable stakingToken;
    IRewarder public immutable rewarder;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    EnumerableSet.AddressSet users;
    uint256 public totalAllocPoint;

    uint256 public rewardRate;
    uint256 public unlockDuration;
    uint256 public claimTimes;

    uint public startTime;
    uint public endTime;

    event Deposit(uint pid, address indexed user, uint amount);
    event Unlock(uint pid, address indexed user, uint amount);
    event Withdraw(uint pid, address indexed user, uint amount);
    event Claim(uint pid, address indexed user, uint amount);

    modifier updateReward(uint pid) {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        if (pool.lastRewardTime > 0 && pool.lastRewardTime <= block.timestamp && rewardRate > 0) {
            if (pool.totalSupply > 0) {
                uint256 multiplier = Math.min(block.timestamp, endTime).sub(pool.lastRewardTime);
                uint256 rewards = multiplier.mul(rewardRate).mul(pool.allocPoint).div(totalAllocPoint);
                pool.rewardsAmount = pool.rewardsAmount.add(rewards);
                pool.accEulerPerShare = pool.accEulerPerShare.add(rewards.mul(1e12).div(pool.totalSupply));
            }
            pool.lastRewardTime = Math.min(block.timestamp, endTime);
            
            uint256 pending = user.amount.mul(pool.accEulerPerShare).div(1e12).sub(user.rewardDebt);
            user.pendingRewards = user.pendingRewards.add(pending);
        }

        _;
        
        if (pool.lastRewardTime > 0 && pool.lastRewardTime <= block.timestamp) {
            user.rewardDebt = user.amount.mul(pool.accEulerPerShare).div(1e12);
            if (user.claimedAt == 0) user.claimedAt = block.timestamp;
        }
    }

    modifier updateUserList {
        _;
        bool staked = false;
        for (uint i = 0; i < poolInfo.length; i++) {
            if (userInfo[i][msg.sender].amount > 0) {
                _checkOrAddUser(msg.sender);
                staked = true;
                break;
            }
        }
        if (staked == false) _removeUser(msg.sender);
    }

    constructor(address _token, address _rewarder) {
        stakingToken = IERC20(_token);
        rewarder = IRewarder(_rewarder);

        addPool(1, 0, 0);

        _pause();
    }

    function addPool(uint256 _allocPoint, uint256 _lockupDuration, uint256 _startTime) public onlyOwner {
        require (_startTime == 0 || _startTime >= block.timestamp, "!start time");

        poolInfo.push(
            PoolInfo({
                allocPoint: _allocPoint,
                lastRewardTime: _startTime,
                accEulerPerShare: 0,
                totalSupply: 0,
                rewardsAmount: 0,
                lockupDuration: _lockupDuration
            })
        );

        totalAllocPoint += _allocPoint;
    }

    function setPool(uint _pid, uint _allocPoint, uint _lockupDuration) external onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        totalAllocPoint = totalAllocPoint - pool.allocPoint + _allocPoint;
        pool.lockupDuration = _lockupDuration;
        pool.allocPoint = _allocPoint;
    }

    function setStartTime(uint _pid, uint _startTimeInMins, bool _updateAcc) external onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];

        if (pool.totalSupply > 0 && _updateAcc && rewardRate > 0) {
            uint256 multiplier = block.timestamp.sub(pool.lastRewardTime);
            uint256 rewards = multiplier.mul(rewardRate).mul(pool.allocPoint).div(totalAllocPoint);
            pool.rewardsAmount = pool.rewardsAmount.add(rewards);
            pool.accEulerPerShare = pool.accEulerPerShare.add(rewards.mul(1e12).div(pool.totalSupply));
        }
        pool.lastRewardTime = block.timestamp.add(_startTimeInMins.mul(1 minutes));
    }

    function totalSupply() external view returns (uint) {
        uint _totalSupply;
        for (uint i = 0; i < poolInfo.length; i++) {
            _totalSupply += poolInfo[i].totalSupply;
        }
        return _totalSupply;
    }

    function getPoolCount() external view returns (uint) {
        return poolInfo.length;
    }

    function userCount() external view returns (uint) {
        return users.length();
    }

    function deposit(uint256 _amount) external whenNotPaused nonReentrant updateReward(0) updateUserList {
        require (block.timestamp < endTime, "pool already expired");
        require(_amount > 0, "!amount");
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];

        uint before = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        _amount = stakingToken.balanceOf(address(this)).sub(before);

        pool.totalSupply += _amount;
        user.amount += _amount;
        user.depositedAt = block.timestamp;
        user.unlockedAt = 0;

        emit Deposit(0, msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public nonReentrant updateReward(0) updateUserList {
        require(_amount > 0, "!amount");
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require (block.timestamp.sub(user.depositedAt) > pool.lockupDuration, "!available to withdraw");
        if (unlockDuration > 0) {
            require (user.unlockedAt > 0 && block.timestamp.sub(user.unlockedAt) > unlockDuration, "still locked");
        }
        require(user.amount >= _amount, "!balance");

        user.amount -= _amount;
        pool.totalSupply -= _amount;
        stakingToken.safeTransfer(msg.sender, _amount);

        emit Withdraw(0, msg.sender, _amount);
    }

    function withdrawAll() external {
        UserInfo storage user = userInfo[0][msg.sender];
        withdraw(user.amount);
    }

    function claim() public updateReward(0) returns (uint) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];

        uint256 claimedAmount = rewarder.transferRewards(msg.sender, user.pendingRewards);
        user.pendingRewards = user.pendingRewards.sub(claimedAmount);
        user.claimedAt = block.timestamp;
        pool.rewardsAmount -= claimedAmount;

        emit Claim(0, msg.sender, claimedAmount);

        return claimedAmount;
    }

    function claimable(address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][_user];
        if (user.amount == 0) return 0;
        
        uint256 curAccPerShare = pool.accEulerPerShare;
        if (pool.lastRewardTime <= block.timestamp && pool.totalSupply > 0) {
            uint256 multiplier = Math.min(block.timestamp, endTime).sub(pool.lastRewardTime);
            uint256 reward = multiplier.mul(rewardRate).mul(pool.allocPoint).div(totalAllocPoint);
            curAccPerShare = pool.accEulerPerShare.add(reward.mul(1e12).div(pool.totalSupply));
        }
        
        return user.amount.mul(curAccPerShare).div(1e12).sub(user.rewardDebt).add(user.pendingRewards);
    }

    function setRewardRate(uint256 _rewardRate) public onlyOwner {
        require (_rewardRate > 0, "Rewards per second should be greater than 0!");

        // Update pool infos with old reward rate before setting new one first
        if (rewardRate > 0) {
            PoolInfo storage pool = poolInfo[0];
            if (pool.lastRewardTime >= block.timestamp) revert ("expired");

            if (pool.totalSupply > 0) {
                uint256 multiplier = block.timestamp.sub(pool.lastRewardTime);
                uint256 reward = multiplier.mul(rewardRate).mul(pool.allocPoint).div(totalAllocPoint);
                pool.rewardsAmount += reward;
                pool.accEulerPerShare += reward.mul(1e12).div(pool.totalSupply);
            }
            pool.lastRewardTime = block.timestamp;
        }
        rewardRate = _rewardRate;
    }

    function expandEndTime(uint _mins) external onlyOwner {
        require (_mins > 0, "!period");

        if (endTime >= block.timestamp) {
            endTime += _mins.mul(1 minutes);
        } else {
            endTime = block.timestamp + _mins.mul(1 minutes);
        }
    }

    function _removeUser(address _user) internal {
        if (users.contains(_user) == true) {
            users.remove(_user);
        }
    }

    function _checkOrAddUser(address _user) internal {
        if (users.contains(_user) == false) {
            users.add(_user);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}