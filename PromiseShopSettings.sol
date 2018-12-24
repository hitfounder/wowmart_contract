pragma solidity ^0.4.23;
pragma experimental ABIEncoderV2;

import "../contracts/Ownable.sol";
import "../contracts/PromiseShopSettingsInterface.sol";

contract PromiseShopSettings is PromiseShopSettingsInterface, Ownable {
  // IPFS hash of docker file containing script to be executed while quering
  string private oraclizeScript;
  // Configurable activity traits
  mapping(uint16 => PromiseShopTypes.ActivityData) private activityTraits;
  // List of admins, maps address to access rights
  mapping(address => uint16) private admins;
  // Storage of int values
  mapping(bytes32 => uint) private valueStorage;
  // Storage of bool flags
  mapping(bytes32 => bool) private flagStorage;

  // The only address which could call methods
  address public caller;

  modifier onlyCaller() {
    require(msg.sender == caller);
    _;
  }

  function setCaller(address sender) public onlyOwner {
    caller = sender;
  }

  function getValue(bytes32 key) external view onlyCaller returns(uint) {
      return valueStorage[key];
  }

  function setValue(bytes32 key, uint value) external onlyCaller {
    valueStorage[key] = value;
  }

  function getFlag(bytes32 key) external view onlyCaller returns(bool) {
      return flagStorage[key];
  }

  function setFlag(bytes32 key, bool value) external onlyCaller {
    flagStorage[key] = value;
  }

  function getOraclizeScript() external view onlyCaller returns(string) {
    return oraclizeScript;
  }
  
  function setOraclizeScript(string script) external onlyCaller {
    oraclizeScript = script;
  }

  function getActivity(uint16 activityId) external view onlyCaller returns(uint32 minParameter,
                                                                         uint32 maxParameter,
                                                                         bool lessIsBetter) {
    PromiseShopTypes.ActivityData memory activityData = activityTraits[activityId];
    minParameter = activityData.minParameter;
    maxParameter = activityData.maxParameter;
    lessIsBetter = activityData.lessIsBetter;
  }

  function setActivity(uint16 activityId,
                       bool lessIsBetter,
                       uint32 minParameter,
                       uint32 maxParameter) external onlyCaller {
    activityTraits[activityId] = PromiseShopTypes.ActivityData(minParameter,
                                                               maxParameter,
                                                               lessIsBetter);
  }

  function getAdminRights(address admin) external view onlyCaller returns(uint16) {
    return admins[admin];
  }
  
  function setAdminRights(address admin, uint16 rights) external onlyCaller {
    admins[admin] = rights;
  }
}
