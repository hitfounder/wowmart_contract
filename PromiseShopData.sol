pragma solidity ^0.4.23;
pragma experimental ABIEncoderV2;

import "../contracts/Ownable.sol";
import "../contracts/PromiseShopDataInterface.sol";

contract PromiseShopData is PromiseShopDataInterface, Ownable {
  // Contains all promises
  PromiseShopTypes.Data[] public promises;
  // Contains all promise IDs (indexes in "promises" array)
  // of specified sender (address)
  mapping(address => uint32[]) public senderPromises;
  // Maps query id to existing promise ID
  mapping(bytes32 => PromiseShopTypes.ExistingID) private queries;

  // Summ off complexity of all promises
  uint32 public overallComplexity;
  // Summ off deposits af all promises
  uint public overallDeposits;

  // Rewards (bonuses) fund
  uint public fund;
  // Rewards in pending state
  uint public hold;

  // The only address which could call methods
  address public caller;


  modifier onlyCaller() {
    require(msg.sender == caller);
    _;
  }

  constructor() public {
    overallComplexity = 0;
    overallDeposits = 0;
    fund = 0;
    hold = 0;
  }

  function setCaller(address sender) public onlyOwner {
    caller = sender;
  }

  function getSenderPromisesCount(address sender) external view onlyCaller returns(uint) {
    return senderPromises[sender].length;
  }

  function getSenderPromiseId(address sender, uint index) external view onlyCaller returns(uint32) {
    require(index < senderPromises[sender].length);
    return senderPromises[sender][index];
  }

  function addPromise(PromiseShopTypes.Data data) public onlyCaller returns(uint32) {
    promises.push(data);
    uint32 promiseId = uint32(promises.length) - 1;
    senderPromises[data.sender].push(promiseId);
    return promiseId;
  }

  function getPromisesCount() external view onlyCaller returns(uint) {
    return promises.length;
  }

  function setPromise(uint32 promiseId, PromiseShopTypes.Data data) public onlyCaller {
    require(promiseId < promises.length);
    promises[promiseId] = data;
  }

  function getPromise(uint promiseId) public view onlyCaller returns(PromiseShopTypes.Data) {
    require(promiseId < promises.length);
    return promises[promiseId];
  }

  function getQuery(bytes32 queryId) public view returns(PromiseShopTypes.ExistingID) {
    return queries[queryId];
  }

  function setQuery(bytes32 queryId, uint32 promiseId) external {
    queries[queryId] = PromiseShopTypes.ExistingID(promiseId, true);
  }

  function setOverallComplexity(uint32 complexity) external onlyCaller {
    overallComplexity = complexity;
  }

  function getOverallComplexity() external view onlyCaller returns(uint32) {
    return overallComplexity;
  }

  function setOverallDeposits(uint deposits) external onlyCaller {
    overallDeposits = deposits;
  }

  function getOverallDeposits() external view onlyCaller returns(uint) {
    return overallDeposits;
  }

  function setFund(uint value) external onlyCaller {
    fund = value;
  }

  function getFund() external view onlyCaller returns(uint) {
    return fund;
  }

  function setHold(uint value) external onlyCaller {
    hold = value;
  }

  function getHold() external view onlyCaller returns(uint) {
    return hold;
  }
}
