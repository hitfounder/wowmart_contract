pragma solidity ^0.4.23;

contract PromiseShopTypes {
  enum State {
    Active,        // Promise is in progress
    Succeded,      // Promise is finished with performed conditions
    Failed,        // Promise is finished with failed conditions
    PendingReward, // Promise succeded, reward is posponed
    PendingLoss,   // Promise failed, loss is posponed
    Error          // Error while getting query response
  }

  struct Data {
    address sender;
    uint deposit;
    uint bonus;
    uint deadline;      // Absolute timestamp in future, seconds since unix epoch
    uint16 activity;    // Activity ID
    uint32 parameter;   // Parameter value for activity
    State state;
  }

  struct ActivityData {
    uint32 minParameter;
    uint32 maxParameter;
    bool lessIsBetter;
  }

  struct ExistingID {
    uint32 id;
    bool exists;
  }
}
