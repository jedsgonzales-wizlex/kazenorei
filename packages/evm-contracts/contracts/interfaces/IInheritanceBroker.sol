// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IInheritanceBroker {
    function setTokenInheritor(address contractAddress_, address inheritor_) external;
    function getInheritor(address contractAddress_, address tokenOwner_) external view returns (address);
    function transferInheritance(address contractAddress_, address tokenOwner_, uint256[] memory tokenIds_) external returns(uint96);
}
