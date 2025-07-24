// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC721RoyaltyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import {ERC721PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract KazenoreiNFT is ERC721RoyaltyUpgradeable, ERC721PausableUpgradeable, ERC721URIStorageUpgradeable, OwnableUpgradeable {
    error ERC721TokenAlreadyOwned(uint256 tokenId);
    error CannotRevokeApprovalWhileInheritorExists(address operator);

    event InheritorSet(address indexed tokenOwner, address indexed inheritor);
    event InheritanceComplete(address indexed tokenOwner, address indexed inheritor);

    // state 1
    mapping(address => address) private _inheritors;

    // state 2
    string private _baseURIValue;

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
        // TODO: Force Royalty charging, if set
        return super._update(to, tokenId, auth);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIValue;
    }

    // Override supportsInterface to resolve inheritance conflict
    function supportsInterface(bytes4 interfaceId) public view override(ERC721RoyaltyUpgradeable, ERC721URIStorageUpgradeable, ERC721Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc ERC721URIStorageUpgradeable
    function tokenURI(uint256 tokenId) public view override(ERC721URIStorageUpgradeable, ERC721Upgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function setPaused(bool flag_) public onlyOwner {
        flag_ ? _pause() : _unpause();
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
        // Prevent the token owner from revoking approval with contract owner if the inheritor exists
        // This is to ensure that the inheritor can still obtain the tokens after the owner's death
        if(!approved && _inheritors[_msgSender()] != address(0) && operator == owner()) {
            revert CannotRevokeApprovalWhileInheritorExists(operator);
        }

        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /// @inheritdoc IERC721
    function approve(address to, uint256 tokenId) public whenNotPaused override(ERC721Upgradeable, IERC721) {
        super.approve(to, tokenId);
    }

    /**
     * @dev Sets the inheritor for the token owner.
     * This allows the owner to specify an address that will inherit the token ownership in case of death.
     * 
     * Requirements:
     * - The caller must be a token owner.
     * 
     * @param inheritor The address that will inherit the token ownership in case of the owner's death. 
     * If set to address(0), it will clear the previous inheritor.
     */
    function setInheritor(address inheritor) public whenNotPaused {
        address tokenOwner = _msgSender();

        require(balanceOf(tokenOwner) > 0, "NO_EXISTING_TOKEN");

        if(inheritor == address(0)) {
            delete _inheritors[tokenOwner];
            setApprovalForAll(owner(), false);
        } else {
            _inheritors[tokenOwner] = inheritor;
        }

        emit InheritorSet(tokenOwner, inheritor);
    }
    
    /**
     * @dev Gets the inheritor for the specified token owner.
     * This function allows anyone to query the inheritor address for a given token owner.
     * 
     * Requirements:
     * - The token owner must have set an inheritor.
     * 
     * @param tokenOwner The address of the token owner whose inheritor is being queried.
     * 
     * @return The address of the inheritor for the specified token owner.
     */
    function getInheritor(address tokenOwner) external view returns (address) {
        return _inheritors[tokenOwner];
    }

    /**
     * @dev Transfers the ownership of specified token IDs from the token owner to their inheritor.
     * This function allows the inheritor to gain ownership of the tokens in case of the owner's death.
     * Note that all token with specified royalty will be reset to default after the transfer.
     * 
     * Requirements:
     * - The caller must be the contract owner.
     * - The token owner must have set an inheritor.
     * 
     * @param tokenOwner The address of the token owner whose tokens are being transferred.
     * @param tokenIds An array of token IDs to be transferred to the inheritor.
     */
    function transferInheritance(address tokenOwner, uint256[] memory tokenIds) public onlyOwner whenNotPaused {
        require(tokenIds.length > 0 && tokenIds.length < 51, "BATCH_TRANSFER_MAX_50");

        address inheritor = _inheritors[tokenOwner];
        require(inheritor != address(0), "INHERITOR_NOT_SET"); // Royalty: Inheritor not set

        // Ensure that the contract owner is approved for all tokens of the token owner
        // This is necessary to allow the contract owner to transfer tokens on behalf of the token owner
        if (!isApprovedForAll(tokenOwner, owner())) {
            _setApprovalForAll(tokenOwner, owner(), true);
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (tokenOwner == _requireOwned(tokenIds[i])) {
                safeTransferFrom(tokenOwner, inheritor, tokenIds[i]);
                _resetTokenRoyalty(tokenIds[i]);
            }
        }

        if( balanceOf(tokenOwner) == 0 ) {
            delete _inheritors[tokenOwner];
            _setApprovalForAll(tokenOwner, owner(), false);
            emit InheritanceComplete(tokenOwner, inheritor);
        }
    }

    /**
     * @dev Burns a specific token.
     * Requirements:
     * - The caller must be the owner of the token.
     * 
     * @param tokenId The ID of the token to burn.
     */
    function burn(uint256 tokenId) public {
        require(_msgSender() == _requireOwned(tokenId), "UNAUTHORIZED_BURN_ERROR");
        _burn(tokenId);
        _resetTokenRoyalty(tokenId);
        _setTokenURI(tokenId, "");
    }
}
