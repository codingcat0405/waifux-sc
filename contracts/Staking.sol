// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Staking is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    // struct of user information for staking
    struct StakerInfo {
        address stakerAddr;
        uint256 amount;
        uint256 stakeTime;
        uint256 dividendClaimed;
    }

    IERC20 public token;
    mapping(address => StakerInfo) public stakerInfo;
    mapping(uint256 => bool) public isDividendPaid;
    mapping(uint256 => mapping(address => bool)) public isDividendClaimed; // dividend claimed status for each dividend round
    mapping(uint256 => mapping(address => uint256)) public userDividendClaimed;
    EnumerableSet.AddressSet private stakers;
    uint256 public totalStakedAmount;
    uint256 public timeLock; // time lock for unstake

    event Stake(address indexed staker, uint256 indexed amount, uint256 stakeTime);
    event Unstake(address indexed staker, uint256 indexed amount, uint256 stakeTime);
    event DividendPaid(uint256 indexed amount, uint256 dividendTime);


    error InvalidAmount(uint256 amount);
    error InvalidTransfer(address from, address to, uint256 amount);
    error InvalidStaker(address staker);
    error InvalidDividend(uint256 round);
    error InvalidRound(uint256 round);
    error NoStaker();
    error InvalidUnstakeTime(uint256 unstakeTime);
    error ZeroBalance();

    constructor(address _token) Ownable(msg.sender){
        token = IERC20(_token);
        timeLock = 7 days;
    }

    /**
     * @dev Stake tokens to earn dividends
     * @param stakeAmount amount of tokens to stake
     */
    function stakeToken(uint256 stakeAmount) public nonReentrant {
        if(stakeAmount == 0) revert InvalidAmount(stakeAmount);
        StakerInfo memory staker = stakerInfo[msg.sender];
        // transfer token to the pool
        if(!token.transferFrom(msg.sender, address(this), stakeAmount)) revert InvalidTransfer(msg.sender, address(this), stakeAmount);
        // record staker info at first time
        if(staker.amount == 0){
            stakers.add(msg.sender);
            staker.stakerAddr = msg.sender;
            staker.stakeTime = block.timestamp;
        }
        staker.amount += stakeAmount;
        totalStakedAmount += stakeAmount;
        stakerInfo[msg.sender] = staker;
        emit Stake(msg.sender, stakeAmount, block.timestamp);
    }
    /**
     * @dev unstake tokens from the pool
     */
    function unStakeToken() public nonReentrant{
        uint256 stakedAmount = stakerInfo[msg.sender].amount;
        if(stakedAmount == 0) revert InvalidStaker(msg.sender);
        // check time lock
        if(block.timestamp < stakerInfo[msg.sender].stakeTime + timeLock) revert InvalidUnstakeTime(block.timestamp);
        totalStakedAmount -= stakedAmount;
        delete stakerInfo[msg.sender];
        stakers.remove(msg.sender);
        // transfer token to the staker
        if(!token.transfer(msg.sender, stakedAmount)) revert InvalidTransfer(address(this), msg.sender, stakedAmount);
        emit Unstake(msg.sender, stakedAmount, block.timestamp);
    }

    /**
    * @dev transfer dividends to all stakers
     */
    function payDividendsForAll(uint256 _round, uint256 _dividendReward) public onlyOwner {
        address[] memory _stakers = getStakers();
        _payDividends(_round, _stakers, _dividendReward, totalStakedAmount);
        emit DividendPaid(_dividendReward, block.timestamp);
    }

    /**
     * @dev transfer dividend to specific stakers
     */
    function payDividendsForStakers(uint256 _round, address[] memory _stakers, uint256 _dividendReward,uint256 _totalStakedAmount) public onlyOwner {
        _payDividends(_round, _stakers, _dividendReward, _totalStakedAmount);
        emit DividendPaid(_dividendReward, block.timestamp);
    }

    // set time lock for unstake
    function setTimeLock(uint256 _timeLock) public onlyOwner {
        timeLock = _timeLock;
    }

    function getStakers() public view returns (address[] memory) {
        return stakers.values();
    }

    function getAllStakersInfo() public view returns (StakerInfo[] memory) {
        uint256 numOfStakers = stakers.length();
        StakerInfo[] memory listStakers = new StakerInfo[](numOfStakers);
        for(uint256 i = 0; i < numOfStakers; i++){
            listStakers[i] = stakerInfo[stakers.at(i)];
        }
        return listStakers;
    }

    function getAllStakersInfo(address [] calldata _stakers) public view returns (StakerInfo[] memory) {
        uint256 numOfStakers = _stakers.length;
        StakerInfo[] memory listStakers = new StakerInfo[](numOfStakers);
        for(uint256 i = 0; i < numOfStakers; i++){
            listStakers[i] = stakerInfo[_stakers[i]];
        }
        return listStakers;
    }


    function _payDividends(uint256 _round, address[] memory _stakers, uint256 _dividendReward, uint256 _totalStakedAmount) private {
        if(isDividendPaid[_round]) revert InvalidRound(_round);
        isDividendPaid[_round] = true;
        uint256 stakerCount = _stakers.length;
        for(uint256 i = 0; i < stakerCount; i++){
            address _staker = _stakers[i];
            uint256 stakedAmount = stakerInfo[_staker].amount;
            if(stakedAmount == 0 || isDividendClaimed[_round][_staker]) continue;
            _payDividend(_round, _staker, _dividendReward, _totalStakedAmount);
        }
    }


    function _payDividend(uint256 _round, address _staker, uint256 _amount, uint256 _totalStakedAmount) private returns(bool) {
        uint256 dividendAmount = _calculateDevidendAmount(_staker, _amount, _totalStakedAmount);
        if(dividendAmount == 0) return false;
        if(!token.transferFrom(owner(), _staker, dividendAmount)) return false;
        stakerInfo[_staker].dividendClaimed += dividendAmount;
        isDividendClaimed[_round][_staker] = true;
        userDividendClaimed[_round][_staker] += dividendAmount;
        return true;
    }
    /**
     * @dev calculate dividend of staker
     * @param _staker address of staker
     * @param _amount amount of dividend reward
     */
    function _calculateDevidendAmount(address _staker, uint256 _amount, uint256 _totalStakedAmount) private view returns(uint256){
        uint256 dividendPercentage = _calculateDividendPercentage(_staker, _totalStakedAmount);
        return _amount * dividendPercentage / 1e18;
    }

    /**
     * @dev calculate dividend of staker
     */
    function _calculateDividendPercentage(address _staker, uint256 _totalStakedAmount) private view returns (uint256) {
        uint256 stakedAmount = stakerInfo[_staker].amount;
        if(_totalStakedAmount == 0) revert NoStaker();
        return stakedAmount * 1e18 / _totalStakedAmount;
    }

    receive() external payable {
        require(msg.value > 0, "Invalid amount");
    }

    // withdraw native token
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
    // withdraw token ERC20
    function withdrawERC20(address _token) external onlyOwner {
        uint256 balance;
        // always keep staked amount in the contract
        if(_token == address(token)){
            balance = token.balanceOf(address(this)) - totalStakedAmount;
        } else {
            balance = IERC20(_token).balanceOf(address(this));
        }
        if(balance == 0) revert ZeroBalance();
        IERC20(_token).transfer(owner(), balance);
    }

}
