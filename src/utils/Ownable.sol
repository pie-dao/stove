// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.6;

contract Ownable {
    address private _owner;
    
    event OwnershipChanged(address indexed previousOwner, address indexed newOwner);

    error NotOwner();

    modifier onlyOwner {
        if(msg.sender != _owner) {
            revert NotOwner();
        }

        _;
    }

    constructor() {
        _owner = msg.sender;
    }

    function owner() public view returns(address) {
        return _owner;
    }

    function renounceOwnership() external onlyOwner {
        _owner = address(0);
        emit OwnershipChanged(msg.sender, address(0));
    }

    function transferOwnership(address newOwner) external onlyOwner {
        _owner = newOwner;
        emit OwnershipChanged(msg.sender, newOwner);
    }
}