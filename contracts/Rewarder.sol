//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract Rewarder is Ownable, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant POOL_ROLE = keccak256("POOL_ROLE");

    modifier onlyPool {
        require (hasRole(POOL_ROLE, msg.sender) || msg.sender == owner(), "!pool");
        _;
    }
    
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(POOL_ROLE, msg.sender);
    }

    function transferRewards(address _to, uint _amount) external nonReentrant onlyPool returns (uint) {
        uint256 bal = address(this).balance;
        require (bal > 0, "!rewards");
        if (_amount > bal) _amount = bal;

        payable(_to).call{
            value: _amount,
            gas: 30000
        }("");
        
        return _amount;
    }

    function withdraw(uint _amount) external onlyOwner {
        uint256 bal = address(this).balance;
        require (bal > 0, "!rewards");
        if (_amount > bal) _amount = bal;

        payable(msg.sender).call{
            value: _amount,
            gas: 30000
        }("");
    }

    function setPool(address _pool, bool _flag) external onlyOwner {
        _flag ? grantRole(POOL_ROLE, _pool) : revokeRole(POOL_ROLE, _pool);
    }

    receive() external payable {}
}