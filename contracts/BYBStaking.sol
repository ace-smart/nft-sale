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
        uint256 rewardDebt;
        uint256 pendingRewards;
        uint256 depositedAt;
        uint256 claimedAt;
        uint256 unlockedAt;
    }

    IERC20 public immutable stakingToken;
    IRewarder public immutable rewarder;

    mapping(address => UserInfo) public userInfo;
    EnumerableSet.AddressSet users;
    uint256 public totalAllocPoint;

    uint256 public rewardRate;
    uint256 public unlockDuration;

    uint256 allocPoint;
    uint256 lastRewardTime;
    uint256 accEulerPerShare;
    uint256 totalSupply;
    uint256 rewardsAmount;
    uint256 lockupDuration;

    uint public startTime;
    uint public endTime;

    event Deposit(uint pid, address indexed user, uint amount);
    event Unlock(uint pid, address indexed user, uint amount);
    event Withdraw(uint pid, address indexed user, uint amount);
    event Claim(uint pid, address indexed user, uint amount);

    modifier updateReward() {
        UserInfo storage user = userInfo[msg.sender];

        if (lastRewardTime > 0 && lastRewardTime <= block.timestamp && rewardRate > 0) {
            if (totalSupply > 0) {
                uint256 multiplier = Math.min(block.timestamp, endTime).sub(lastRewardTime);
                uint256 rewards = multiplier.mul(rewardRate);
                rewardsAmount = rewardsAmount.add(rewards);
                accEulerPerShare = accEulerPerShare.add(rewards.mul(1e12).div(totalSupply));
            }
            lastRewardTime = Math.min(block.timestamp, endTime);
            
            uint256 pending = user.amount.mul(accEulerPerShare).div(1e12).sub(user.rewardDebt);
            user.pendingRewards = user.pendingRewards.add(pending);
        }

        _;
        
        if (lastRewardTime > 0 && lastRewardTime <= block.timestamp) {
            user.rewardDebt = user.amount.mul(accEulerPerShare).div(1e12);
            if (user.claimedAt == 0) user.claimedAt = block.timestamp;
        }
    }

    modifier updateUserList {
        _;
        if (userInfo[msg.sender].amount > 0) {
            _checkOrAddUser(msg.sender);
        } else {
            _removeUser(msg.sender);
        }
    }

    constructor(address _token, address _rewarder) {
        stakingToken = IERC20(_token);
        rewarder = IRewarder(_rewarder);

        lastRewardTime = block.timestamp;
        endTime = block.timestamp;

        _pause();
    }

    function userCount() external view returns (uint) {
        return users.length();
    }

    function deposit(uint256 _amount) external whenNotPaused nonReentrant updateReward updateUserList {
        require (block.timestamp < endTime, "pool already expired");
        require(_amount > 0, "!amount");
        UserInfo storage user = userInfo[msg.sender];

        uint before = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        _amount = stakingToken.balanceOf(address(this)).sub(before);

        totalSupply += _amount;
        user.amount += _amount;
        user.depositedAt = block.timestamp;
        user.unlockedAt = 0;

        emit Deposit(0, msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public nonReentrant updateReward updateUserList {
        require(_amount > 0, "!amount");
        UserInfo storage user = userInfo[msg.sender];
        require (block.timestamp.sub(user.depositedAt) > lockupDuration, "!available to withdraw");
        if (unlockDuration > 0) {
            require (user.unlockedAt > 0 && block.timestamp.sub(user.unlockedAt) > unlockDuration, "still locked");
        }
        require(user.amount >= _amount, "!balance");

        user.amount -= _amount;
        totalSupply -= _amount;
        stakingToken.safeTransfer(msg.sender, _amount);

        emit Withdraw(0, msg.sender, _amount);
    }

    function withdrawAll() external {
        UserInfo storage user = userInfo[msg.sender];
        withdraw(user.amount);
    }

    function claim() public updateReward returns (uint) {
        UserInfo storage user = userInfo[msg.sender];

        uint256 claimedAmount = rewarder.transferRewards(msg.sender, user.pendingRewards);
        user.pendingRewards = user.pendingRewards.sub(claimedAmount);
        user.claimedAt = block.timestamp;
        rewardsAmount -= claimedAmount;

        emit Claim(0, msg.sender, claimedAmount);

        return claimedAmount;
    }

    function claimable(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        if (user.amount == 0) return 0;
        
        uint256 curAccPerShare = accEulerPerShare;
        if (lastRewardTime <= block.timestamp && totalSupply > 0) {
            uint256 multiplier = Math.min(block.timestamp, endTime).sub(lastRewardTime);
            uint256 reward = multiplier.mul(rewardRate).mul(allocPoint).div(totalAllocPoint);
            curAccPerShare = accEulerPerShare.add(reward.mul(1e12).div(totalSupply));
        }
        
        return user.amount.mul(curAccPerShare).div(1e12).sub(user.rewardDebt).add(user.pendingRewards);
    }

    function setRewardRate(uint256 _rewardRate) public onlyOwner {
        require (_rewardRate > 0, "Rewards per second should be greater than 0!");
        require (endTime >= block.timestamp, "expired");

        // Update pool infos with old reward rate before setting new one first
        if (rewardRate > 0 && totalSupply > 0) {
            uint256 multiplier = block.timestamp.sub(lastRewardTime);
            uint256 reward = multiplier.mul(rewardRate);
            rewardsAmount += reward;
            accEulerPerShare += reward.mul(1e12).div(totalSupply);
            lastRewardTime = block.timestamp;
        }
        rewardRate = _rewardRate;
    }

    function setEndTime(uint _endTime) external onlyOwner {
        require (_endTime > block.timestamp, "!end time");

        if (endTime < block.timestamp && totalSupply > 0 && rewardRate > 0) {
            uint256 multiplier = block.timestamp.sub(lastRewardTime);
            uint256 reward = multiplier.mul(rewardRate);
            rewardsAmount += reward;
            accEulerPerShare += reward.mul(1e12).div(totalSupply);
            lastRewardTime = block.timestamp;
        }
        endTime = _endTime;
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