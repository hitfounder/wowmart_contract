pragma solidity ^0.4.23;

// Simple Ownable base contract
contract Ownable {
  address public owner;

  event OwnershipTransferred(
      address indexed previousOwner,
      address indexed newOwner);

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  constructor() internal {
    owner = msg.sender;
    emit OwnershipTransferred(address(0), owner);
  }

  function changeOwner(address newOwner) public onlyOwner {
    require(newOwner != address(0));
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }
}