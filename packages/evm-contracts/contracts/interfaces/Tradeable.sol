// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

abstract contract Tradeable {
    function setTradingBroker(address broker_) public virtual;
}