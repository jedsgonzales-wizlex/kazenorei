// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

abstract contract Inheritable {
    function setInheritanceBroker(address broker_) public virtual;
}