// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {InheritanceBroker} from "./InheritanceBroker.sol";
import {KazenoreiNFT} from "./KazenoreiNFT.sol";
import {Test} from "forge-std/Test.sol";

contract TestERC721 is ERC721 {
    constructor() ERC721("TestERC721", "TERC721") {}
}

contract TestERC20 is ERC20, IERC165 {
    constructor() ERC20("TestERC20", "TERC20") {}

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(ERC20).interfaceId;
    }
}

contract TestERC20_2 is ERC20 {
    constructor() ERC20("TestERC20_2", "TERC20_2") {}
}

contract InheritanceBrokerTest is Test {
    using Strings for uint256;
    using Strings for address;

    address constant nftOwner0 = address(0x123);
    address constant nftOwner1 = address(0x456);
    address constant nftOwner2 = address(0x789);

    address constant inheritor1 = address(0x101112);
    address constant inheritor2 = address(0x131415);

    InheritanceBroker private _inheritanceBroker;
    KazenoreiNFT private _nft;

    TestERC721 private _standardERC721;
    TestERC20 private _standardERC20;
    TestERC20_2 private _nonIERC165;

    uint256 private _tokenId = 1;

    function getNftId() internal returns (uint256) {
        return _tokenId++;
    }

    function setUp() public {
        _inheritanceBroker = new InheritanceBroker();

        _nft = new KazenoreiNFT();
        _nft.initialize("KazenoreiNFT", "KNFT", "https://api.kazenorei.com/metadata/");

        _standardERC721 = new TestERC721();
        _standardERC20 = new TestERC20();
        _nonIERC165 = new TestERC20_2();
    }

    function test_InitialOwner() public view {
        address owner = _inheritanceBroker.owner();
        assertEq(
            owner,
            address(this),
            "Initial owner should be the contract deployer"
        );
    }

    function test_PauseAndUnpause() public {
        _inheritanceBroker.setPaused(true);
        assertEq(_inheritanceBroker.paused(), true, "Broker should be paused");

        _inheritanceBroker.setPaused(false);
        assertEq(_inheritanceBroker.paused(), false, "Broker should be unpaused");
    }

    function test_AddManagedContract_NonInheritableERC721_Reverts() public {
        vm.expectRevert("Contract does not support Inheritable interface");
        _inheritanceBroker.addManagedContract(address(_standardERC721), true);
    }

    function test_AddManagedContract_ERC20_Reverts() public {
        vm.expectRevert("Contract is not ERC721");
        _inheritanceBroker.addManagedContract(address(_standardERC20), true);
    }

    function test_AddManagedContract_NonIERC165_Reverts() public {
        vm.expectRevert();
        _inheritanceBroker.addManagedContract(address(_nonIERC165), true);
    }

    function test_AddManagedContract_CompliantNFTs() public {
        _inheritanceBroker.addManagedContract(address(_nft), true);
    }

    function test_SetTokenInheritor_RevertsOnZeroBalance() public {
        address contractAddress = address(_nft);
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        vm.expectRevert("Owner has no tokens");
        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
    }

    function test_SetTokenInheritor_RevertsOnNotAllowedNFTs() public {
        address contractAddress = address(_standardERC721);
        
        vm.expectRevert("Caller is not an allowed contract");
        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
    }

    function test_SetTokenInheritor_RevertsWhenPaused() public {
        address contractAddress = address(_nft);

        _inheritanceBroker.addManagedContract(contractAddress, true);
        _inheritanceBroker.setPaused(true);
        
        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)
        );
        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
    }

    function test_SetTokenInheritor_SucceedsOfTokenOwnerHasBalance() public {
        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        address contractAddress = address(_nft);
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        vm.startPrank(nftOwner1);
        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
        vm.stopPrank();

        assertEq(
            _inheritanceBroker.getInheritor(contractAddress, nftOwner1),
            inheritor1,
            "Inheritor should be set correctly"
        );
    }

    function test_SetTokenInheritor_EmitsEventOnSuccessfulSetOfInheritor() public {
        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        address contractAddress = address(_nft);
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        vm.startPrank(nftOwner1);

        vm.expectEmit(true, true, true, true);
        emit InheritanceBroker.InheritorSet(contractAddress, nftOwner1, inheritor1);

        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
        vm.stopPrank();
    }

    function test_SetTokenInheritor_CanChangeInheritor() public {
        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        address contractAddress = address(_nft);
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        vm.startPrank(nftOwner1);
        
        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
        
        assertEq(
            _inheritanceBroker.getInheritor(contractAddress, nftOwner1),
            inheritor1,
            "Inheritor should be set correctly"
        );

        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor2);

        assertEq(
            _inheritanceBroker.getInheritor(contractAddress, nftOwner1),
            inheritor2,
            "Inheritor should be changed correctly"
        );

        vm.stopPrank();
    }

    function test_SetTokenInheritor_CanRevokeInheritor() public {
        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        address contractAddress = address(_nft);
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        vm.startPrank(nftOwner1);
        
        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
        
        assertEq(
            _inheritanceBroker.getInheritor(contractAddress, nftOwner1),
            inheritor1,
            "Inheritor should be set correctly"
        );

        _inheritanceBroker.setTokenInheritor(contractAddress, address(0));

        assertNotEq(
            _inheritanceBroker.getInheritor(contractAddress, nftOwner1),
            inheritor1,
            "Inheritor should be removed correctly"
        );

        assertEq(
            _inheritanceBroker.getInheritor(contractAddress, nftOwner1),
            address(0),
            "Inheritor should be unset correctly"
        );

        vm.stopPrank();
    }

    function test_SetTokenInheritor_EmitsEventOnInheritanceRevocation() public {
        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        address contractAddress = address(_nft);
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        vm.startPrank(nftOwner1);
        
        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
        
        assertEq(
            _inheritanceBroker.getInheritor(contractAddress, nftOwner1),
            inheritor1,
            "Inheritor should be set correctly"
        );

        vm.expectEmit(true, true, true, true);
        emit InheritanceBroker.InheritorRevoked(contractAddress, nftOwner1, inheritor1);
        _inheritanceBroker.setTokenInheritor(contractAddress, address(0));

        vm.stopPrank();
    }

    function test_transferInheritance_RevertsOnNotAllowedContract() public {
        address contractAddress = address(_standardERC721);
        
        vm.expectRevert("Caller is not an allowed contract");
        _inheritanceBroker.transferInheritance(contractAddress, nftOwner1, new uint256[](0));
    }

    function test_transferInheritance_RevertsOnZeroTokenOwner() public {
        address contractAddress = address(_nft);
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        vm.expectRevert("Invalid token owner address");
        _inheritanceBroker.transferInheritance(contractAddress, address(0), new uint256[](0));
    }

    function test_transferInheritance_RevertsOnBrokerNotApproved() public {
        address contractAddress = address(_nft);
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        vm.expectRevert("Contract does not approve broker");
        _inheritanceBroker.transferInheritance(contractAddress, nftOwner1, new uint256[](0));
    }

    function test_transferInheritance_RevertsOnEmptyTokenIds() public {
        address contractAddress = address(_nft);
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        _nft.setInheritanceBroker(address(_inheritanceBroker));
        _nft.mint(nftOwner1, getNftId(), "");

        vm.startPrank(nftOwner1);
        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
        vm.stopPrank();

        vm.expectRevert("TOKENS_LEN_MIN_1_MAX_50");
        _inheritanceBroker.transferInheritance(contractAddress, nftOwner1, new uint256[](0));
    }

    function test_transferInheritance_RevertsOnOverSizedTokenIds() public {
        address contractAddress = address(_nft);
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        _nft.setInheritanceBroker(address(_inheritanceBroker));
        _nft.mint(nftOwner1, getNftId(), "");

        vm.startPrank(nftOwner1);
        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
        vm.stopPrank();

        vm.expectRevert("TOKENS_LEN_MIN_1_MAX_50");
        _inheritanceBroker.transferInheritance(contractAddress, nftOwner1, new uint256[](51));
    }

    function test_transferInheritance_RevertsWhenNoInheritorSet() public {
        address contractAddress = address(_nft);
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        _nft.setInheritanceBroker(address(_inheritanceBroker));
        _nft.mint(nftOwner1, getNftId(), "");

        vm.expectRevert("INHERITOR_NOT_SET");
        _inheritanceBroker.transferInheritance(contractAddress, nftOwner1, new uint256[](1));
    }

    function test_transferInheritance_RevertsWhenPaused() public {
        address contractAddress = address(_nft);
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        _nft.setInheritanceBroker(address(_inheritanceBroker));
        _nft.mint(nftOwner1, getNftId(), "");

        vm.startPrank(nftOwner1);
        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
        vm.stopPrank();

        _inheritanceBroker.setPaused(true);

        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)
        );
        _inheritanceBroker.transferInheritance(contractAddress, nftOwner1, new uint256[](1));
    }

    function test_transferInheritance_TransfersTokensToInheritor() public {
        address contractAddress = address(_nft);
        uint256 tokenId = getNftId();
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        _nft.setInheritanceBroker(address(_inheritanceBroker));
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
        vm.stopPrank();

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.expectEmit(true, true, true, true);
        emit InheritanceBroker.InheritanceComplete(contractAddress, nftOwner1, inheritor1);
        _inheritanceBroker.transferInheritance(contractAddress, nftOwner1, tokenIds);

        assertEq(
            _nft.ownerOf(tokenId),
            inheritor1,
            "Token should be transferred to the inheritor"
        );
    }

    function test_transferInheritance_CanPartiallyTransferTokens() public {
        address contractAddress = address(_nft);
        uint256 tokenId1 = getNftId();
        uint256 tokenId2 = getNftId();
        uint256 tokenId3 = getNftId();
        
        _inheritanceBroker.addManagedContract(contractAddress, true);

        _nft.setInheritanceBroker(address(_inheritanceBroker));
        _nft.mint(nftOwner1, tokenId1, "");
        _nft.mint(nftOwner1, tokenId2, "");
        _nft.mint(nftOwner1, tokenId3, "");

        vm.startPrank(nftOwner1);
        _inheritanceBroker.setTokenInheritor(contractAddress, inheritor1);
        vm.stopPrank();

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        vm.expectEmit(false, false, false, false);
        _inheritanceBroker.transferInheritance(contractAddress, nftOwner1, tokenIds);

        assertEq(
            _nft.ownerOf(tokenId1),
            inheritor1,
            "First token should be transferred to the inheritor"
        );
        
        assertEq(
            _nft.ownerOf(tokenId2),
            inheritor1,
            "Second token should be transferred to the inheritor"
        );

        assertEq(
            _nft.ownerOf(tokenId3),
            nftOwner1,
            "Thrird token should remain with the original owner"
        );

        tokenIds = new uint256[](1);
        tokenIds[0] = tokenId3;

        vm.expectEmit(true, true, true, true);
        emit InheritanceBroker.InheritanceComplete(contractAddress, nftOwner1, inheritor1);
        _inheritanceBroker.transferInheritance(contractAddress, nftOwner1, tokenIds);
    }
}