// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {KazenoreiNFT} from "./KazenoreiNFT.sol";
import {Test} from "forge-std/Test.sol";

contract KazenoreiNFTTest is Test {
    using Strings for uint256;
    using Strings for address;

    KazenoreiNFT nft;

    address constant nftOwner0 = address(0x123);
    address constant nftOwner1 = address(0x456);
    address constant nftOwner2 = address(0x789);

    string constant baseURI = "https://api.kazenorei.com/metadata/";
    string constant nftName = "KazenoreiNFT";
    string constant nftSymbol = "KNFT";

    uint256 private _tokenId = 1;

    function getNftId() internal returns (uint256) {
        return _tokenId++;
    }

    function setUp() public {
        nft = new KazenoreiNFT();
        nft.initialize(nftName, nftSymbol, baseURI);
    }

    function test_Initialize() public view {
        string memory name = nft.name();
        string memory symbol = nft.symbol();

        assertEq(
            keccak256(abi.encodePacked(name)),
            keccak256(abi.encodePacked(nftName)),
            string.concat("Name should be ", nftName)
        );
        assertEq(
            keccak256(abi.encodePacked(symbol)),
            keccak256(abi.encodePacked(nftSymbol)),
            string.concat("Symbol should be ", nftSymbol)
        );
    }

    function test_InitialOwner() public view {
        address owner = nft.owner();
        assertEq(
            owner,
            address(this),
            "Initial owner should be the contract deployer"
        );
    }

    function test_MintNFT() public {
        nft.mint(
            nftOwner0,
            getNftId(),
            "https://api.kazenorei.com/metadata/1.json"
        );
        assertEq(
            nft.balanceOf(nftOwner0),
            1,
            "Balance should be 1 after minting"
        );
    }

    function test_NonOwnerMinting() public {
        vm.startPrank(nftOwner0);
        vm.expectRevert();
        nft.mint(nftOwner1, getNftId(), "");
    }

    function test_MintingWhilePaused() public {
        nft.setPaused(true);
        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)
        );
        nft.mint(nftOwner1, getNftId(), "");
    }

    function test_NFTBaseURI() public {
        uint256 newTokenId = getNftId();
        string memory tokenURI = string(
            abi.encodePacked(baseURI, newTokenId.toString())
        );

        nft.mint(nftOwner1, newTokenId, "");
        assertEq(
            keccak256(abi.encodePacked(nft.tokenURI(newTokenId))),
            keccak256(abi.encodePacked(tokenURI)),
            "Token URI should match based on base URI and token ID"
        );
    }

    function test_NFTTokenURI() public {
        uint256 newTokenId = getNftId();
        string memory tokenURI = string(
            abi.encodePacked("kazenorei-", newTokenId.toString(), ".json")
        );
        string memory fullURI = string(abi.encodePacked(baseURI, tokenURI));

        nft.mint(nftOwner1, newTokenId, tokenURI);
        assertEq(
            keccak256(abi.encodePacked(nft.tokenURI(newTokenId))),
            keccak256(abi.encodePacked(fullURI)),
            "Token URI should match based on base URI and provided token URI"
        );
    }

    function test_PauseAndUnpause() public {
        nft.setPaused(true);
        assertEq(nft.paused(), true, "NFT should be paused");

        nft.setPaused(false);
        assertEq(nft.paused(), false, "NFT should be unpaused");
    }

    function test_TranfersWhilePaused() public {
        uint256 tokenId = getNftId();
        nft.mint(nftOwner1, tokenId, "");

        nft.setPaused(true);
        vm.startPrank(nftOwner1);
        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)
        );
        nft.transferFrom(nftOwner1, nftOwner2, tokenId);
    }

    function test_TokenTransfer() public {
        uint256 tokenId = getNftId();
        nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        nft.transferFrom(nftOwner1, nftOwner2, tokenId);
        vm.stopPrank();

        assertEq(
            nft.ownerOf(tokenId),
            nftOwner2,
            "Token should be transferred to nftOwner2"
        );
    }

    function test_TokenSafeTransfer() public {
        uint256 tokenId = getNftId();
        nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        nft.safeTransferFrom(nftOwner1, nftOwner2, tokenId);
        vm.stopPrank();

        assertEq(
            nft.ownerOf(tokenId),
            nftOwner2,
            "Token should be transferred to nftOwner2"
        );
    }

    function test_UnauthorizedTokenTransfer() public {
        uint256 tokenId = getNftId();
        nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner2);
        vm.expectRevert();
        nft.safeTransferFrom(nftOwner1, nftOwner2, tokenId);
    }

    function test_CantSetDefaultRoyaltyIfPaused() public {
        nft.setPaused(true);
        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)
        );
        nft.setDefaultRoyalty(10_00); // = 10%

        (address receiver, uint256 amount) = nft.royaltyInfo(_tokenId, 10000);

        assertEq(receiver, address(0), "Receiver should be the deployer");
        assertEq(amount, 0, "Royalty fee should be zero");
    }

    function test_ZeroRoyaltyDefault() public {
        nft.setDefaultRoyalty(0);

        (address receiver, uint256 amount) = nft.royaltyInfo(_tokenId, 10000);

        assertEq(receiver, address(this), "Receiver should be the deployer");
        assertEq(amount, 0, "Royalty fee should be zero");
    }

    function test_DefinedDefaultRoyalty() public {
        nft.setDefaultRoyalty(1_00); // = 1% => 1.00 -> 100

        (address receiver, uint256 amount) = nft.royaltyInfo(_tokenId, 10000);

        assertEq(receiver, address(this), "Receiver should be the deployer");
        assertEq(
            amount,
            100,
            string.concat(
                "Royalty fee numerator should be 1% of sale price - ",
                amount.toString()
            )
        );
    }

    function test_CantSetPerTokenRoyaltyIfPaused() public {
        uint256 tokenId = getNftId();

        nft.mint(nftOwner1, tokenId, "");

        nft.setDefaultRoyalty(1_00); // = 1%
        nft.setPaused(true);

        vm.startPrank(nftOwner1); // Next call will be from nftOwner1
        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)
        );
        nft.setTokenRoyalty(tokenId, nftOwner1, 10_00); // = 10%
        vm.stopPrank();

        (address receiver, uint256 amount) = nft.royaltyInfo(tokenId, 10000);

        assertEq(receiver, address(this), "Receiver should be the contract owner");
        assertEq(
            amount,
            100,
            string.concat(
                "Royalty fee should be 1% of sale price as set by default - ",
                amount.toString()
            )
        );
    }

    function test_PerTokenRoyaltyByContractOwner() public {
        uint256 tokenId = getNftId();

        nft.mint(nftOwner1, tokenId, "");

        nft.setDefaultRoyalty(1_00); // = 1%

        nft.setTokenRoyalty(tokenId, nftOwner1, 10_00); // = 10%

        (address receiver, uint256 amount) = nft.royaltyInfo(tokenId, 10_000);

        assertEq(receiver, nftOwner1, "Receiver should be the nftOwner1");
        assertEq(
            amount,
            1_000,
            string.concat(
                "Royalty fee should be 10% of sale price - ",
                amount.toString()
            )
        );
    }

    function test_CantSetTokenRoyaltyWhenNotContractOwner() public {
        uint256 tokenId = getNftId();

        nft.mint(nftOwner1, tokenId, "");

        nft.setDefaultRoyalty(1_00); // = 1%

        vm.startPrank(nftOwner2); // Next call will be from nftOwner1
        
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                nftOwner2
            )
        );
        nft.setTokenRoyalty(tokenId, nftOwner2, 10_00); // = 10%
        vm.stopPrank();

        (address receiver, uint256 amount) = nft.royaltyInfo(tokenId, 10000);

        assertEq(receiver, address(this), "Receiver should be the default");
        assertEq(
            amount,
            100,
            string.concat(
                "Royalty fee should be 1% of sale price as per default set - ",
                amount.toString()
            )
        );
    }

    function test_SingleApproval() public {
        uint256 tokenId = getNftId();
        nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        nft.approve(nftOwner2, tokenId);
        vm.stopPrank();

        assertEq(
            nft.getApproved(tokenId),
            nftOwner2,
            "nftOwner2 should be approved for the token"
        );
    }

    function test_SingleApprovalWhenPaused() public {
        uint256 tokenId = getNftId();
        nft.mint(nftOwner1, tokenId, "");

        nft.setPaused(true);
        vm.startPrank(nftOwner1);

        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)
        );
        nft.approve(nftOwner2, tokenId);
    }

    function test_MultiApproval() public {
        vm.startPrank(nftOwner1);
        nft.setApprovalForAll(nftOwner2, true);
        vm.stopPrank();

        assertEq(
            nft.isApprovedForAll(nftOwner1, nftOwner2),
            true,
            "nftOwner2 should be approved for all nftOwner1 token"
        );
    }

    function test_MultiApprovalWhenPaused() public {
        nft.setPaused(true);

        vm.startPrank(nftOwner1);
        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)
        );
        nft.setApprovalForAll(nftOwner2, true);
    }

    function test_AllowUsersToBurn() public {
        uint256 tokenId = getNftId();
        nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        nft.burn(tokenId);
        vm.stopPrank();

        assertEq(
            nft.balanceOf(nftOwner1),
            0,
            "Balance should be 0 after burning the token"
        );
    }

    function test_DisallowUsersToBurnWhenPaused() public {
        uint256 tokenId = getNftId();
        nft.mint(nftOwner1, tokenId, "");

        nft.setPaused(true);

        vm.startPrank(nftOwner1);
        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)
        );
        nft.burn(tokenId);
        vm.stopPrank();

        assertEq(
            nft.balanceOf(nftOwner1),
            1,
            "Balance should be 1 after failed burning the token"
        );
    }

    function test_DisallowUsersToBurnIfNotTheOwner() public {
        uint256 tokenId = getNftId();
        nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner2);
        vm.expectRevert(bytes("UNAUTHORIZED_BURN_ERROR"));
        nft.burn(tokenId);
        vm.stopPrank();

        assertEq(
            nft.balanceOf(nftOwner1),
            1,
            "Balance should be 1 after unauthorized burning the token"
        );
    }

    function test_RevokesApprovalWhenTransferred() public {
        uint256 tokenId = getNftId();
        nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        nft.approve(nftOwner2, tokenId);
        nft.transferFrom(nftOwner1, nftOwner2, tokenId);
        vm.stopPrank();

        assertEq(
            nft.getApproved(tokenId),
            address(0),
            "Approval should be revoked after transfer"
        );
    }

    function test_RevokesApprovalForAllOnTokenWhenTransferred() public {
        uint256 tokenId = getNftId();
        nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        nft.setApprovalForAll(nftOwner2, true);
        nft.transferFrom(nftOwner1, nftOwner2, tokenId);
        vm.stopPrank();

        assertEq(
            nft.getApproved(tokenId),
            address(0),
            "Approval should be revoked after transfer"
        );
    }
}
