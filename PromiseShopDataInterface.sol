pragma solidity ^0.4.23;
pragma experimental ABIEncoderV2;

import "../contracts/PromiseShopTypes.sol";

interface PromiseShopDataInterface {
  function getSenderPromisesCount(address sender) external view returns(uint);
  function getSenderPromiseId(address sender, uint index) external view returns(uint32);

  function getPromisesCount() external view returns(uint);
  function addPromise(PromiseShopTypes.Data data) public returns(uint32);
  function setPromise(uint32 promiseId, PromiseShopTypes.Data data) public;
  function getPromise(uint promiseId) public view returns(PromiseShopTypes.Data);

  function getQuery(bytes32 queryId) public view returns(PromiseShopTypes.ExistingID);
  function setQuery(bytes32 queryId, uint32 promiseId) external;

  function setOverallComplexity(uint32 complexity) external;
  function getOverallComplexity() external view returns(uint32);

  function setOverallDeposits(uint deposits) external;
  function getOverallDeposits() external view returns(uint);

  function setFund(uint value) external;
  function getFund() external view returns(uint);

  function setHold(uint value) external;
  function getHold() external view returns(uint);
}
