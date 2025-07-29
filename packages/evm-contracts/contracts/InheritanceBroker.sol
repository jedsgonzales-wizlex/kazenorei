// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Inheritable} from "./interfaces/Inheritable.sol";

contract InheritanceBroker is Ownable, Pausable {
    using Math for uint256;

    bytes4 constant INTERFACE_ID_INHERITABLE = type(Inheritable).interfaceId;
    bytes4 constant INTERFACE_ID_ERC721 = type(IERC721).interfaceId;

    // token address => token owner address => inheritor address
    // This allows for multiple tokens to have different inheritors
    mapping(address => mapping(address => address)) private _inheritors;

    mapping(address => bool) private _allowedContracts;

    event InheritorSet(address indexed contractAddress, address indexed tokenOwner, address indexed inheritor);
    event InheritorRevoked(address indexed contractAddress, address indexed tokenOwner, address indexed inheritor);
    event InheritanceComplete(address indexed contractAddress, address indexed tokenOwner, address indexed inheritor);

    constructor() Ownable(msg.sender) {
        
    }

    function setPaused(bool flag_) public onlyOwner {
        flag_ ? _pause() : _unpause();
    }

    function addManagedContract(address contractAddress_, bool isManaged_) public onlyOwner {
        require(contractAddress_ != address(0), "Invalid contract address");

        // Check if contractAddress supports ERC721 interface via ERC165
        require(
            IERC165(contractAddress_).supportsInterface(INTERFACE_ID_ERC721),
            "Contract is not ERC721"
        );

        // Check if contractAddress supports Inheritable interface via ERC165
        require(
            IERC165(contractAddress_).supportsInterface(INTERFACE_ID_INHERITABLE),
            "Contract does not support Inheritable interface"
        );

        _allowedContracts[contractAddress_] = isManaged_;
    }

    function setTokenInheritor(address contractAddress_, address inheritor_) public whenNotPaused {
        address tokenOwner = _msgSender();

        require(_allowedContracts[contractAddress_], "Caller is not an allowed contract");
        require(IERC721(contractAddress_).balanceOf(tokenOwner) > 0, "Owner has no tokens");

        if(inheritor_ == address(0)) {
            // If inheritor is set to zero address, remove the inheritor
            address existingInheritor = _inheritors[contractAddress_][tokenOwner];
            require(existingInheritor != address(0), "No inheritor set to revoke");

            delete _inheritors[contractAddress_][tokenOwner];
            emit InheritorRevoked(contractAddress_, tokenOwner, existingInheritor);
        } else {
            _inheritors[contractAddress_][tokenOwner] = inheritor_;
            emit InheritorSet(contractAddress_, tokenOwner, inheritor_);
        }
    }

    function getInheritor(address contractAddress_, address tokenOwner_) external view returns (address) {
        return _inheritors[contractAddress_][tokenOwner_];
    }

    function transferInheritance(address contractAddress_, address tokenOwner_, uint256[] memory tokenIds_) public whenNotPaused onlyOwner {
        require(_allowedContracts[contractAddress_], "Caller is not an allowed contract");
        require(tokenOwner_ != address(0), "Invalid token owner address");
        require(IERC721(contractAddress_).isApprovedForAll(tokenOwner_, address(this)), "Contract does not approve broker");
        require(tokenIds_.length > 0 && tokenIds_.length < 51, "TOKENS_LEN_MIN_1_MAX_50");

        address inheritor = _inheritors[contractAddress_][tokenOwner_];
        
        require(inheritor != address(0), "INHERITOR_NOT_SET");

        // Logic to transfer ownership or rights to the inheritor
        // This would typically involve calling a function on the contract at contractAddress
        // that handles the inheritance logic.
        
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            if (tokenOwner_ == IERC721(contractAddress_).ownerOf(tokenIds_[i])) {
                IERC721(contractAddress_).safeTransferFrom(tokenOwner_, inheritor, tokenIds_[i]);
            }
        }

        if( IERC721(contractAddress_).balanceOf(tokenOwner_) == 0 ) {
            delete _inheritors[contractAddress_][tokenOwner_];
            emit InheritanceComplete(contractAddress_, tokenOwner_, inheritor);
        }
    }
}