// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC721RoyaltyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import {ERC721PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Tradeable} from "./interfaces/Tradeable.sol";
import {Inheritable} from "./interfaces/Inheritable.sol";

contract KazenoreiNFT is Tradeable, Inheritable, ERC721RoyaltyUpgradeable, ERC721PausableUpgradeable, ERC721URIStorageUpgradeable, OwnableUpgradeable {
    error ERC721TokenAlreadyOwned(uint256 tokenId);
    error CannotRevokeApprovalWhileInheritorExists(address operator);

    event InheritorSet(address indexed tokenOwner, address indexed inheritor);
    event InheritanceComplete(address indexed tokenOwner, address indexed inheritor);

    string private _baseURIValue;
    address private _inheritanceBroker;
    address private _tradingBroker;

    function initialize(string memory nftName_, string memory nftSymbol_, string memory baseURI_) public initializer {
        __KazenoreiNFT_init(nftName_, nftSymbol_, baseURI_);
    }

    function __KazenoreiNFT_init(string memory nftName_, string memory nftSymbol_, string memory baseURI_) internal onlyInitializing {
        __ERC721_init(nftName_, nftSymbol_);
        __Ownable_init(_msgSender());
        
        _baseURIValue = baseURI_;
    }

    /**
     * @dev Requires that the token is not owned by anyone.
     * Reverts if the token is already owned.
     * 
     * @param tokenId The ID of the token to check ownership for.
     */
    function _requireNotOwned(uint256 tokenId) internal view {
        address owner = _ownerOf(tokenId);
        if (owner != address(0)) {
            revert ERC721TokenAlreadyOwned(tokenId);
        }
    }

    // Override _update to resolve inheritance conflict
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721PausableUpgradeable, ERC721Upgradeable) returns (address) {
        // Upon transfer, reset the royalty for the token
        // This is necessary to ensure that the inheritor does not inherit the previous owner's royalty settings
        _resetTokenRoyalty(tokenId);

        return super._update(to, tokenId, auth);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIValue;
    }

    /// @inheritdoc IERC721
    function isApprovedForAll(address owner, address operator) public view override(ERC721Upgradeable, IERC721) returns (bool) {
        if (operator == address(0)) {
            return false; // No operator can be approved for the zero address
        }
        
        return super.isApprovedForAll(owner, operator) || (operator == _inheritanceBroker) || (operator == _tradingBroker);
    }

    // Override supportsInterface to resolve inheritance conflict
    function supportsInterface(bytes4 interfaceId) public view override(ERC721RoyaltyUpgradeable, ERC721URIStorageUpgradeable, ERC721Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId) || 
               interfaceId == type(Inheritable).interfaceId || 
               interfaceId == type(Tradeable).interfaceId;
    }

    /// @inheritdoc ERC721URIStorageUpgradeable
    function tokenURI(uint256 tokenId) public view override(ERC721URIStorageUpgradeable, ERC721Upgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function setPaused(bool flag_) public onlyOwner {
        flag_ ? _pause() : _unpause();
    }

    function setInheritanceBroker(address broker_) public override(Inheritable) onlyOwner {
        _inheritanceBroker = broker_;
    }

    function setTradingBroker(address broker_) public override(Tradeable) onlyOwner {
        _tradingBroker = broker_;
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner whenNotPaused {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /**
     * @dev Sets the royalty for a specific token.
     * 
     * Requirements:
     * - The caller must be the owner of the token.
     * - The contract must not be paused.
     * 
     * @param tokenId The ID of the token for which the royalty is being set.
     * @param receiver The address that will receive the royalty payments.
     * @param feeNumerator The royalty fee percentage (in basis points).
     */
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public whenNotPaused {
        require(_msgSender() == _requireOwned(tokenId), "SET_ROYALTY_ERROR"); // Royalty: Not the owner of the token
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function setBaseURI(string memory baseURI_) public onlyOwner whenNotPaused {
        _baseURIValue = baseURI_;
    }

    function mint(address to, uint256 tokenId, string memory tokenURI_) public onlyOwner {
        _requireNotOwned(tokenId);
        _safeMint(to, tokenId);

        if(bytes(tokenURI_).length > 0) {
            _setTokenURI(tokenId, tokenURI_);
        }
    }

    /// @inheritdoc ERC721Upgradeable
    function setApprovalForAll(address operator, bool approved) public whenNotPaused override(ERC721Upgradeable, IERC721) {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /// @inheritdoc IERC721
    function approve(address to, uint256 tokenId) public whenNotPaused override(ERC721Upgradeable, IERC721) {
        super.approve(to, tokenId);
    }
    
    /**
     * @dev Burns a specific token.
     * Requirements:
     * - The caller must be the owner of the token.
     * 
     * @param tokenId The ID of the token to burn.
     */
    function burn(uint256 tokenId) public whenNotPaused {
        require(_msgSender() == _requireOwned(tokenId), "UNAUTHORIZED_BURN_ERROR");
        _resetTokenRoyalty(tokenId);
        _setTokenURI(tokenId, "");
        _burn(tokenId);
    }
}
