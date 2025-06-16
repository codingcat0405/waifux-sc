// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract Fish is Ownable {

    address private admin;

    IERC20 public customToken;

    mapping (uint256 =>  bool) public isUsedId;
    mapping (uint256 => bool) public isUsedNonce;

    event BuyFish(uint256 indexed id, uint256 indexed amount, address player);
    event ClaimPayment(uint256 indexed id, uint256 indexed amount, address player);

    error InvalidId(uint256 id);
    error InvalidNonce(uint256 nonce);
    error InvalidBuy(string message);
    error InvalidSignature(string message);

    constructor(address _admin, address _customToken) Ownable(msg.sender) {
        admin = _admin;
        customToken = IERC20(_customToken);
    }

    function userSafeBuy(uint256 id, uint256 amount) public {
        if(isUsedId[id]) revert InvalidId(id);
        isUsedId[id] = true;
        if(amount == 0) revert InvalidBuy("Invalid amount");
        bool isSent = customToken.transferFrom(msg.sender, address(this), amount);
        if(!isSent) revert InvalidBuy("Buy failed");
        emit BuyFish(id, amount, msg.sender);
    }

    function claimPayments(address recipient, uint256 amount, uint256 nonce, uint8 v, bytes32 r, bytes32 s) public{
        if(isUsedNonce[nonce]) revert InvalidNonce(nonce);
        isUsedNonce[nonce] = true;
        bytes32 message = keccak256(abi.encode(recipient, amount, nonce));
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, message));
        address signer = ecrecover(prefixedHashMessage, v, r, s);
        if(signer != admin) revert InvalidSignature("Invalid signature");
        // transfer to recipient
        customToken.transfer(recipient, amount);
        emit ClaimPayment(nonce, amount, recipient);
    }

    function setIds(uint256[] memory ids, bool status) public onlyOwner{
        for(uint256 i = 0; i < ids.length; i++){
            isUsedId[ids[i]] = status;
        }
    }

    function setAdmin(address _admin) external onlyOwner{
        admin = _admin;
    }

    function setCustomToken(address _customToken) external onlyOwner{
        customToken = IERC20(_customToken);
    }

    // withdraw eth
    function withdrawETH() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
    // withdraw erc20
    function withdrawErc20(address token) public onlyOwner {
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }
    // receive fallback
    receive() external payable{
        require(msg.value > 0, "Invalid amount");
    }

}