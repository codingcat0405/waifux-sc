// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./xFish.sol";

contract FishTank is Ownable{

    IERC20 public token;
    uint256 public fishTankPrice;
    mapping(address => bool) public isUserUpgraded;
    address[] public users;

    event FishTankBought(address indexed user, address indexed token, uint256 price);
    event SetFishTankPrice(address indexed token, uint256 price);

    error AlreadyUpgraded();
    error InvalidToken();
    error BalanceNotEnough();
    error AllowanceNotEnough();

    constructor(address _token) Ownable(msg.sender) {
        token = IERC20(_token);
        fishTankPrice = 2500000 * 10**18;
    }
    // buy fish tank
    function userBuyFishTank(address _user) external {
        if(isUserUpgraded[_user]) revert AlreadyUpgraded();
        uint256 price = fishTankPrice;
        if(price == 0) revert InvalidToken();
        if(token.balanceOf(msg.sender) < price) revert BalanceNotEnough();
        if(token.allowance(msg.sender, address(this)) < price) revert AllowanceNotEnough();
        token.transferFrom(msg.sender, address(this), price);
        isUserUpgraded[_user] = true;
        users.push(_user);
        emit FishTankBought(_user, address(token), price);
    }
    // set fish tank price
    function setFishTankPrice(uint256 _price) external onlyOwner{
        fishTankPrice = _price;
        emit SetFishTankPrice(address(token), _price);
    }

    // get number of users
    function getUsersCount() external view returns(uint256){
        return users.length;
    }

    // get users
    function getUsers() external view returns(address[] memory){
        return users;
    }

    // get users with range
    function getUsersWithRange(uint256 _start, uint256 _end) external view returns(address[] memory){
        require(_end <= users.length, "Invalid range");
        address[] memory _users = new address[](_end - _start);
        for(uint256 i = _start; i < _end; i++){
            _users[i - _start] = users[i];
        }
        return _users;
    }

    // withdraw eth
    function withdrawETH(address _admin) external onlyOwner{
        payable(_admin).transfer(address(this).balance);
    }
    // withdraw token
    function withdrawTokenERC20(address _token, address _admin) external onlyOwner{
        IERC20(_token).transfer(_admin, IERC20(_token).balanceOf(address(this)));
    }
    // receive fallback
    receive() external payable{
        require(msg.value > 0, "Invalid amount");
    }
}