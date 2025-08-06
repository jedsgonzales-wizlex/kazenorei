// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC721RoyaltyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import {ERC721PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Tradeable} from "./interfaces/Tradeable.sol";
import {Inheritable} from "./interfaces/Inheritable.sol";
import {IInheritanceBroker} from "./interfaces/IInheritanceBroker.sol";
import {ITradingBroker} from "./interfaces/ITradingBroker.sol";

import "forge-std/console.sol";

contract KazenoreiNFT is
    Tradeable,
    Inheritable,
    ERC721RoyaltyUpgradeable,
    ERC721PausableUpgradeable,
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable
{
    using SafeCast for uint256;

    error ERC721TokenAlreadyOwned(uint256 tokenId);
    error CannotRevokeApprovalWhileInheritorExists(address operator);

    event InheritorSet(address indexed tokenOwner, address indexed inheritor);
    event InheritanceComplete(
        address indexed tokenOwner,
        address indexed inheritor
    );

    string private _baseURIValue;
    address private _inheritanceBroker;
    address private _tradingBroker;

    function initialize(
        string memory nftName_,
        string memory nftSymbol_,
        string memory baseURI_
    ) public initializer {
        __KazenoreiNFT_init(nftName_, nftSymbol_, baseURI_);
    }

    function __KazenoreiNFT_init(
        string memory nftName_,
        string memory nftSymbol_,
        string memory baseURI_
    ) internal onlyInitializing {
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

    // Override _update to resolve inheritance conflict and implement new manuevers
    function _update(
        address to_,
        uint256 tokenId_,
        address auth_
    )
        internal
        override(ERC721PausableUpgradeable, ERC721Upgradeable)
        returns (address)
    {
        address from = super._update(to_, tokenId_, auth_);

        // delist from trading broker if listed for sale
        if (
            _tradingBroker != address(0) &&
            ITradingBroker(_tradingBroker).isTokenForSale(
                address(this),
                tokenId_
            )
        ) {
            ITradingBroker(_tradingBroker).revokeTokenForSale(
                address(this),
                tokenId_
            );
        }

        // if moving from contract owner account to another, set the royalty
        if (from == owner()) {
            (address royaltyReceiver, uint256 royaltyFee) = royaltyInfo(
                tokenId_,
                _feeDenominator()
            );
            if (royaltyFee > 0) {
                // set default royalty for owner granted token
                _setTokenRoyalty(tokenId_, to_, royaltyFee.toUint96());
            }
        }

        return from;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIValue;
    }

    /// @inheritdoc IERC721
    function isApprovedForAll(
        address owner,
        address operator
    ) public view override(ERC721Upgradeable, IERC721) returns (bool) {
        if (operator == address(0)) {
            return false; // No operator can be approved for the zero address
        }

        return
            super.isApprovedForAll(owner, operator) ||
            (operator == _inheritanceBroker &&
                IInheritanceBroker(_inheritanceBroker).getInheritor(
                    address(this),
                    owner
                ) !=
                address(0)) ||
            (operator == _tradingBroker &&
                ITradingBroker(_tradingBroker).tokensForSale(
                    address(this),
                    owner
                ) >
                0);
    }

    // Override supportsInterface to resolve inheritance conflict
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(
            ERC721RoyaltyUpgradeable,
            ERC721URIStorageUpgradeable,
            ERC721Upgradeable
        )
        returns (bool)
    {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(Inheritable).interfaceId ||
            interfaceId == type(Tradeable).interfaceId;
    }

    /// @inheritdoc ERC721URIStorageUpgradeable
    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721URIStorageUpgradeable, ERC721Upgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function setPaused(bool flag_) public onlyOwner {
        flag_ ? _pause() : _unpause();
    }

    function setInheritanceBroker(
        address broker_
    ) public override(Inheritable) onlyOwner {
        if (broker_ != address(0)) {
            require(
                IERC165(broker_).supportsInterface(
                    type(IInheritanceBroker).interfaceId
                ),
                "Not an Inheritance Broker"
            );
            require(
                Ownable(broker_).owner() == _msgSender(),
                "Diff Contract Owners Disallowed"
            );
        }

        _inheritanceBroker = broker_;
    }

    function setTradingBroker(
        address broker_
    ) public override(Tradeable) onlyOwner {
        if (broker_ != address(0)) {
            require(
                IERC165(broker_).supportsInterface(
                    type(ITradingBroker).interfaceId
                ),
                "Not a Trading Broker"
            );
            require(
                Ownable(broker_).owner() == _msgSender(),
                "Diff Contract Owners Disallowed"
            );
        }

        _tradingBroker = broker_;
    }

    function setDefaultRoyalty(
        uint96 feeNumerator
    ) public onlyOwner whenNotPaused {
        _setDefaultRoyalty(owner(), feeNumerator);
    }

    /**
     * @dev Sets the royalty for a specific token.
     *
     * Requirements:
     * - The caller must be the owner of the contract (administered).
     * - The contract must not be paused.
     *
     * @param tokenId The ID of the token for which the royalty is being set.
     * @param receiver The address that will receive the royalty payments.
     * @param feeNumerator The royalty fee percentage (in basis points).
     */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) public whenNotPaused onlyOwner {
        _requireOwned(tokenId);
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function setBaseURI(string memory baseURI_) public onlyOwner whenNotPaused {
        _baseURIValue = baseURI_;
    }

    function mint(
        address to_,
        uint256 tokenId_,
        string memory tokenURI_
    ) public onlyOwner {
        _requireNotOwned(tokenId_);
        _safeMint(to_, tokenId_);

        address owner = _msgSender();

        if (to_ != owner) {
            (address royaltyReceiver, uint256 royaltyFee) = royaltyInfo(
                tokenId_,
                _feeDenominator()
            );
            if (royaltyFee > 0) {
                // set default royalty for the newly minted token
                _setTokenRoyalty(tokenId_, to_, royaltyFee.toUint96());
            }
        }

        if (bytes(tokenURI_).length > 0) {
            _setTokenURI(tokenId_, tokenURI_);
        }
    }

    /// @inheritdoc ERC721Upgradeable
    function setApprovalForAll(
        address operator,
        bool approved
    ) public override(ERC721Upgradeable, IERC721) whenNotPaused {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /// @inheritdoc IERC721
    function approve(
        address to,
        uint256 tokenId
    ) public override(ERC721Upgradeable, IERC721) whenNotPaused {
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
        require(
            _msgSender() == _requireOwned(tokenId),
            "UNAUTHORIZED_BURN_ERROR"
        );
        _resetTokenRoyalty(tokenId);
        _setTokenURI(tokenId, "");
        _burn(tokenId);
    }
}
