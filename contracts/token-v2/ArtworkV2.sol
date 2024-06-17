//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "openzeppelin-solidity/contracts/utils/Context.sol";
import "openzeppelin-solidity/contracts/utils/Counters.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-solidity/contracts/utils/math/SafeMath.sol";

contract Set {
    address[] items;
    mapping(address => uint256) presence;

    constructor() {}

    function size() public view returns (uint256) {
        return items.length;
    }

    function has(address item) public view returns (bool) {
        return presence[item] > 0;
    }

    function list() public view returns (address[] memory) {
        return items;
    }

    function indexOf(address item) public view returns (uint256) {
        require(presence[item] > 0, "Item not found");
        return presence[item] - 1;
    }

    function get(uint256 index) public view returns (address) {
        return items[index];
    }

    function add(address item) public {
        if (presence[item] > 0) {
            return;
        }

        items.push(item);
        presence[item] = items.length; // index plus one
    }

    function remove(address item) public {
        if (presence[item] == 0) {
            return;
        }

        if (items.length > 1) {
            uint256 index = presence[item] - 1;
            presence[items[items.length - 1]] = index + 1;
            items[index] = items[items.length - 1];
        }
        presence[item] = 0;
        items.pop();
    }

    function clear() public {
        for (uint256 i = 0; i < items.length; i++) {
            presence[items[i]] = 0;
        }

        delete items;
    }
}

