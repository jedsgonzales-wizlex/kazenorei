// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {TradingBroker} from "./TradingBroker.sol";
import {KazenoreiNFT} from "./KazenoreiNFT.sol";
import {Tradeable} from "./interfaces/Tradeable.sol";

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

contract TestERC721 is ERC721 {
    constructor() ERC721("TestERC721", "TERC721") {}
}

contract TradeableERC721 is ERC721, Tradeable {
    address private _tradingBroker;

    constructor() ERC721("TradeableERC721", "TRDERC721") {}

    function setTradingBroker(address broker_) public override(Tradeable) {
        _tradingBroker = broker_;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(Tradeable).interfaceId;
    }

    function mint(address to, uint256 tokenId) public {
        _safeMint(to, tokenId);
    }
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

contract TradingBrokerTest is Test {
    using Strings for uint256;
    using Strings for address;

    address constant nftBuyer1 = address(0x123);

    address constant nftOwner0 = address(0xabcdef);
    address constant nftOwner1 = address(0x456);
    address constant nftOwner2 = address(0x789);

    TradingBroker private _tradingBroker;
    KazenoreiNFT private _nft;
    TradeableERC721 private _tradeableNft;

    TestERC721 private _standardERC721;
    TestERC20 private _standardERC20;
    TestERC20_2 private _nonIERC165;

    uint256 private _tokenId = 1;

    function getNftId() internal returns (uint256) {
        return _tokenId++;
    }

    function setUp() public {
        _tradingBroker = new TradingBroker();

        _nft = new KazenoreiNFT();
        _nft.initialize("KazenoreiNFT", "KNFT", "https://api.kazenorei.com/metadata/");

        _tradeableNft = new TradeableERC721();

        _standardERC721 = new TestERC721();
        _standardERC20 = new TestERC20();
        _nonIERC165 = new TestERC20_2();
    }

    function test_InitialOwner() public view {
        address owner = _tradingBroker.owner();
        assertEq(
            owner,
            address(this),
            "Initial owner should be the contract deployer"
        );
    }

    function test_PauseAndUnpause() public {
        _tradingBroker.setPaused(true);
        assertEq(_tradingBroker.paused(), true, "Broker should be paused");

        _tradingBroker.setPaused(false);
        assertEq(_tradingBroker.paused(), false, "Broker should be unpaused");
    }

    function test_AddManagedContract_NonTradeableERC721_Reverts() public {
        vm.expectRevert("Contract does not support Tradeable interface");
        _tradingBroker.addManagedContract(address(_standardERC721), true);
    }

    function test_AddManagedContract_ERC20_Reverts() public {
        vm.expectRevert("Contract is not ERC721");
        _tradingBroker.addManagedContract(address(_standardERC20), true);
    }

    function test_AddManagedContract_NonIERC165_Reverts() public {
        vm.expectRevert();
        _tradingBroker.addManagedContract(address(_nonIERC165), true);
    }

    function test_AddManagedContract_CompliantNFTs() public {
        _tradingBroker.addManagedContract(address(_nft), true);
    }

    function test_setTokenForSale_NotAllowedContract_Reverts() public {
        vm.expectRevert("Not an allowed contract");
        _tradingBroker.setTokenForSale(address(_standardERC721), getNftId(), 1 ether);
    }

    function test_setTokenForSale_ZeroPrice_Reverts() public {
        _tradingBroker.addManagedContract(address(_nft), true);
        vm.expectRevert("Price must be greater than zero");
        _tradingBroker.setTokenForSale(address(_nft), getNftId(), 0);
    }

    function test_setTokenForSale_NotOwner_Reverts() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");
        
        vm.startPrank(nftOwner2);

        vm.expectRevert("Not the owner of the token");
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);

        vm.stopPrank();
    }

    function test_setTokenForSale_Success() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        vm.expectEmit(true, true, true, true);
        emit TradingBroker.TokenForSaleAdded(address(_nft), tokenId, 1 ether);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();
    }

    function test_isTokenForSale_canCheckTokenAvailability() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        assertTrue(_tradingBroker.isTokenForSale(address(_nft), tokenId), "Token should be marked for sale");
        assertFalse(_tradingBroker.isTokenForSale(address(_nft), getNftId()), "Token should not be marked for sale");
    }

    function test_getTokenPrice_canRetrievePrice() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        uint256 price = _tradingBroker.getTokenPrice(address(_nft), tokenId);
        assertEq(price, 1 ether, "Price should match the set price");
    }

    function test_getTokenPrice_throwsErrorOnNotForSaleTokens() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");


        vm.expectRevert("Token is not for sale");
        _tradingBroker.getTokenPrice(address(_nft), tokenId);
    }

    function test_getTokenPrice_throwsErrorOnNotForSaleNFT() public {
        vm.expectRevert("Token is not for sale");
        _tradingBroker.getTokenPrice(address(_standardERC721), getNftId());
    }

    function test_getTokenPrice_throwsErrorOnNonNFT() public {
        vm.expectRevert("Token is not for sale");
        _tradingBroker.getTokenPrice(address(_standardERC20), getNftId());
    }

    function test_getRoyaltyFee_throwsErrorOnNonTradeableNFT() public {
        vm.expectRevert("Not an allowed contract");
        _tradingBroker.getRoyaltyFee(address(_standardERC721), getNftId());
    }

    function test_getRoyaltyFee_returnsZeroRoyaltyOnNoRoyaltyContract() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        (address receiver, uint256 fee) = _tradingBroker.getRoyaltyFee(address(_nft), tokenId);
        assertEq(receiver, address(0), "Royalty receiver should be zero address");
        assertEq(fee, 0, "Royalty fee should be zero");
    }

    function test_getRoyaltyFee_returnsDefaultRoyaltyOnContractWithDefaultRoyalty() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        uint256 price = 100 ether;

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");
        _nft.setDefaultRoyalty(5_00); // 5% royalty

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, price);
        vm.stopPrank();

        (address receiver, uint256 fee) = _tradingBroker.getRoyaltyFee(address(_nft), tokenId);
        assertEq(receiver, address(this), "Royalty receiver should be the NFT owner");
        assertEq(fee, 5 ether, "Royalty fee should be 5% of price ether");
    }

    function test_getRoyaltyFee_returnsTokenRoyaltyOnNFTWithAssignedRoyalty() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setDefaultRoyalty(1_00); // 1% royalty

        uint256 price = 100 ether;

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        _nft.setTokenRoyalty(tokenId, nftOwner1, 10_00); // 10% royalty

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, price);
        vm.stopPrank();

        vm.startPrank(nftOwner2);
        (address receiver, uint256 fee) = _tradingBroker.getRoyaltyFee(address(_nft), tokenId);
        assertEq(receiver, nftOwner1, "Royalty receiver should be the NFT owner");
        assertEq(fee, 10 ether, "Royalty fee should be 10% of price ether");
    }

    function test_commitBuy_NotAllowedContract_Reverts() public {
        uint256 tokenId = getNftId();
        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, uint256(1 ether), address(_nft), tokenId));

        vm.expectRevert("Not an allowed contract");
        _tradingBroker.commitBuy(address(_standardERC721), commitMsg);
    }

    function test_commitBuy_AcceptsCommitments() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, uint256(1 ether), address(_nft), tokenId));

        vm.startPrank(nftBuyer1);
        _tradingBroker.commitBuy(address(_nft), commitMsg);
        vm.stopPrank();
    }

    function test_commitBuy_DoesNotAcceptMultipleSameCommitments() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, uint256(1 ether), address(_nft), tokenId));

        vm.startPrank(nftBuyer1);
        _tradingBroker.commitBuy(address(_nft), commitMsg);

        vm.expectRevert("Commitment exists");
        _tradingBroker.commitBuy(address(_nft), commitMsg);
        vm.stopPrank();
    }

    function test_commitBuy_DoesNotAcceptMultipleDiffCommitments() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        bytes32 commitMsg1 = keccak256(abi.encodePacked(nftBuyer1, uint256(1 ether), address(_nft), tokenId));

        vm.startPrank(nftBuyer1);
        _tradingBroker.commitBuy(address(_nft), commitMsg1);

        bytes32 commitMsg2 = keccak256(abi.encodePacked(nftBuyer1, uint256(0.5 ether), address(_nft), tokenId));

        vm.expectRevert("Commitment exists");
        _tradingBroker.commitBuy(address(_nft), commitMsg2);
        vm.stopPrank();
    }

    function test_commitBuy_DoesAcceptCommitmentAfterPreviousExpired() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, uint256(1 ether), address(_nft), tokenId));

        vm.startPrank(nftBuyer1);
        _tradingBroker.commitBuy(address(_nft), commitMsg);

        // Simulate commitment expiration
        vm.warp(block.timestamp + uint256(11 minutes));

        _tradingBroker.commitBuy(address(_nft), commitMsg);
        vm.stopPrank();
    }

    function test_buyToken_NotAllowedContract_Reverts() public {
        vm.expectRevert("Not an allowed contract");
        _tradingBroker.buyToken(address(_standardERC721), getNftId());
    }

    function test_buyToken_NotForSaleToken_Reverts() public {
        _tradingBroker.addManagedContract(address(_nft), true);
        vm.expectRevert("Token is not for sale");
        _tradingBroker.buyToken(address(_nft), getNftId());
    }

    function test_buyToken_NotApprovedBroker_Reverts() public {
        _tradingBroker.addManagedContract(address(_tradeableNft), true);

        uint256 tokenId = getNftId();
        _tradeableNft.mint(nftOwner1, tokenId);

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_tradeableNft), tokenId, 1 ether);
        vm.stopPrank();

        // make commitment
        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, uint256(1 ether), address(_tradeableNft), tokenId));
        vm.startPrank(nftBuyer1);
        _tradingBroker.commitBuy(address(_tradeableNft), commitMsg);

        vm.expectRevert("Contract does not approve broker");
        _tradingBroker.buyToken(address(_tradeableNft), tokenId);
    }

    function test_buyToken_InsufficientPayment_Reverts() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, uint256(1 ether), address(_nft), tokenId));

        vm.startPrank(nftBuyer1);

        _tradingBroker.commitBuy(address(_nft), commitMsg);

        // give buyer some funds
        vm.deal(nftBuyer1, 10 ether);
        
        vm.expectRevert("Insufficient payment");
        _tradingBroker.buyToken{value: 0.5 ether}(address(_nft), tokenId);

        vm.stopPrank();
    }

    function test_buyToken_BuyOwnToken_Reverts() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        bytes32 commitMsg = keccak256(abi.encodePacked(nftOwner1, uint256(1 ether), address(_nft), tokenId));

        vm.startPrank(nftOwner1);

        _tradingBroker.commitBuy(address(_nft), commitMsg);

        // give buyer some funds
        vm.deal(nftOwner1, 10 ether);
        
        vm.expectRevert("Cannot buy your own token");
        _tradingBroker.buyToken{value: 1 ether}(address(_nft), tokenId);

        vm.stopPrank();
    }

    function test_buyToken_BuyingWithoutCommitment_Reverts() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        vm.startPrank(nftBuyer1);

        // give buyer some funds
        vm.deal(nftBuyer1, 10 ether);
        
        vm.expectRevert("Invalid commitment");
        _tradingBroker.buyToken{value: 1 ether}(address(_nft), tokenId);

        vm.stopPrank();
    }

    function test_buyToken_BuyWithExpiredCommitment_Reverts() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, uint256(1 ether), address(_nft), tokenId));

        vm.startPrank(nftBuyer1);

        _tradingBroker.commitBuy(address(_nft), commitMsg);

        // give buyer some funds
        vm.deal(nftBuyer1, 10 ether);

        // buyer was too slow, commitment expired
        vm.warp(block.timestamp + 10 minutes + 1 seconds);
        
        vm.expectRevert("No Commitment or expired");
        _tradingBroker.buyToken{value: 1 ether}(address(_nft), tokenId);

        vm.stopPrank();
    }

    function test_buyToken_SellerGetsEtherOnSuccessfulBuy() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        uint256 initialBalance = address(nftOwner1).balance;

        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, uint256(1 ether), address(_nft), tokenId));

        vm.startPrank(nftBuyer1);

        _tradingBroker.commitBuy(address(_nft), commitMsg);

        // give buyer some funds
        vm.deal(nftBuyer1, 10 ether);
        _tradingBroker.buyToken{value: 1 ether}(address(_nft), tokenId);
        vm.stopPrank();

        uint256 finalBalance = address(nftOwner1).balance;
        assertEq(finalBalance, initialBalance + 1 ether, "Seller should receive the payment");
    }

    function test_buyToken_TransfersTokenToBuyerOnSuccessfulBuy() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, uint256(1 ether), address(_nft), tokenId));

        vm.startPrank(nftBuyer1);

        _tradingBroker.commitBuy(address(_nft), commitMsg);

        // give buyer some funds
        vm.deal(nftBuyer1, 10 ether);
        _tradingBroker.buyToken{value: 1 ether}(address(_nft), tokenId);
        vm.stopPrank();

        address newOwner = _nft.ownerOf(tokenId);
        assertEq(newOwner, nftBuyer1, "Token should be transferred to the buyer");
    }

    function test_buyToken_BrokerEmitsPurchaseEventOnSuccessfulBuy() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, uint256(1 ether), address(_nft), tokenId));

        vm.startPrank(nftBuyer1);

        _tradingBroker.commitBuy(address(_nft), commitMsg);

        // give buyer some funds
        vm.deal(nftBuyer1, 10 ether);

        vm.expectEmit(true, true, true, true);
        emit TradingBroker.TokenPurchased(address(_nft), nftBuyer1, tokenId, uint256(1 ether));
        _tradingBroker.buyToken{value: 1 ether}(address(_nft), tokenId);

        vm.stopPrank();
    }

    function test_buyToken_BrokerEmitsRemovalEventOnSuccessfulBuy() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, 1 ether);
        vm.stopPrank();

        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, uint256(1 ether), address(_nft), tokenId));

        vm.startPrank(nftBuyer1);

        _tradingBroker.commitBuy(address(_nft), commitMsg);

        // give buyer some funds
        vm.deal(nftBuyer1, 10 ether);

        vm.expectEmit(true, true, true, true);
        emit TradingBroker.TokenForSaleRemoved(address(_nft), tokenId);
        _tradingBroker.buyToken{value: 1 ether}(address(_nft), tokenId);

        vm.stopPrank();
    }

    function test_buyToken_DefaultReceiverGetsDefaultRoyaltyOnSuccessfulBuy() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));
        _nft.setDefaultRoyalty(5_00); // 5% royalty

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        uint256 price = 1 ether;

        // send token to another owner
        vm.startPrank(nftOwner1);
       _nft.safeTransferFrom(nftOwner1, nftOwner2, tokenId);
        vm.stopPrank();

        // new owner sets token for sale
        vm.startPrank(nftOwner2);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, price);
        vm.stopPrank();

        (address royaltyReciver, uint256 royaltyFee) = _tradingBroker.getRoyaltyFee(address(_nft), tokenId);

        uint256 initialBalance = address(nftOwner2).balance;
        uint256 royaltyReciverInitialBalance = address(royaltyReciver).balance;

        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, price, address(_nft), tokenId));

        vm.startPrank(nftBuyer1);

        _tradingBroker.commitBuy(address(_nft), commitMsg);

        // give buyer some funds and buy token
        vm.deal(nftBuyer1, 10 ether);

        uint256 buyerBalance = address(nftBuyer1).balance;

        _tradingBroker.buyToken{value: price}(address(_nft), tokenId);
        vm.stopPrank();

        uint256 finalBuyerBalance = address(nftBuyer1).balance;
        uint256 finalBalance = address(nftOwner2).balance;
        uint256 royaltyReciverFinalBalance = address(royaltyReciver).balance;

        assertTrue(finalBuyerBalance <= buyerBalance - price, "Buyer should have been charged the price");
        assertEq(finalBalance, initialBalance + price - royaltyFee, "Seller should receive the deducted payment");
        assertEq(royaltyReciverFinalBalance, royaltyReciverInitialBalance + royaltyFee, "Royalty receiver should receive the percentage of payment");
    }

    function test_buyToken_DesignatedReceiverGetsRoyaltyOnSuccessfulBuy() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));
        _nft.setDefaultRoyalty(5_00); // 5% default royalty
        
        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");
        _nft.setTokenRoyalty(tokenId, nftOwner1, 10_00); // 10% royalty

        uint256 price = 100;

        // send token to another owner
        vm.startPrank(nftOwner1);
       _nft.safeTransferFrom(nftOwner1, nftOwner2, tokenId);
        vm.stopPrank();

        // new owner sets token for sale
        vm.startPrank(nftOwner2);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, price);
        vm.stopPrank();

        (address royaltyReciver, uint256 royaltyFee) = _tradingBroker.getRoyaltyFee(address(_nft), tokenId);

        uint256 initialBalance = address(nftOwner2).balance;
        uint256 royaltyReciverInitialBalance = address(royaltyReciver).balance;

        bytes32 commitMsg = keccak256(abi.encodePacked(nftBuyer1, price, address(_nft), tokenId));

        vm.startPrank(nftBuyer1);

        _tradingBroker.commitBuy(address(_nft), commitMsg);

        // give buyer some funds and buy token
        vm.deal(nftBuyer1, 10 ether);

        uint256 buyerBalance = address(nftBuyer1).balance;

        _tradingBroker.buyToken{value: price}(address(_nft), tokenId);
        vm.stopPrank();

        uint256 finalBuyerBalance = address(nftBuyer1).balance;
        uint256 finalBalance = address(nftOwner2).balance;
        uint256 royaltyReciverFinalBalance = address(royaltyReciver).balance;

        assertTrue(finalBuyerBalance <= buyerBalance - price, "Buyer should have been charged the price");
        assertEq(finalBalance, initialBalance + 90, "Seller should receive the deducted payment");
        assertEq(royaltyReciverFinalBalance, royaltyReciverInitialBalance + 10, "Royalty receiver should receive the percentage of payment");
    }

    function test_revokeTokenForSale_RevertsWithDisallowedContracts() public {
        vm.expectRevert("Not an allowed contract");
        _tradingBroker.revokeTokenForSale(address(_tradeableNft), 1);
    }

    function test_revokeTokenForSale_RevertsIfCallerIsNotTokenOwner() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, uint256(0.5 ether));
        vm.stopPrank();

        vm.startPrank(nftOwner2);
        vm.expectRevert("Unauthorized to delist token");
        _tradingBroker.revokeTokenForSale(address(_nft), tokenId);
        vm.stopPrank();
    }

    function test_revokeTokenForSale_RevertsIfCallerIsNotManagedContract() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, uint256(0.5 ether));
        vm.stopPrank();

        vm.startPrank(address(_tradeableNft));
        vm.expectRevert("Unauthorized to delist token");
        _tradingBroker.revokeTokenForSale(address(_nft), tokenId);
        vm.stopPrank();
    }

    function test_revokeTokenForSale_SuccessfullyRemovesTokenListingIfCalledbyTokenOwner() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, uint256(0.5 ether));
        
        _tradingBroker.revokeTokenForSale(address(_nft), tokenId);
        vm.stopPrank();

        assertFalse(_tradingBroker.isTokenForSale(address(_nft), tokenId));
    }

    function test_revokeTokenForSale_SuccessfullyRemovesTokenListingIfCalledByMangedContract() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, uint256(0.5 ether));
        vm.stopPrank();

        vm.startPrank(address(_nft));
        _tradingBroker.revokeTokenForSale(address(_nft), tokenId);
        vm.stopPrank();

        assertFalse(_tradingBroker.isTokenForSale(address(_nft), tokenId));
    }

    function test_revokeTokenForSale_SuccessfulRevocationEmitsEvent() public {
        _tradingBroker.addManagedContract(address(_nft), true);

        _nft.setTradingBroker(address(_tradingBroker));

        uint256 tokenId = getNftId();
        _nft.mint(nftOwner1, tokenId, "");

        vm.startPrank(nftOwner1);
        _tradingBroker.setTokenForSale(address(_nft), tokenId, uint256(0.5 ether));
        vm.stopPrank();

        vm.startPrank(address(_nft));
        vm.expectEmit(true, true, true, true);
        emit TradingBroker.TokenForSaleRemoved(address(_nft), tokenId);
        _tradingBroker.revokeTokenForSale(address(_nft), tokenId);
        vm.stopPrank();
    }
}