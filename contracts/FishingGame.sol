// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20Extended is IERC20{
    function decimals() external view returns (uint8);
}

contract FishingGame is Ownable, ERC1155, ERC1155Burnable {
    uint256 public constant BAIT = 0;
    uint256 public constant ROD = 1;

    IERC20Extended public stableCoin;
    IERC20Extended public customToken;

    address private manager;

    struct BaitPrice {
        uint256 priceInEther;
        uint256 priceInStableCoin;
        uint256 priceInCustomToken;
    }
    struct RodPrice {
        uint256 priceInEther;
        uint256 priceInStableCoin;
        uint256 priceInCustomToken;
    }

    BaitPrice public baitPrice;
    RodPrice public rodPrice;

    event BuyItemWithEther(address indexed player, uint256 indexed itemId, uint256 indexed itemAmount);
    event BuyItemWithStableCoin(address indexed player, uint256 indexed itemId, uint256 indexed itemAmount, uint256 stableCoinAmount);
    event BuyItemWithCustomToken(address indexed player, uint256 indexed itemId, uint256 indexed itemAmount, uint256 customTokenAmount);

    event MintBait(address indexed player, uint256 indexed amount);
    event MintRod(address indexed player,uint256 indexed amount);
    event BuyItem(address indexed player, uint256 indexed itemId, uint256 indexed itemAmount, uint256 payAmount);

    error InvalidItemID(uint256 itemId);
    error InvalidAmount(uint256 amount);
    error InvalidToken(address tokenAddr);
    error InvalidTransfer(string message);

    constructor(address _stableCoin, address _customToken, address _manager) Ownable(msg.sender) ERC1155("https://xfish.pet/item/{id}.json")  {
        stableCoin = IERC20Extended(_stableCoin);
        customToken = IERC20Extended(_customToken);
        manager = _manager;
        // Set the price for each item
        baitPrice = BaitPrice(0.00323 ether, 1*10**stableCoin.decimals(), 100_000*10**customToken.decimals());
        rodPrice = RodPrice(0.162 ether, 50*10**stableCoin.decimals(), 5_000_000*10**customToken.decimals());
    }

    function buyGameItems(address tokenAddr, uint256 itemId, uint256 itemQuantity, uint256 amount) external payable{
        uint256 payAmount = getPayAmount(tokenAddr, itemId, itemQuantity);
        if(tokenAddr == address(0)) {
            if(msg.value < payAmount) revert InvalidAmount(msg.value);
        }else{
            if(!userPayment(tokenAddr, amount, payAmount)) revert InvalidTransfer("Payment failed");
        }
        _mintItem(msg.sender, itemId, itemQuantity);
        emit BuyItem(msg.sender, itemId, itemQuantity, payAmount);
    }

    // mint bait from owner
    function mintBaits(address player, uint256 amount) external onlyOwner {
        _mint(player, BAIT, amount, "");
        emit MintBait(player, amount);
    }
    // mint rod from owner
    function mintRods(address player, uint256 amount) external onlyOwner {
        _mint(player, ROD, amount, "");
        emit MintRod(player, amount);
    }

    // burn from owner
    function burnByOwner(address account, uint256 id, uint256 amount) external onlyOwner {
        _burn(account, id, amount);
    }

    function _mintItem(address account, uint256 id, uint256 quantity ) private {
        _mint(account, id, quantity, "");
        _setApprovalForAll(_msgSender(), manager, true);
    }

    function userPayment(address _tokenAddr, uint256 _amount, uint256 _payAmount) internal returns(bool){
        if(_tokenAddr == address(stableCoin)){
            if(_amount < _payAmount || !stableCoin.transferFrom(msg.sender, manager, _payAmount)) return false;
        } else if(_tokenAddr == address(customToken)){
            if(_amount < _payAmount || !customToken.transferFrom(msg.sender, manager, _payAmount)) return false;
        } else {
            revert InvalidToken(_tokenAddr);
        }
        return true;
    }

    function getPrice(address tokenAddr, uint256 itemId) internal view returns(uint256){
        if(tokenAddr == address(0)){
            return (itemId == BAIT) ? baitPrice.priceInEther : rodPrice.priceInEther;
        } else if(tokenAddr == address(stableCoin)){
            return (itemId == BAIT) ? baitPrice.priceInStableCoin : rodPrice.priceInStableCoin;
        } else if(tokenAddr == address(customToken)){
            return (itemId == BAIT) ? baitPrice.priceInCustomToken : rodPrice.priceInCustomToken;
        } else {
            revert InvalidToken(tokenAddr);
        }
    }

    function getPayAmount(address tokenAddr, uint256 itemId, uint256 itemQuantity) internal view returns(uint256){
        uint256 price = getPrice(tokenAddr, itemId);
        return price * itemQuantity;
    }

    // override _setURI(string memory newuri) function
    function _setURI(string memory newuri) internal override onlyOwner{
        super._setURI(newuri);
    }

    // set manager address from owner
    function setManager(address __manager) external onlyOwner {
        manager = __manager;
    }

    // set the price for bait item
    function setBaitPrice(uint256 _priceInEther, uint256 _priceInStableCoin, uint256 _priceInCustomToken) external onlyOwner {
        baitPrice = BaitPrice(_priceInEther, _priceInStableCoin, _priceInCustomToken);
    }
    // set the price for rod item
    function setRodPrice(uint256 _priceInEther, uint256 _priceInStableCoin, uint256 _priceInCustomToken) external onlyOwner {
        rodPrice = RodPrice(_priceInEther, _priceInStableCoin, _priceInCustomToken);
    }
    // set stableCoin address and customToken address from owner
    function setTokenAddress(address _stableCoin, address _customToken) external onlyOwner {
        stableCoin = IERC20Extended(_stableCoin);
        customToken = IERC20Extended(_customToken);
    }
    // withdraw eth
    function withdrawETH(address admin) external onlyOwner{
        payable(admin).transfer(address(this).balance);
    }
    // withdraw token
    function withdrawTokenERC20(address token, address admin) external onlyOwner{
        IERC20(token).transfer(admin, IERC20(token).balanceOf(address(this)));
    }
    // receive fallback
    receive() external payable{
        require(msg.value > 0, "Invalid amount");
    }

    // override _updateWithAcceptanceCheck do not allow transfer from normal user, only allow owner, but normal user can burn their token
    function _updateWithAcceptanceCheck(address from, address to, uint256[] memory ids, uint256[] memory values, bytes memory data) internal override {
        require(from == owner() || from  == address(0) || to == owner() || to == address(0), "Not allow transfer from normal user");
        super._updateWithAcceptanceCheck(from, to, ids, values, data);
    }

}