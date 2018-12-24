pragma solidity ^0.4.23;
pragma experimental ABIEncoderV2;

import "../contracts/PromiseShopTypes.sol";

contract PromiseShopSettingsInterface {
  function getValue(bytes32 key) external view returns (uint);
  function setValue(bytes32 key, uint value) external;

  function getFlag(bytes32 key) external view returns (bool);
  function setFlag(bytes32 key, bool value) external;

  function getOraclizeScript() external view returns(string);
  function setOraclizeScript(string script) external;

	function getActivity(uint16 activityId) external view returns(uint32 minParameter,
                                                                uint32 maxParameter,
                                                                bool lessIsBetter);
  function setActivity(uint16 activityId,
                       bool lessIsBetter,
                       uint32 minParameter,
                       uint32 maxParameter) external;

  function getAdminRights(address admin) external view returns(uint16);
  function setAdminRights(address admin, uint16 rights) external;
}
