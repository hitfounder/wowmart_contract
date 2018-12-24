pragma solidity ^0.4.23;

import "../contracts/Ownable.sol";
import "../contracts/PromiseShopStorage.sol";
import "../installed_contracts/oraclize-api/contracts/usingOraclize.sol";

contract PromiseShopProxy is PromiseShopStorage, usingOraclize, Ownable {
  // Logic delegate
  address public logicContract;

  function setLogicContract(address contractAddress) public onlyOwner {
    logicContract = contractAddress;
  }

  function setDataContract(address dataContractAddress) public onlyOwner {
    promisesData = PromiseShopDataInterface(dataContractAddress);
  }

  function setSettingsContract(address settingsContractAddress) public onlyOwner {
    settingsData = PromiseShopSettingsInterface(settingsContractAddress);
  }

  // Empty __callback function is defined in usingOraclize, so it will be not redirected
  // via fallback proxy, make explicit delegatecall instead
  function __callback(bytes32 id, string result) public {
    require(logicContract != address(0));
    require(logicContract.delegatecall(msg.data));
  }

  function () payable public {
    address target = logicContract;

    assembly {
      // Copy the data sent to the memory address starting free mem position
      let ptr := mload(0x40)
      calldatacopy(ptr, 0, calldatasize)

      // Proxy the call to the contract address with the provided gas and data
      let result := delegatecall(gas, target, ptr, calldatasize, 0, 0)

      // Copy the data returned by the proxied call to memory
      let size := returndatasize
      returndatacopy(ptr, 0, size)

      // Check what the result is, return and revert accordingly
      switch result
      case 0 { revert(ptr, size) }
      case 1 { return(ptr, size) }
    }
  }
}