// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ITradingBroker {
    function setTokenForSale(address contractAddress, uint256 tokenId, uint256 price) external;
    function revokeTokenForSale(address contractAddress, uint256 tokenId) external;
    function isTokenForSale(address contractAddress, uint256 tokenId) external view returns (bool);
    function getTokenPrice(address contractAddress, uint256 tokenId) external view returns (uint256);
    function getRoyaltyFee(address contractAddress, uint256 tokenId) external view returns (address, uint256);
    function commitBuy(address contractAddress, bytes32 commitMsg) external;
    function buyToken(address contractAddress, uint256 tokenId) external payable;
    function tokensForSale(address contractAddress, address owner) external view returns (uint256);
}
