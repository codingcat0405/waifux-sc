//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "openzeppelin-solidity/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

contract MarketplaceV2 is IERC721Receiver, Ownable {
    using SafeERC20 for IERC20;
    address public nftAddress;

    struct ListDetail {
        address payable author;
        uint256 price;
        uint256 tokenId;
    }

    event ListNFT(address indexed _from, uint256 _tokenId, uint256 _price);
    event UnlistNFT(address indexed _from, uint256 _tokenId);
    event BuyNFT(address indexed _from, uint256 _tokenId, uint256 _price);
    event UpdateListingNFTPrice(uint256 _tokenId, uint256 _price);

    uint256 public tax = 7;
    mapping(uint256 => ListDetail) public listDetail;
    mapping(address => uint256[]) public authorListedNfts;
    // save all listed token ids
    uint256[] public listedTokenIds;

    //uint256 public totalListedNft;

    constructor(address _nftAddress) {
        nftAddress = _nftAddress;
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

    /**
     * @dev get a list of NFTs listed on marketplace from an author address
     */
    function getListedNftByAddress(
        address _author
    ) public view returns (uint256[] memory) {
        return authorListedNfts[_author];
    }

    // get all listed NFTs to show on marketplace
    function getAllListedNfts() public view returns (ListDetail[] memory) {
        // get balance of NFTs on this contract
        uint256 balance = IERC721Enumerable(nftAddress).balanceOf(
            address(this)
        );
        ListDetail[] memory listNftDetail = new ListDetail[](balance);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = IERC721Enumerable(nftAddress).tokenOfOwnerByIndex(
                address(this),
                i
            );
            listNftDetail[i] = listDetail[tokenId];
        }
        return listNftDetail;
    }

    /**
     * @dev list NFT to marketplace
     */
    function listNft(uint256 _tokenId, uint256 _price) public {
        require(
            IERC721Enumerable(nftAddress).ownerOf(_tokenId) == msg.sender,
            "You are not the owner of this NFT"
        );
        require(
            listDetail[_tokenId].author == address(0),
            "This NFT is already listed"
        );
        // approve this contract to transfer NFT
        require(
            IERC721Enumerable(nftAddress).isApprovedForAll(
                msg.sender,
                address(this)
            ),
            "You need to approve this contract to transfer your NFT"
        );
        // update listDetail
        listDetail[_tokenId] = ListDetail({
            author: payable(msg.sender),
            price: _price,
            tokenId: _tokenId
        });
        // transfer NFT to this contract
        IERC721Enumerable(nftAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenId
        );
        // save listDetail to authorListedNfts
        authorListedNfts[msg.sender].push(_tokenId);
        emit ListNFT(msg.sender, _tokenId, _price);
    }

    /**
     * @dev update price of NFT on Marketplace
     */
    function updateListingNftPrice(uint256 _tokenId, uint256 _price) public {
        require(
            listDetail[_tokenId].author == msg.sender,
            "You are not the owner of this NFT"
        );
        listDetail[_tokenId].price = _price;
        emit UpdateListingNFTPrice(_tokenId, _price);
    }

    /**
     * @dev unlist NFT from marketplace
     */
    function unlistNft(uint256 _tokenId) public {
        require(
            listDetail[_tokenId].author == msg.sender,
            "You are not the owner of this NFT"
        );
        // transfer NFT to owner
        IERC721Enumerable(nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            _tokenId
        );
        // delete listDetail
        delete listDetail[_tokenId];
        // delete listDetail from authorListedNfts
        uint256[] storage listedNfts = authorListedNfts[msg.sender];
        for (uint256 i = 0; i < listedNfts.length; i++) {
            if (listedNfts[i] == _tokenId) {
                listedNfts[i] = listedNfts[listedNfts.length - 1];
                listedNfts.pop();
                break;
            }
        }
        emit UnlistNFT(msg.sender, _tokenId);
    }

    /**
     * @dev buy NFT from marketplace
     */
    function buyNft(uint256 _tokenId, uint256 _price) public payable {
        require(msg.value >= _price, "Dont have enough money to buy this NFT!");
        require(
            IERC721Enumerable(nftAddress).ownerOf(_tokenId) == address(this),
            "This NFT does not exist in Marketplace to buy!"
        );
        require(
            listDetail[_tokenId].author != address(0),
            "This NFT is not listed"
        );
        require(
            listDetail[_tokenId].author != msg.sender,
            "You are the owner of this NFT"
        );
        require(
            listDetail[_tokenId].price <= _price,
            "You need to pay more money to buy this NFT"
        );

        // transfer NFT to buyer
        IERC721Enumerable(nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            _tokenId
        );
        // transfer money to author
        uint256 taxAmount = (_price * tax) / 100;
        uint256 authorAmount = _price - taxAmount;

        payable(listDetail[_tokenId].author).transfer(authorAmount);

        // delete listDetail
        delete listDetail[_tokenId];
        // delete listDetail from authorListedNfts
        uint256[] storage listedNfts = authorListedNfts[
            listDetail[_tokenId].author
        ];
        for (uint256 i = 0; i < listedNfts.length; i++) {
            if (listedNfts[i] == _tokenId) {
                listedNfts[i] = listedNfts[listedNfts.length - 1];
                listedNfts.pop();
                break;
            }
        }
        emit BuyNFT(msg.sender, _tokenId, msg.value);
    }

    /**
     * @dev withdraw money from contract to owner
     */

    function withdraw() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * @dev withdraw token ERC20 from contract to owner
     */
    function withdrawTokenERC20(address _tokenAddress) public onlyOwner {
        IERC20(_tokenAddress).transfer(
            msg.sender,
            IERC20(_tokenAddress).balanceOf(address(this))
        );
    }

    // get balance of NFTs on this contract
    function getTotalNftListed() public view returns (uint256) {
        return IERC721Enumerable(nftAddress).balanceOf(address(this));
    }

    /**
     * @dev set tax for buy NFTs
     */
    function setTax(uint256 _tax) public onlyOwner {
        tax = _tax;
    }

    /**
     * @dev set NFT address
     */
    function setNft(address _nftAddress) public onlyOwner {
        nftAddress = _nftAddress;
    }
}
