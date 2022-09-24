//SPDX-License-Identifier: Unlicense
pragma solidity >0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract mocERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) public {
        _mint(msg.sender, 100000000 * 1e18);
    }
}