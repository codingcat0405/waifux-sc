//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

contract WBNBMock is ERC20("Wrapped BNB", "WBNB") {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
