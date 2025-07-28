import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Tradeable} from "./interfaces/Tradeable.sol";

contract TradingBroker is Ownable, Pausable {
    using SafeMathUpgradeable for uint256;

    struct BuyCommitment {
        bytes32 commitMsg;
        uint256 timestamp;
    }

    event TokenForSale(address indexed contractAddress, uint256 indexed tokenId, uint256 price);
    event TokenPurchased(address indexed contractAddress, address indexed buyer, uint256 tokenId, uint256 price);

    bytes4 private constant INTERFACE_ID_TRADEABLE = type(Tradeable).interfaceId;
    bytes4 private constant INTERFACE_ID_ERC721 = type(IERC721).interfaceId;

    uint256 private _commitWindow = 10 minutes;

    // Contract Address => token ID => Price
    private mapping(address => mapping(tokenId => price)) private _saleListing;
    private mapping(address => bool) private _allowedContracts;

    private mapping(address => mapping(tokenId => mapping(address => BuyCommitment))) private _buyCommitments;
    
    constructor() Ownable(msg.sender()) {
        
    }

    function _requireAllowedContract(address contractAddress_) internal view {
        require(_allowedContracts[contractAddress_], "Not an allowed contract");
    }

    function _requireTokenForSale(address contractAddress_, uint256 tokenId_) internal view {
        require(_saleListing[contractAddress_][tokenId_] > 0, "Token is not for sale");
    }

    function setPaused(bool flag_) public onlyOwner {
        flag_ ? _pause() : _unpause();
    }

    function setCommitWindow(uint256 commitWindow_) public onlyOwner {
        require(commitWindow_ > 2 minutes, "Commit window too low");
        _commitWindow = commitWindow_;
    }

    function addManagedContract(address contractAddress_, bool isManaged_) public onlyOwner {
        require(contractAddress != address(0), "Invalid contract address");

        // Check if contractAddress supports Inheritable interface via ERC165
        require(
            IERC165(contractAddress_).supportsInterface(INTERFACE_ID_TRADEABLE),
            "Contract does not support Tradeable interface"
        );

        // Check if contractAddress supports ERC721 interface via ERC165
        require(
            IERC165(contractAddress_).supportsInterface(INTERFACE_ID_ERC721),
            "Contract is not ERC721"
        );

        _allowedContracts[contractAddress_] = isManaged_;
    }

    function setTokenForSale(address contractAddress_, uint256 tokenId_, uint256 price_) public whenNotPaused {
        _requireAllowedContract(contractAddress_);

        require(price_ > 0, "Price must be greater than zero");

        address tokenOwner = IERC721(contractAddress_).ownerOf(tokenId_);
        require(tokenOwner == _msgSender(), "Not the owner of the token");

        _saleListing[contractAddress_][tokenId_] = price_;

        emit TokenForSale(contractAddress_, tokenId_, price_);
    }

    function isTokenForSale(address contractAddress_, uint256 tokenId_) public view returns (bool) {
        _requireAllowedContract(contractAddress_);

        return _saleListing[contractAddress_][tokenId_] > 0;
    }

    function getTokenPrice(address contractAddress_, uint256 tokenId_) public view returns (uint256) {
        _requireAllowedContract(contractAddress_);

        uint256 price = _saleListing[contractAddress_][tokenId_];

        require(price > 0, "Token is not for sale");

        (address royaltyReceiver, uint256 royaltyAmount) = getRoyaltyFee(contractAddress_, tokenId_);

        return price + royaltyAmount;
    }

    function getRoyaltyFee(address contractAddress_, uint256 tokenId_) public view returns (address, uint256) {
        _requireAllowedContract(contractAddress_);

        uint256 royaltyFee = 0;
        address royaltyReceiver = address(0);

        bool hasRoyalty = IERC165(contractAddress_).supportsInterface(type(IERC2981).interfaceId);
        if (hasRoyalty) {
            (address receiver, uint256 amount) = IERC2981(contractAddress_).royaltyInfo(tokenId_, price);
            if (receiver != address(0) && amount > 0) {
                royaltyFee = amount;
                royaltyReceiver = receiver;
            }
        }

        return (receiver, royaltyFee);
    }

    function commitBuy(address contractAddress_, uint256 tokenId_, bytes32 commitMsg_) public whenNotPaused {
        _requireAllowedContract(contractAddress_);
        _requireTokenForSale(contractAddress_, tokenId_);

        address buyer = _msgSender();

        BuyCommitment storage commitment = _buyCommitments[contractAddress_][tokenId_][buyer];

        require(commitment.commitMsg == bytes32(0) && commitment.timestamp + _commitWindow < block.timestamp, "Commitment exists");

        _buyCommitments[contractAddress_][tokenId_][buyer] = BuyCommitment({
            commitMsg: commitMsg_,
            timestamp: block.timestamp
        });
    }

    function buyToken(address contractAddress_, uint256 tokenId_) public payable whenNotPaused {
        _requireAllowedContract(contractAddress_);
        _requireTokenForSale(contractAddress_, tokenId_);

        (address royaltyReceiver, uint256 royaltyAmount) = getRoyaltyFee(contractAddress_, tokenId_);

        uint256 totalPrice = getTokenPrice(contractAddress_, tokenId_);

        uint256 payment = _msgValue();
        uint256 payer = _msgSender();

        require(payment >= totalPrice, "Insufficient payment");

        address tokenOwner = IERC721(contractAddress_).ownerOf(tokenId_);
        require(tokenOwner != payer, "Cannot buy your own token");

        // Check buyer's commitment
        BuyCommitment storage commitment = _buyCommitments[contractAddress_][tokenId_][payer];

        require(commitment.timestamp + _commitWindow >= block.timestamp, "No Commitment or expired");
        require(keccak256(abi.encodePacked(payer, totalPrice, contractAddress_, tokenId_)) == commitment.commitMsg, "Invalid commitment");

        // Transfer the token to the buyer
        IERC721(contractAddress_).safeTransferFrom(tokenOwner, payer, tokenId_);

        // Transfer the payment to the seller
        payable(tokenOwner).transfer(price.sub(royaltyAmount));

        // Transfer the royalty to the royalty receiver
        if (royaltyReceiver != address(0) && royaltyAmount > 0) {
            payable(royaltyReceiver).transfer(royaltyAmount);
        }

        // Emit event for sale
        emit TokenPurchased(contractAddress_, payer, tokenId_, totalPrice);

        // Remove the listing
        delete _saleListing[contractAddress_][tokenId_];

        // Reset the commitment
        delete _buyCommitments[contractAddress_][tokenId_];
    }
}