contract ArtworkV2 is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    Set public artists;

    uint256 public blindBoxPrice;
    uint256 public blindBoxOpenFee;
    uint256 public blindBoxBuyLimit;
    uint256 public constant MAX_SUPPLY = 5000;

    mapping(address => uint256) public blindBox;
    // total box bought
    uint256 public totalBoxBought;
    // total box opened
    uint256 public totalBoxOpened;

    string public baseUri = "https://cryptopop.io/";

    Counters.Counter private _tokenIdTracker;

    constructor() ERC721("Cryptopop Artwork", "Artwork") {
        artists = new Set();
        // mint 2000 NFTs initial supply for this contract
        for (uint256 i = 0; i < 30; i++) {
            _safeMint(address(this), i);
        }
        _tokenIdTracker._value = totalSupply();
    }

    // === Events ===
    event BuyBlindBox(address indexed _buyer, uint256 _quantity);

    event OpenBlindBox(address indexed _from, uint256 indexed _id);

    event TransferBlindBox(
        address indexed _from,
        address indexed _to,
        uint256 _amount
    );

    // === Getter & Setters ===

    function getArtworks() public view returns (uint256[] memory) {
        uint256 balance = this.balanceOf(address(this));
        uint256[] memory myNft = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            myNft[i] = this.tokenOfOwnerByIndex(address(this), i);
        }
        return myNft;
    }

    function getArtists() public view returns (address[] memory) {
        return artists.list();
    }

    function getBlindBoxPrice() public view returns (uint256) {
        return blindBoxPrice;
    }

    function getBlindBoxOpenFee() public view returns (uint256) {
        return blindBoxOpenFee;
    }

    function getBlindBoxBuyLimit() public view returns (uint256) {
        return blindBoxBuyLimit;
    }

    function getBaseUri() public view returns (string memory) {
        return baseUri;
    }

    function setBlindBoxPrice(uint256 _blindBoxPrice) public onlyOwner {
        blindBoxPrice = _blindBoxPrice;
    }

    function setBlindBoxOpenFee(uint256 _blindBoxOpenFee) public onlyOwner {
        blindBoxOpenFee = _blindBoxOpenFee;
    }

    function setBlindBoxBuyLimit(uint256 _blindBoxBuyLimit) public onlyOwner {
        blindBoxBuyLimit = _blindBoxBuyLimit;
    }

    function setBaseUri(string memory _baseUri) public onlyOwner {
        baseUri = _baseUri;
    }

    function random(uint256 _limit) private view returns (uint256) {
        return
            uint256(
                uint256(
                    keccak256(
                        abi.encodePacked(block.timestamp, block.difficulty)
                    )
                ) % _limit
            );
    }

    function addArtist(address _artist) public onlyOwner {
        require(_artist != address(0));
        artists.add(_artist);
    }

    function removeArtist(address _artist) public onlyOwner {
        require(_artist != address(0));
        artists.remove(_artist);
    }

    function mintArtwork() public onlyArtist {
        // require total supply is not over max supply
        require(totalSupply() < MAX_SUPPLY, "Total supply is over max supply!");
        uint256 _tokenId = _tokenIdTracker.current();
        _mint(address(this), _tokenId);
        _tokenIdTracker.increment();
    }

    function buyBlindBox(
        uint256 _quantity
    )
        public
        payable
        underQuantityLimit(_quantity)
        overMinimumPrice(_quantity * blindBoxPrice)
    {
        // require total blindbox is not over total supply
        require(
            totalBoxBought + _quantity <= totalSupply(),
            "Total blindbox is over total supply!"
        );
        //TODO: check msg.value of caller is equal or greater than _quantity * blindBoxPrice and transfer remaining to caller
        uint256 _totalPrice = _quantity * blindBoxPrice;
        uint256 remain = msg.value - _totalPrice;
        require(remain >= 0, "Not enought BNB");
        payable(msg.sender).transfer(remain);
        blindBox[msg.sender] += _quantity;
        totalBoxBought += _quantity;

        emit BuyBlindBox(msg.sender, _quantity);
    }

    function transferBlindBox(address to, uint256 _quantity) public {
        require(blindBox[msg.sender] >= _quantity, "Not enough blindBoxes");

        blindBox[msg.sender] -= _quantity;
        blindBox[to] += _quantity;

        emit TransferBlindBox(msg.sender, to, _quantity);
    }

    function openBlindBox(
        uint256 _quantity
    )
        public
        payable
        overMinimumPrice(blindBoxOpenFee * _quantity)
        underBlindBoxAmount(_quantity)
    {
        uint256 unSalesBox = balanceOf(address(this));
        for (uint256 index = 0; index < _quantity; index++) {
            uint256 _tokenId = tokenOfOwnerByIndex(
                address(this),
                random(unSalesBox)
            );

            this.safeTransferFrom(address(this), msg.sender, _tokenId);

            unSalesBox--;

            emit OpenBlindBox(msg.sender, _tokenId);
        }

        blindBox[msg.sender] -= _quantity;
        totalBoxOpened += _quantity;
    }

    function getNftListByAddress(
        address _address
    ) public view returns (uint256[] memory _ids) {
        uint256 balance = balanceOf(_address);
        uint256[] memory ids = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            ids[i] = tokenOfOwnerByIndex(_address, i);
        }
        return (ids);
    }

    /**
     * @dev transfer number of nfts for specific addresses
     */
    function transferNFTs(
        address[] memory _addresses,
        uint256[] memory _ids
    ) public onlyOwner {
        require(_addresses.length == _ids.length, "Invalid input");
        for (uint256 i = 0; i < _addresses.length; i++) {
            this.safeTransferFrom(address(this), _addresses[i], _ids[i]);
        }
    }

    /**
     * @dev fast mint nfts for only owner who is also an artist
     */
    function fastMintNFTs(uint256 _quantity) public onlyOwner {
        for (uint256 i = 0; i < _quantity; i++) {
            // Only owner and ower is artist can mint
            mintArtwork();
        }
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseUri;
    }

    function withdraw() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawErc20(IERC20 token) public onlyOwner {
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    modifier onlyArtist() {
        require(artists.has(msg.sender), "Only artists can mint");
        _;
    }

    modifier underQuantityLimit(uint256 _quantity) {
        require(
            _quantity <= blindBoxBuyLimit,
            "Quantity must be less than or equal to the buy limit"
        );
        _;
    }

    modifier underBlindBoxAmount(uint256 _amount) {
        require(
            _amount <= blindBox[msg.sender],
            "Not enough blind boxes to open"
        );
        _;
    }

    modifier overMinimumPrice(uint256 _amount) {
        require(msg.value >= _amount, "The minimum price has not been reached");
        _;
    }
}
