// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// This contract is for demo purposes only
contract Token is ERC20 {
    constructor () ERC20("Test USDT", "TUSDT") {        
        _mint(msg.sender, 1000000000 ether); //1k Millones
    }

    function burn(uint256 amount) public virtual {
        _burn(msg.sender, amount);
    }

    function decimals() public view override returns (uint8) {
        return 6;
    }
}
