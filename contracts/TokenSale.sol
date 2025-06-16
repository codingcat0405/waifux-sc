// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title TokenSale
 * @dev Private sale contract for XFISH token with vesting mechanism
 */
contract TokenSale is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Token being sold
    IERC20 public immutable xfishToken;
    
    // Price configuration
    uint256 public usdtPrice; // XFISH per USDT (with 6 decimals for USDT)
    uint256 public ethPrice;  // USDT per ETH (with 18 decimals for ETH)
    
    // Sale state
    bool public saleActive;
    uint256 public totalEthRaised;
    uint256 public totalTokensSold;
    
    // Vesting configuration
    uint256 public constant VESTING_DURATION = 9; // 9 months total
    uint256 public constant IMMEDIATE_RELEASE_PERCENTAGE = 10; // 10% immediate
    uint256 public constant MONTHLY_RELEASE_PERCENTAGE = 10; // 10% per month
    uint256 public constant MONTH_DURATION = 30 days;
    
    // User vesting information
    struct VestingInfo {
        uint256 totalAmount;        // Total XFISH purchased
        uint256 claimedAmount;      // Amount already claimed
        uint256 purchaseTime;       // Timestamp of purchase
        uint256 lastClaimTime;      // Last claim timestamp
    }
    
    mapping(address => VestingInfo) public vestingInfo;
    mapping(address => bool) public hasParticipated;
    address[] public participants;
    
    // Events
    event TokensPurchased(address indexed buyer, uint256 ethAmount, uint256 tokenAmount);
    event TokensClaimed(address indexed user, uint256 amount);
    event SaleStarted();
    event SaleEnded();
    event PricesUpdated(uint256 newUsdtPrice, uint256 newEthPrice);
    event EmergencyWithdraw(address token, uint256 amount);
    event ReferralBonusTransferred(address indexed recipient, uint256 amount, string reason);
    
    // Custom errors for gas optimization
    error SaleNotActive();
    error SaleAlreadyActive();
    error InvalidPrice();
    error InvalidAmount();
    error NothingToClaim();
    error TransferFailed();
    error InsufficientContractBalance();
    
    /**
     * @dev Constructor
     * @param _xfishToken Address of XFISH token
     * @param _usdtPrice XFISH per USDT (e.g., 10000 means 1 USDT = 10000 XFISH)
     * @param _ethPrice USDT per ETH (e.g., 2500 means 1 ETH = 2500 USDT)
     */
    constructor(
        address _xfishToken,
        uint256 _usdtPrice,
        uint256 _ethPrice
    ) Ownable(msg.sender) {
        if (_xfishToken == address(0)) revert InvalidAmount();
        if (_usdtPrice == 0 || _ethPrice == 0) revert InvalidPrice();
        
        xfishToken = IERC20(_xfishToken);
        usdtPrice = _usdtPrice;
        ethPrice = _ethPrice;
    }
    
    /**
     * @dev Start the private sale
     */
    function startSale() external onlyOwner {
        if (saleActive) revert SaleAlreadyActive();
        saleActive = true;
        emit SaleStarted();
    }
    
    /**
     * @dev End the private sale
     */
    function endSale() external onlyOwner {
        if (!saleActive) revert SaleNotActive();
        saleActive = false;
        emit SaleEnded();
    }
    
    /**
     * @dev Update prices
     * @param _usdtPrice New XFISH per USDT price
     * @param _ethPrice New USDT per ETH price
     */
    function updatePrices(uint256 _usdtPrice, uint256 _ethPrice) external onlyOwner {
        if (_usdtPrice == 0 || _ethPrice == 0) revert InvalidPrice();
        usdtPrice = _usdtPrice;
        ethPrice = _ethPrice;
        emit PricesUpdated(_usdtPrice, _ethPrice);
    }
    
    /**
     * @dev Transfer referral bonus to user
     * @param recipient Address to receive the bonus
     * @param amount Amount of XFISH tokens to transfer
     * @param reason Reason for the referral bonus (for tracking)
     */
    function transferReferralBonus(
        address recipient,
        uint256 amount,
        string calldata reason
    ) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert InvalidAmount();
        if (amount == 0) revert InvalidAmount();
        
        // Check contract has enough tokens
        uint256 contractBalance = xfishToken.balanceOf(address(this));
        if (contractBalance < amount) {
            revert InsufficientContractBalance();
        }
        
        // Transfer tokens directly from contract's balance
        xfishToken.safeTransfer(recipient, amount);
        
        emit ReferralBonusTransferred(recipient, amount, reason);
    }
    
    /**
     * @dev Purchase tokens with ETH
     */
    function buyTokens() external payable nonReentrant whenNotPaused {
        if (!saleActive) revert SaleNotActive();
        if (msg.value == 0) revert InvalidAmount();
        
        // Calculate token amount
        // Example: 1 ETH = 2500 USDT, 1 USDT = 10000 XFISH
        // So 1 ETH = 2500 * 10000 = 25,000,000 XFISH
        // Since both ETH and XFISH have 18 decimals, we can directly multiply
        // tokenAmount = ethAmount * ethPrice * usdtPrice
        uint256 tokenAmount = msg.value * ethPrice * usdtPrice;
        
        if (tokenAmount == 0) revert InvalidAmount();
        
        // Check contract has enough tokens
        if (xfishToken.balanceOf(address(this)) < tokenAmount) {
            revert InsufficientContractBalance();
        }
        
        // Update global stats
        totalEthRaised += msg.value;
        totalTokensSold += tokenAmount;
        
        // Track new participants
        if (!hasParticipated[msg.sender]) {
            hasParticipated[msg.sender] = true;
            participants.push(msg.sender);
        }
        
        // Update vesting info
        VestingInfo storage info = vestingInfo[msg.sender];
        info.totalAmount += tokenAmount;
        if (info.purchaseTime == 0) {
            info.purchaseTime = block.timestamp;
        }
        
        // Transfer immediate 10%
        uint256 immediateAmount = (tokenAmount * IMMEDIATE_RELEASE_PERCENTAGE) / 100;
        info.claimedAmount += immediateAmount;
        info.lastClaimTime = block.timestamp;
        
        xfishToken.safeTransfer(msg.sender, immediateAmount);
        
        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
    }
    
    /**
     * @dev Claim vested tokens
     */
    function claimTokens() external nonReentrant whenNotPaused {
        VestingInfo storage info = vestingInfo[msg.sender];
        
        if (info.totalAmount == 0) revert NothingToClaim();
        
        uint256 claimableAmount = getClaimableAmount(msg.sender);
        
        if (claimableAmount == 0) revert NothingToClaim();
        
        // Check contract has enough tokens
        if (xfishToken.balanceOf(address(this)) < claimableAmount) {
            revert InsufficientContractBalance();
        }
        
        info.claimedAmount += claimableAmount;
        info.lastClaimTime = block.timestamp;
        
        xfishToken.safeTransfer(msg.sender, claimableAmount);
        
        emit TokensClaimed(msg.sender, claimableAmount);
    }
    
    /**
     * @dev Get claimable amount for a user
     * @param user Address to check
     * @return Amount of tokens that can be claimed
     */
    function getClaimableAmount(address user) public view returns (uint256) {
        VestingInfo memory info = vestingInfo[user];
        
        if (info.totalAmount == 0) return 0;
        
        // Calculate months passed since purchase
        uint256 monthsPassed = (block.timestamp - info.purchaseTime) / MONTH_DURATION;
        
        // Cap at 9 months (10% immediate + 9 * 10% = 100%)
        if (monthsPassed > VESTING_DURATION) {
            monthsPassed = VESTING_DURATION;
        }
        
        // Calculate total vested amount (10% immediate + monthsPassed * 10%)
        uint256 vestedPercentage = IMMEDIATE_RELEASE_PERCENTAGE + (monthsPassed * MONTHLY_RELEASE_PERCENTAGE);
        uint256 totalVested = (info.totalAmount * vestedPercentage) / 100;
        
        // Return claimable (vested - already claimed)
        if (totalVested > info.claimedAmount) {
            return totalVested - info.claimedAmount;
        }
        
        return 0;
    }
    
    /**
     * @dev Get next release info for a user
     * @param user Address to check
     * @return nextReleaseTime Timestamp of next release
     * @return nextReleaseAmount Amount to be released
     */
    function getNextReleaseInfo(address user) external view returns (uint256 nextReleaseTime, uint256 nextReleaseAmount) {
        VestingInfo memory info = vestingInfo[user];
        
        if (info.totalAmount == 0 || info.claimedAmount >= info.totalAmount) {
            return (0, 0);
        }
        
        uint256 monthsPassed = (block.timestamp - info.purchaseTime) / MONTH_DURATION;
        
        if (monthsPassed >= VESTING_DURATION) {
            // All vested, can claim remaining
            return (block.timestamp, info.totalAmount - info.claimedAmount);
        }
        
        // Next release is at the next month mark
        nextReleaseTime = info.purchaseTime + ((monthsPassed + 1) * MONTH_DURATION);
        nextReleaseAmount = (info.totalAmount * MONTHLY_RELEASE_PERCENTAGE) / 100;
        
        return (nextReleaseTime, nextReleaseAmount);
    }
    
    /**
     * @dev Get user vesting details
     * @param user Address to check
     * @return total Total tokens purchased
     * @return claimed Tokens already claimed
     * @return claimable Tokens currently claimable
     * @return locked Tokens still locked
     */
    function getUserVestingDetails(address user) external view returns (
        uint256 total,
        uint256 claimed,
        uint256 claimable,
        uint256 locked
    ) {
        VestingInfo memory info = vestingInfo[user];
        total = info.totalAmount;
        claimed = info.claimedAmount;
        claimable = getClaimableAmount(user);
        locked = total > (claimed + claimable) ? total - claimed - claimable : 0;
    }
    
    /**
     * @dev Owner withdraw ETH
     */
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InvalidAmount();
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        if (!success) revert TransferFailed();
    }
    
    /**
     * @dev Owner withdraw tokens (for unsold tokens or emergency)
     * @param token Token address (use address(0) for ETH)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (amount == 0) revert InvalidAmount();
        
        if (token == address(0)) {
            // Withdraw ETH
            if (address(this).balance < amount) revert InsufficientContractBalance();
            (bool success, ) = payable(owner()).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            // Withdraw tokens
            IERC20(token).safeTransfer(owner(), amount);
        }
        
        emit EmergencyWithdraw(token, amount);
    }
    
    /**
     * @dev Pause contract (emergency)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Get total number of participants
     */
    function getParticipantCount() external view returns (uint256) {
        return participants.length;
    }
    
    /**
     * @dev Get participant address by index
     */
    function getParticipant(uint256 index) external view returns (address) {
        return participants[index];
    }
    
    /**
     * @dev Calculate token amount for given ETH amount
     * @param ethAmount ETH amount in wei
     * @return Token amount user will receive
     */
    function calculateTokenAmount(uint256 ethAmount) external view returns (uint256) {
        return ethAmount * ethPrice * usdtPrice;
    }
    
    /**
     * @dev Get contract XFISH balance
     * @return Current XFISH token balance of the contract
     */
    function getContractXFISHBalance() external view returns (uint256) {
        return xfishToken.balanceOf(address(this));
    }
    
    /**
     * @dev Check if contract has sufficient balance for operation
     * @param amount Amount to check
     * @return true if contract has sufficient balance
     */
    function hasSufficientBalance(uint256 amount) external view returns (bool) {
        return xfishToken.balanceOf(address(this)) >= amount;
    }
    
    /**
     * @dev Receive ETH
     */
    receive() external payable {
        revert("Use buyTokens function");
    }
}