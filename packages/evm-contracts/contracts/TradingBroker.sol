// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Tradeable} from "./interfaces/Tradeable.sol";
import {ITradingBroker} from "./interfaces/ITradingBroker.sol";

import "forge-std/console.sol";

contract TradingBroker is ERC165, Ownable, Pausable, ITradingBroker {
    using Math for uint256;

    //============================================//
    //                Definitions                 //
    //============================================//
    struct BuyCommitment {
        bytes32 commitMsg;
        uint256 timestamp;
    }

    //============================================//
    //                   Events                   //
    //============================================//
    event TokenForSaleAdded(address indexed contractAddress, uint256 indexed tokenId, uint256 price);
    event TokenForSaleRemoved(address indexed contractAddress, uint256 indexed tokenId_);
    event TokenPurchased(address indexed contractAddress, address indexed buyer, uint256 tokenId, uint256 price);

    //============================================//
    //                  Constants                 //
    //============================================//
    bytes4 private constant INTERFACE_ID_TRADEABLE = type(Tradeable).interfaceId;
    bytes4 private constant INTERFACE_ID_ERC721 = type(IERC721).interfaceId;

    //============================================//
    //              State Variables               //
    //============================================//
    uint256 private _commitWindow = 10 minutes;

    // Lists of tokens for sale, by contract address
    // Contract Address => token ID => Price
    mapping(address => mapping(uint256 => uint256)) private _saleListing;

    // List of allowed contracts that can use this broker
    mapping(address => bool) private _allowedContracts;

    // List of buyer commitments, 1 commitment per buyer per token
    // Contract Address => (token ID => (buyer address => BuyCommitment))
    mapping(address => mapping(address => BuyCommitment)) private _buyCommitments;

    // Tracking of number of tokens the user has for sale, by contract address
    mapping(address => mapping(address => uint256)) private _tokensOnSale;
    
    constructor() Ownable(msg.sender) {
        
    }


    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(ITradingBroker).interfaceId;
    }

    function _requireAllowedContract(address contractAddress_) internal view {
        require(_allowedContracts[contractAddress_], "Not an allowed contract");
    }

    function _requireTokenForSale(address contractAddress_, uint256 tokenId_) internal view {
        require(_saleListing[contractAddress_][tokenId_] > 0, "Token is not for sale");
    }

    /**
     * @dev Pauses or Un-Pauses the contract
     * @param flag_ flag to pause or unpause the contract
     */
    function setPaused(bool flag_) public onlyOwner {
        flag_ ? _pause() : _unpause();
    }

    /**
     * @dev Modifies the buy commit window time
     */
    function setCommitWindow(uint256 commitWindow_) public onlyOwner {
        require(commitWindow_ > 2 minutes, "Commit window too low");
        _commitWindow = commitWindow_;
    }

    /**
     * @dev Add or removes the contract to be managed by this broker
     * @dev Contract address must implement IERC721 interface
     * @dev Contract address must implement Tradeable interface
     */
    function addManagedContract(address contractAddress_, bool isManaged_) public onlyOwner {
        require(contractAddress_ != address(0), "Invalid contract address");

        // Check if contractAddress supports ERC721 interface via ERC165
        require(
            IERC165(contractAddress_).supportsInterface(INTERFACE_ID_ERC721),
            "Contract is not ERC721"
        );

        // Check if contractAddress supports Inheritable interface via ERC165
        require(
            IERC165(contractAddress_).supportsInterface(INTERFACE_ID_TRADEABLE),
            "Contract does not support Tradeable interface"
        );

        _allowedContracts[contractAddress_] = isManaged_;
    }

    /**
     * @dev Flags the token for sale with given price
     * 
     *      Emits TokenForSaleAdded event.
     * 
     * @dev Caller must be the token owner from the given contract address
     */
    function setTokenForSale(address contractAddress_, uint256 tokenId_, uint256 price_) public whenNotPaused {
        _requireAllowedContract(contractAddress_);

        require(price_ > 0, "Price must be greater than zero");

        address tokenOwner = IERC721(contractAddress_).ownerOf(tokenId_);
        require(tokenOwner == _msgSender(), "Not the owner of the token");

        _saleListing[contractAddress_][tokenId_] = price_;
        _tokensOnSale[contractAddress_][tokenOwner] = _tokensOnSale[contractAddress_][tokenOwner].saturatingAdd(1);

        emit TokenForSaleAdded(contractAddress_, tokenId_, price_);
    }

    /**
     * @dev Removes the token for sale status
     * 
     *      Emits TokenForSaleRemoved event.
     * 
     * @dev Caller must be the token owner from the given contract address
     */
    function revokeTokenForSale(address contractAddress_, uint256 tokenId_) public {
        _requireAllowedContract(contractAddress_);

        address caller =  _msgSender();

        address tokenOwner = IERC721(contractAddress_).ownerOf(tokenId_);
        require(caller == tokenOwner || caller == contractAddress_, "Unauthorized to delist token");

        // Remove the listing
        delete _saleListing[contractAddress_][tokenId_];

        _tokensOnSale[contractAddress_][tokenOwner] = _tokensOnSale[contractAddress_][tokenOwner].saturatingSub(1);
        
        // Emit event for sale
        emit TokenForSaleRemoved(contractAddress_, tokenId_);
    }

    /**
     * @dev Checks if token ID from contract address is for sale
     * @param contractAddress_ Address of a managed contract
     * @param tokenId_ Token ID to inquire
     */
    function isTokenForSale(address contractAddress_, uint256 tokenId_) public view returns (bool) {
        _requireAllowedContract(contractAddress_);

        return _saleListing[contractAddress_][tokenId_] > 0;
    }

    /**
     * @dev Returns how many tokens does an address has for sale in an NFT contract
     * @param contractAddress_ Address of a managed contract
     * @param owner_ Wallet address of owner
     */
    function tokensForSale(address contractAddress_, address owner_) public view returns (uint256) {
        _requireAllowedContract(contractAddress_);

        return _tokensOnSale[contractAddress_][owner_];
    }

    /**
     * @dev Gets the price of NFT token that is for sale
     * @param contractAddress_ Address of a managed contract
     * @param tokenId_ Token ID to inquire the price with
     */
    function getTokenPrice(address contractAddress_, uint256 tokenId_) public view returns (uint256) {
        uint256 price = _saleListing[contractAddress_][tokenId_];

        require(price > 0, "Token is not for sale");

        return price;
    }

    /**
     * @dev Gets the token royalty fee, for public query and for internal calculations
     * @param contractAddress_ Address of a managed contract
     * @param tokenId_ Token ID to inquire the royalty fee with
     * @return address wallet of royalty fee receiver
     * @return uint256 value of royalty fee based on posted price
     */
    function getRoyaltyFee(address contractAddress_, uint256 tokenId_) public view returns (address, uint256) {
        _requireAllowedContract(contractAddress_);

        uint256 price = _saleListing[contractAddress_][tokenId_];

        uint256 royaltyFee = 0;
        address royaltyReceiver = address(0);

        bool hasRoyalty = IERC165(contractAddress_).supportsInterface(type(IERC2981).interfaceId);
        if (hasRoyalty) {
            (address receiver, uint256 amount) = IERC2981(contractAddress_).royaltyInfo(tokenId_, price);
            
            royaltyFee = amount;
            royaltyReceiver = receiver;
        }

        return (royaltyReceiver, royaltyFee);
    }

    /**
     * Sets a buy commit for the user. Only single buy commit per contract is allowed at a time for any user
     * and is set to expire within commit window (configured) from blockchain's current time. This means that 
     * only single token buy can be reserved. User must commit and perform the buy transaction after to consume
     * the buy commitment.
     * 
     * @dev     Any succeeding commit using the same contract will overwrite the previous from same user. This is
     *          to prevent front-running attacks.
     * 
     * @param contractAddress_ Address of a managed contract
     * @param commitMsg_ User signed commit message
     */
    function commitBuy(address contractAddress_, bytes32 commitMsg_) public whenNotPaused {
        _requireAllowedContract(contractAddress_);

        address buyer = _msgSender();

        BuyCommitment storage commitment = _buyCommitments[contractAddress_][buyer];

        require(commitment.commitMsg == bytes32(0) || 
            commitment.timestamp == 0 || 
            commitment.timestamp + _commitWindow < block.timestamp, "Commitment exists");

        _buyCommitments[contractAddress_][buyer] = BuyCommitment({
            commitMsg: commitMsg_,
            timestamp: block.timestamp
        });
    }

    /**
     * Performs buy to the desired token. Will throw a revert if no commitment for the token ID is sent first.
     * 
     * @dev     This operation will send the payment to owner wallet address. If royalty fee is present, it will be deducted accordingly
     *          and be sent to the royalty receiver.
     * 
     *          Emits TokenPurchased event.
     * 
     * @param contractAddress_ Address of a managed contract
     * @param tokenId_ Token ID to buy
     */
    function buyToken(address contractAddress_, uint256 tokenId_) public payable whenNotPaused {
        _requireAllowedContract(contractAddress_);
        _requireTokenForSale(contractAddress_, tokenId_);

        address tokenOwner = IERC721(contractAddress_).ownerOf(tokenId_);

        require(IERC721(contractAddress_).isApprovedForAll(tokenOwner, address(this)), "Contract does not approve broker");

        uint256 price = getTokenPrice(contractAddress_, tokenId_);

        // Get royalty fee if applicable
        (address royaltyReceiver, uint256 royaltyAmount) = getRoyaltyFee(contractAddress_, tokenId_);

        uint256 payment = msg.value;
        address payer = _msgSender();

        require(payment >= price, "Insufficient payment");
        require(tokenOwner != payer, "Cannot buy your own token");

        uint256 paymentToSeller = price - royaltyAmount;

        // Check buyer's commitment
        BuyCommitment storage commitment = _buyCommitments[contractAddress_][payer];
        
        require(keccak256(abi.encodePacked(payer, price, contractAddress_, tokenId_)) == commitment.commitMsg, "Invalid commitment");
        require(commitment.timestamp + _commitWindow > block.timestamp, "No Commitment or expired");
        
        // Transfer the token to the buyer
        IERC721(contractAddress_).safeTransferFrom(tokenOwner, payer, tokenId_);

        // Transfer the payment to the seller
        payable(tokenOwner).transfer(paymentToSeller);

        // Transfer the royalty to the royalty receiver
        if (royaltyReceiver != address(0) && royaltyAmount > 0) {
            payable(royaltyReceiver).transfer(royaltyAmount);
        }

        // Emit event for sale
        emit TokenPurchased(contractAddress_, payer, tokenId_, price);

        // Reset the commitment
        delete _buyCommitments[contractAddress_][payer];
    }
}