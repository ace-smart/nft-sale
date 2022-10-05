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
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract NFTStaking is ERC1155Holder, Ownable, Pausable, ReentrancyGuard {
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
    }

    struct NftInfo {
        uint id;
        uint weight;
    }

    // IERC20 public immutable stakingToken;
    IERC1155 public immutable nft;
    IERC20 public immutable rewardToken;

    mapping(address => UserInfo) public userInfo;
    mapping(address => mapping(uint => uint)) public userNftMap;
    EnumerableSet.AddressSet users;

    uint[] public nfts;
    mapping(uint => uint) public weightMap;

    uint256 public rewardRate;
    uint256 public claimTimes;

    uint public startTime;
    uint public endTime;
    uint public lastRewardTime;
    uint public rewardsAmount;
    uint public totalSupply;
    uint public accEulerPerShare;

    event Deposit(address indexed user, uint amount);
    event Unlock(address indexed user, uint amount);
    event Withdraw(address indexed user, uint amount);
    event Claim(address indexed user, uint amount);

    modifier updateReward {
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
        bool staked = false;
        if (userInfo[msg.sender].amount > 0) {
            _checkOrAddUser(msg.sender);
            staked = true;
        }
        if (staked == false) _removeUser(msg.sender);
    }

    constructor(address _nft, address _reward) {
        nft = IERC1155(_nft);
        rewardToken = IERC20(_reward);

        nfts.push(1);
        nfts.push(2);
        nfts.push(3);
        nfts.push(4);

        weightMap[1] = 104510 ether;
        weightMap[2] = 118142 ether;
        weightMap[3] = 127229 ether;
        weightMap[4] = 145405 ether;

        _pause();
    }

    function exists(uint _id) public view returns (bool ret) {
        return (weightMap[_id] > 0);
    }

    function addNft(uint _id, uint _weight) external onlyOwner {
        require (!exists(_id), "existing nft");
        nfts.push(_id);
        weightMap[_id] = _weight;
    }

    function updateNft(uint _id, uint _weight) external onlyOwner {
        require (exists(_id), "!existing nft");
        weightMap[_id] = _weight;
    }

    function setStartTime(uint _startTimeInMins, bool _updateAcc) external onlyOwner {
        if (totalSupply > 0 && _updateAcc && rewardRate > 0) {
            uint256 multiplier = block.timestamp.sub(lastRewardTime);
            uint256 rewards = multiplier.mul(rewardRate);
            rewardsAmount = rewardsAmount.add(rewards);
            accEulerPerShare = accEulerPerShare.add(rewards.mul(1e12).div(totalSupply));
        }
        lastRewardTime = block.timestamp.add(_startTimeInMins.mul(1 minutes));
    }

    function totalSupplyForNft() external view returns (uint) {
        uint _totalSupply;
        for (uint i = 0; i < nfts.length; i++) {
            _totalSupply += nft.balanceOf(address(this), weightMap[nfts[i]]);
        }
        return _totalSupply;
    }

    function totalSupplyForId(uint _id) external view returns (uint) {
        if (!exists(_id)) return 0;
        return nft.balanceOf(address(this), _id);

    }

    function availableRewards() public view returns (uint) {
        if (rewardToken.balanceOf(address(this)) <= rewardsAmount) return 0;
        return rewardToken.balanceOf(address(this)).sub(rewardsAmount);
    }

    function userCount() external view returns (uint) {
        return users.length();
    }

    function deposit(uint256 _id, uint256 _amount) external whenNotPaused nonReentrant updateReward updateUserList {
        require (block.timestamp < endTime, "pool already expired");
        require (exists(_id), "!exists");
        require (_amount > 0, "!amount");
        UserInfo storage user = userInfo[msg.sender];

        nft.safeTransferFrom(msg.sender, address(this), _id, _amount, "");
        uint tokenAmount = weightMap[_id].mul(_amount);

        totalSupply += tokenAmount;
        user.amount += tokenAmount;
        user.depositedAt = block.timestamp;
        userNftMap[msg.sender][_id] += _amount;

        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _id, uint256 _amount) public nonReentrant updateReward updateUserList {
        require(_amount > 0, "!amount");
        UserInfo storage user = userInfo[msg.sender];
        require(userNftMap[msg.sender][_id] >= _amount, "!balance");

        uint tokenAmount = weightMap[_id].mul(_amount);

        user.amount -= tokenAmount;
        totalSupply -= tokenAmount;
        userNftMap[msg.sender][_id] -= _amount;

        nft.safeTransferFrom(address(this), msg.sender, _id, _amount, "");

        emit Withdraw(msg.sender, _amount);
    }

    function withdrawAll() external {
        for (uint i = 0; i < nfts.length; i++) {
            if (userNftMap[msg.sender][nfts[i]] == 0) continue;
            withdraw(nfts[i], userNftMap[msg.sender][nfts[i]]);
        }
    }

    function claim() public updateReward returns (uint) {
        UserInfo storage user = userInfo[msg.sender];

        uint256 claimedAmount = safeTransferRewards(msg.sender, user.pendingRewards);
        user.pendingRewards = user.pendingRewards.sub(claimedAmount);
        user.claimedAt = block.timestamp;
        rewardsAmount -= claimedAmount;

        emit Claim(msg.sender, claimedAmount);

        return claimedAmount;
    }

    function claimable(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        if (user.amount == 0) return 0;
        
        uint256 curAccPerShare = accEulerPerShare;
        if (lastRewardTime <= block.timestamp && totalSupply > 0) {
            uint256 multiplier = Math.min(block.timestamp, endTime).sub(lastRewardTime);
            uint256 reward = multiplier.mul(rewardRate);
            curAccPerShare = accEulerPerShare.add(reward.mul(1e12).div(totalSupply));
        }
        
        return user.amount.mul(curAccPerShare).div(1e12).sub(user.rewardDebt).add(user.pendingRewards);
    }

    function safeTransferRewards(address _user, uint _amount) internal returns (uint) {
        uint curBal = rewardToken.balanceOf(address(this));
        require (curBal > 0, "!rewards");

        if (_amount > curBal) _amount = curBal;
        rewardToken.safeTransfer(_user, _amount);

        return _amount;
    }

    function setRewardRate(uint256 _rewardRate) public onlyOwner {
        require (_rewardRate > 0, "Rewards per second should be greater than 0!");

        // Update pool infos with old reward rate before setting new one first
        if (rewardRate > 0 && lastRewardTime < block.timestamp) {
            if (totalSupply > 0) {
                uint256 multiplier = block.timestamp.sub(lastRewardTime);
                uint256 reward = multiplier.mul(rewardRate);
                rewardsAmount += reward;
                accEulerPerShare += reward.mul(1e12).div(totalSupply);
            }
            lastRewardTime = block.timestamp;
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

        uint remaining = availableRewards();
        setRewardRate(remaining.div(endTime.sub(block.timestamp)));
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