// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract xFish is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 3_000_000_000 * 10 ** 18;
    constructor() ERC20("xFish","xFi") Ownable(msg.sender) {
        uint256 initSupply = 3_000_000_000 * 10 ** 18;
        _mint(msg.sender, initSupply);
    }
    // mint more token but not exceed max supply
    function mint(address to, uint256 amount) public onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Max supply reached");
        _mint(to, amount);
    }
}