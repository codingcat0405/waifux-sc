//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";

contract AuctionHouseV2 is IERC721Receiver, Ownable {
    IERC721Enumerable public nft;
    IERC20 public token;

    uint public constant AUCTION_SERVICE_FEE_RATE = 3; // Percentage

    uint public constant MINIMUM_BID_RATE = 110; // Percentage
    event AuctionCreated(
        address indexed auctioneer,
        uint256 tokenId,
        uint256 initialPrice,
        uint256 startTime,
        uint256 endTime
    );
    event AuctionJoined(address indexed bidder, uint256 auctionId, uint256 bid);
    event AuctionCompleted(
        address indexed auctioneer,
        uint256 auctionId,
        uint256 bid,
        address indexed winner
    );
    event AuctionCancelled(address indexed auctioneer, uint256 auctionId);

    constructor(IERC20 _token, IERC721Enumerable _nft) {
        token = _token;
        nft = _nft;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    struct AuctionInfo {
        address auctioneer;
        uint256 _tokenId;
        uint256 initialPrice;
        address previousBidder;
        uint256 lastBid;
        address lastBidder;
        uint256 startTime;
        uint256 endTime;
        bool completed;
        bool active;
    }

    AuctionInfo[] public auction;

    /**
     * @dev Create an auction
     */
    function createAuction(
        uint256 _tokenId,
        uint256 _initialPrice,
        uint256 _startTime,
        uint256 _endTime
    ) public {
        require(block.timestamp <= _startTime, "Auction can not start");
        require(_startTime < _endTime, "Auction can not end before it starts");
        require(0 < _initialPrice, "Initial price must be greater than 0");
        require(
            nft.ownerOf(_tokenId) == msg.sender,
            "Must stake your own token"
        );
        require(
            nft.getApproved(_tokenId) == address(this),
            "This contract must be approved to transfer the token"
        );
        // Transfer ownership to the auctioneer
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);

        AuctionInfo memory _auction = AuctionInfo(
            msg.sender, // auctioneer
            _tokenId, // tokenId
            _initialPrice, // initialPrice
            address(0), // previousBidder
            _initialPrice, // lastBid
            address(0), // lastBidder
            _startTime, // startTime
            _endTime, // endTime
            false, // completed
            true // active
        );

        auction.push(_auction);
        emit AuctionCreated(
            msg.sender,
            _tokenId,
            _initialPrice,
            _startTime,
            _endTime
        );
    }

    function joinAuction(uint256 _auctionId, uint256 _bid) public {
        AuctionInfo memory _auction = auction[_auctionId];

        require(
            block.timestamp >= _auction.startTime,
            "Auction has not started"
        );
        require(_auction.completed == false, "Auction is already completed");
        require(_auction.active, "Auction is not active");
        // current bid must be greater than 10% of the last bid
        uint256 _minBid = _auction.lastBidder == address(0)
            ? _auction.initialPrice
            : (_auction.lastBid * MINIMUM_BID_RATE) / 100;

        require(
            _minBid <= _bid,
            "Bid price must be greater than the minimum price"
        );
        require(token.balanceOf(msg.sender) >= _bid, "Insufficient balance");
        require(
            token.allowance(msg.sender, address(this)) >= _bid,
            "Insufficient allowance"
        );
        // require(_auction.lastBidder != msg.sender, "You have already bid on this auction");
        require(
            _auction.auctioneer != msg.sender,
            "Can not bid on your own auction"
        );

        // Next bidder transfer token to contract
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), _bid);

        // Refund token to previous bidder
        if (_auction.lastBidder != address(0)) {
            token.transfer(_auction.lastBidder, _auction.lastBid);
        }

        // Update auction info
        auction[_auctionId].previousBidder = _auction.lastBidder;
        auction[_auctionId].lastBidder = msg.sender;
        auction[_auctionId].lastBid = _bid;
        emit AuctionJoined(msg.sender, _auctionId, _bid);
    }

    function finishAuction(
        uint256 _auctionId
    ) public onlyAuctioneer(_auctionId) {
        require(
            auction[_auctionId].completed == false,
            "Auction is already completed"
        );
        require(auction[_auctionId].active, "Auction is not active");

        // Transfer NFT to winner which is the last bidder
        nft.safeTransferFrom(
            address(this),
            auction[_auctionId].lastBidder,
            auction[_auctionId]._tokenId
        );

        // Calculate all fee
        uint256 lastBid = auction[_auctionId].lastBid;
        uint256 profit = auction[_auctionId].lastBid -
            auction[_auctionId].initialPrice;

        uint256 auctionServiceFee = (profit * AUCTION_SERVICE_FEE_RATE) / 100;

        uint256 auctioneerReceive = lastBid - auctionServiceFee;

        // Transfer token to auctioneer
        token.transfer(auction[_auctionId].auctioneer, auctioneerReceive);

        auction[_auctionId].completed = true;
        auction[_auctionId].active = false;
        emit AuctionCompleted(
            auction[_auctionId].auctioneer,
            _auctionId,
            auction[_auctionId].lastBid,
            auction[_auctionId].lastBidder
        );
    }

    function cancelAuction(
        uint256 _auctionId
    ) public onlyAuctioneer(_auctionId) {
        require(
            auction[_auctionId].completed == false,
            "Auction is already completed"
        );
        require(auction[_auctionId].active, "Auction is not active");

        // Return NFT back to auctioneer
        nft.safeTransferFrom(
            address(this),
            auction[_auctionId].auctioneer,
            auction[_auctionId]._tokenId
        );

        // Refund token to previous bidder
        if (auction[_auctionId].lastBidder != address(0)) {
            token.transfer(
                auction[_auctionId].lastBidder,
                auction[_auctionId].lastBid
            );
        }

        auction[_auctionId].completed = true;
        auction[_auctionId].active = false;
        emit AuctionCancelled(auction[_auctionId].auctioneer, _auctionId);
    }

    function getAuction(
        uint256 _auctionId
    ) public view returns (AuctionInfo memory) {
        return auction[_auctionId];
    }

    function getNft(address _address) public view returns (uint256[] memory) {
        uint balance = nft.balanceOf(_address);
        uint256[] memory myNft = new uint256[](balance);

        for (uint i = 0; i < balance; i++) {
            myNft[i] = nft.tokenOfOwnerByIndex(_address, i);
        }
        return myNft;
    }

    function getAllAuction() public view returns (AuctionInfo[] memory) {
        return auction;
    }

    // get lastest auction id by token id
    function getAuctionIdByTokenId(
        uint256 _tokenId
    ) public view returns (uint256) {
        // return auction id if found
        for (uint256 i = auction.length - 1; i >= 0; i--) {
            if (auction[i]._tokenId == _tokenId) {
                return i;
            }
        }
        // revert if not found
        revert("Auction not found with this token id!");
    }

    function withdraw() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawErc20(IERC20 token) public onlyOwner {
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    modifier onlyAuctioneer(uint256 _auctionId) {
        require(
            msg.sender == auction[_auctionId].auctioneer,
            "Only auctioneer can perform this action"
        );
        _;
    }
}
