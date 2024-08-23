// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GameTokenContract is ERC20, Ownable {
    constructor(address owner) ERC20("GameToken", "GTK") Ownable(owner) {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
