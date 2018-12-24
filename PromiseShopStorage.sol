pragma solidity ^0.4.23;

import "../contracts/PromiseShopDataInterface.sol";
import "../contracts/PromiseShopSettingsInterface.sol";

contract PromiseShopStorage {
  // Data
  PromiseShopDataInterface public promisesData;
  // Settings
  PromiseShopSettingsInterface public settingsData;
}
