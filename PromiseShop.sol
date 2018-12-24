pragma solidity ^0.4.23;
pragma experimental ABIEncoderV2;

import "../contracts/Ownable.sol";
import "../contracts/PromiseShopStorage.sol";
import "../installed_contracts/oraclize-api/contracts/usingOraclize.sol";

contract PromiseShop is PromiseShopStorage, usingOraclize, Ownable {
  event Promise(
    address indexed sender,
    uint deposit,
    uint bonus,
    uint deadline,
    uint32 promiseId,
    uint16 activity,
    uint32 parameter,
    PromiseShopTypes.State state
  );

  event Response(
    uint32 promiseId,
    string response,
    uint32 parsed
  );

  modifier adminOrOwner(uint16 requiredAccess) {
    require(msg.sender == owner || 
           ((settingsData.getAdminRights(msg.sender) & requiredAccess) == 0 ? false : true));
    _;
  }

  // Access rights for admins
  uint16 constant ACCESS_SET_AUTO_REWARD = 2**0;
  uint16 constant ACCESS_SET_AUTO_LOSS = 2**1;
  uint16 constant ACCESS_SET_BASE_TIMESTAMP = 2**2;
  uint16 constant ACCESS_SET_ACTIVITY_TRAITS = 2**3;
  uint16 constant ACCESS_SET_ORACLIZE_SCRIPT = 2**4;
  uint16 constant ACCESS_SET_FEE = 2**5;
  uint16 constant ACCESS_RESOLVE = 2**6;
  uint16 constant ACCESS_ADD_ADMIN = 2**7;
  uint16 constant ACCESS_WITHDRAW = 2**8;

  constructor() public {
    // Oraclize address only for test purpose.
    // If you executed ethereum bridge in private network with non determenistic address,
    // uncomment this and specify the address.
    // OAR = OraclizeAddrResolverI(0x6f485C8BF6fc43eA212E93BBF8ce046C7f1cb475);

    // Set custom gas price, default was 20 GWei
    oraclize_setCustomGasPrice(10000000000);
  }

  // PromiseShopData getters
  //////////////////////////
  function promises(uint promiseId) public view returns(address sender,
                                                        uint deposit,
                                                        uint bonus,
                                                        uint deadline,
                                                        uint16 activity,
                                                        uint32 parameter,
                                                        PromiseShopTypes.State state) {
    PromiseShopTypes.Data memory promise = promisesData.getPromise(promiseId);
    sender = promise.sender;
    deposit = promise.deposit;
    bonus = promise.bonus;
    deadline = promise.deadline;
    activity = promise.activity;
    parameter = promise.parameter;
    state = promise.state;
  }

  function senderPromises(address sender, uint index) public view returns(uint32) {
    return promisesData.getSenderPromiseId(sender, index);
  }

  function overallComplexity() public view returns(uint32) {
    return promisesData.getOverallComplexity();
  }

  function overallDeposits() public view returns(uint) {
    return promisesData.getOverallDeposits();
  }

  function fund() public view returns(uint) {
    return promisesData.getFund();
  }

  function hold() public view returns(uint) {
    return promisesData.getHold();
  }

  function getPromisesCount() public view returns(uint) {
    return promisesData.getPromisesCount();
  }

  function getSenderPromisesCount(address sender) public view returns(uint) {
    return promisesData.getSenderPromisesCount(sender);
  }

  // Options setters
  //////////////////
  function setAutoReward(bool enabled) public adminOrOwner(ACCESS_SET_AUTO_REWARD) {
    settingsData.setFlag("ar", enabled);
  }

  function autoReward() public view returns(bool) {
    return settingsData.getFlag("ar");
  }

  function setAutoLoss(bool enabled) public adminOrOwner(ACCESS_SET_AUTO_LOSS) {
    settingsData.setFlag("al", enabled);
  }

  function autoLoss() public view returns(bool) {
    return settingsData.getFlag("al");
  }

  function setBaseTimeStamp(uint timeStamp) public adminOrOwner(ACCESS_SET_BASE_TIMESTAMP) {
    settingsData.setValue("bt", timeStamp);
  }

  function baseTimeStamp() public view returns(uint) {
    return settingsData.getValue("bt");
  }

  function setActivityTraits(uint16 activity,
                             bool lessIsBetter,
                             uint32 minParameter,
                             uint32 maxParameter) public adminOrOwner(ACCESS_SET_ACTIVITY_TRAITS) {
    settingsData.setActivity(activity, lessIsBetter, minParameter, maxParameter);
  }
  
  function activityTraits(uint16 activity) public view returns(uint32 minParameter,
                                                               uint32 maxParameter,
                                                               bool lessIsBetter) {
    (minParameter, maxParameter, lessIsBetter) = settingsData.getActivity(activity);
  }

  function setOraclizeScript(string newScript) public adminOrOwner(ACCESS_SET_ORACLIZE_SCRIPT) {
    settingsData.setOraclizeScript(newScript);
  }

  function oraclizeScript() public view returns(string) {
    return settingsData.getOraclizeScript();
  }

  function setFee(uint newFee) public adminOrOwner(ACCESS_SET_FEE) {
    settingsData.setValue("fe", newFee);
  }

  function fee() public view returns(uint) {
    return settingsData.getValue("fe");
  }

  function addAdmin(address admin, uint16 rights) public adminOrOwner(ACCESS_ADD_ADMIN) {
    settingsData.setAdminRights(admin, rights);
  }

  function isAdmin(address user) public view returns(bool) {
    return user == owner || settingsData.getAdminRights(user) != 0;
  }

  // Businness logic
  //////////////////
  function checkCondition(uint32 targetParameter,
                          uint32 actualParameter,
                          bool lessIsBetter) private pure returns(bool) {
    if (actualParameter == 0) {
      return false;
    }
    if (lessIsBetter) {
      return actualParameter <= targetParameter;
    } else {
      return actualParameter >= targetParameter;
    }
  }

  function getComplexity(uint16 activity,
                         uint32 parameter) public view returns(uint8) {
    PromiseShopTypes.ActivityData memory activityData;
    (activityData.minParameter, activityData.maxParameter, activityData.lessIsBetter) =
        settingsData.getActivity(activity);
    require(activityData.minParameter > 0 || activityData.maxParameter > 0);
    
    if (parameter < activityData.minParameter) {
      return (activityData.lessIsBetter) ? 255 : 1;
    }
    if (parameter > activityData.maxParameter) {
      return (activityData.lessIsBetter) ? 1 : 255;
    }
    
    // @todo make exponential dependency
    if (activityData.lessIsBetter) {
      return uint8(255 - 254 * (parameter - activityData.minParameter) / (activityData.maxParameter - activityData.minParameter));
    } else {
      return uint8(254 * (parameter - activityData.minParameter) / (activityData.maxParameter - activityData.minParameter) + 1);
    }
    assert(false);
  }

  // Calculate current bonus, depending on activity parameters and deposit amount.
  // Only for external calls - for evaluating promises, that are not yet commited.
  function getBonus(uint deposit,
                    uint16 activity,
                    uint32 parameter) public view returns(uint) {
    uint8 complexity = getComplexity(activity, parameter);
    return getBonusInternal(deposit, complexity,
        promisesData.getOverallComplexity() + complexity,
        promisesData.getOverallDeposits() + deposit);
  }

  // Calculate bonus for already commited promise.
  // Only for internal call.
  function getBonusInternal(uint deposit,
                            uint8 currentComplexity,
                            uint32 totalComplexity,
                            uint totalDeposits) private view returns(uint) {
    assert(totalComplexity != 0 && totalDeposits != 0);

    uint fund = promisesData.getFund();
    uint hold = promisesData.getHold();
    assert(fund >= hold);
    
    uint freeCash = fund - hold;
    uint bonusComplexityBased = (currentComplexity * freeCash) / totalComplexity;
    uint bonusDepositBased = (deposit * freeCash) / totalDeposits;
    return (bonusComplexityBased > bonusDepositBased) ? bonusDepositBased
                                                      : bonusComplexityBased;
  }

  function getQueryPrice() public view returns(uint) {
    // Set custom gas limit to prevent "out of gas" on callback, default was 200,000 gas
    return oraclize_getPrice("computation", 400000) + settingsData.getValue("fe");
  }

  function getWithdrawAmount() public view returns(uint) {
    uint overallDeposits = promisesData.getOverallDeposits();
    uint fund = promisesData.getFund();
    uint hold = promisesData.getHold();
    assert(address(this).balance >= overallDeposits + fund + hold);
    return address(this).balance - overallDeposits - fund - hold;
  }

  function withdraw() public adminOrOwner(ACCESS_WITHDRAW) {
    msg.sender.transfer(getWithdrawAmount());
  }

  function createQuery(string token,
                       uint16 activity) private view returns(string) {
    assert(bytes(settingsData.getOraclizeScript()).length != 0);

    uint baseTimeStamp = settingsData.getValue("bt");
    uint promiseTime = baseTimeStamp != 0 ? baseTimeStamp : now;
    bool lessIsBetter;
    (,,lessIsBetter) = settingsData.getActivity(activity);
    string memory part1 = strConcat("[computation] ['",
                                    settingsData.getOraclizeScript(),
                                    "', '${[decrypt] ",
                                    token,
                                    "}', '");
    string memory part2 = strConcat(uint2str(activity),
                                    " ', '",
                                    uint2str(lessIsBetter ? 1 : 0),
                                    " ', '",
                                    uint2str(promiseTime));
    return strConcat(part1, part2, "']");
  }

  function __callback(bytes32 id, string result) public {
    // @todo reschedule query if deadline > 60 days
    require(msg.sender == oraclize_cbAddress());

    PromiseShopTypes.ExistingID memory promiseId = promisesData.getQuery(id);
    require(promiseId.exists);

    uint fund = promisesData.getFund();
    uint hold = promisesData.getHold();
    assert(fund >= hold);

    uint32 actualParameter = uint32(parseInt(result));

    emit Response(promiseId.id, result, actualParameter);

    PromiseShopTypes.Data memory promise = promisesData.getPromise(promiseId.id);
    uint8 complexity = getComplexity(promise.activity, promise.parameter);
    promise.bonus = getBonusInternal(promise.deposit,
                                     complexity,
                                     promisesData.getOverallComplexity(),
                                     promisesData.getOverallDeposits());
    promisesData.setHold(hold + promise.bonus);

    uint resultLength = bytes(result).length;
    bool resultIsNotANumber = actualParameter == 0 && resultLength > 0;
    bool lessIsBetter;
    (,,lessIsBetter) = settingsData.getActivity(promise.activity);
    if (resultLength == 0 || resultIsNotANumber) {
      promise.state = PromiseShopTypes.State.Error;
    } else if (checkCondition(promise.parameter,
                              actualParameter,
                              lessIsBetter)) {
      if (settingsData.getFlag("ar"))
        reward(promise, complexity, false);  // Cannot throw
      else
        promise.state = PromiseShopTypes.State.PendingReward;
    } else {
      if (settingsData.getFlag("al"))
        loss(promise, complexity);
      else
        promise.state = PromiseShopTypes.State.PendingLoss;
    }

    promisesData.setPromise(promiseId.id, promise);
    emit Promise(promise.sender,
                 promise.deposit,
                 promise.bonus,
                 promise.deadline,
                 promiseId.id,
                 promise.activity,
                 promise.parameter,
                 promise.state);
  }

  // Send reward for succedded promise.
  // If canThrow == false, if sending is failed, promise moves to PendingReward state
  function reward(PromiseShopTypes.Data memory promise, uint8 complexity, bool canThrow) internal {
    bool sendResult = true;
    if (canThrow) {
      promise.sender.transfer(promise.deposit + promise.bonus);
    } else {
      sendResult = promise.sender.send(promise.deposit + promise.bonus);
    }

    if (sendResult) {
      promisesData.setOverallComplexity(promisesData.getOverallComplexity() - complexity);
      promisesData.setOverallDeposits(promisesData.getOverallDeposits() - promise.deposit);
      promisesData.setFund(promisesData.getFund() - promise.bonus);
      promisesData.setHold(promisesData.getHold() - promise.bonus);
      promise.state = PromiseShopTypes.State.Succeded;
    } else {
      promise.state = PromiseShopTypes.State.PendingReward;
    }
  }

  // Add money to fund, after failed promise
  function loss(PromiseShopTypes.Data memory promise, uint8 complexity) internal {
    promisesData.setOverallComplexity(promisesData.getOverallComplexity() - complexity);
    promisesData.setOverallDeposits(promisesData.getOverallDeposits() - promise.deposit);
    promisesData.setFund(promisesData.getFund() + promise.deposit);
    promisesData.setHold(promisesData.getHold() - promise.bonus);

    promise.state = PromiseShopTypes.State.Failed;
  }

  // Resolves pending promise
  // approve - promise resolution
  function resolve(uint32 promiseId, bool approve) public adminOrOwner(ACCESS_RESOLVE) {
    PromiseShopTypes.Data memory promise = promisesData.getPromise(promiseId);
    require(promise.deposit != 0);
    require(promise.state == PromiseShopTypes.State.PendingReward ||
            promise.state == PromiseShopTypes.State.PendingLoss ||
            promise.state == PromiseShopTypes.State.Error);

    assert(address(this).balance >= promise.deposit + promise.bonus);
    assert(promisesData.getFund() >= promise.bonus);

    uint8 complexity = getComplexity(promise.activity, promise.parameter);
    if ((promise.state == PromiseShopTypes.State.PendingReward && approve) ||  // reward approved
        (promise.state == PromiseShopTypes.State.PendingLoss && !approve) ||   // loss rejected
        (promise.state == PromiseShopTypes.State.Error && approve)) {          // errror confirmed
      reward(promise, complexity, true);
    } else if ((promise.state == PromiseShopTypes.State.PendingReward && !approve) ||  // reward rejected
               (promise.state == PromiseShopTypes.State.PendingLoss && approve) ||     // loss approved
               (promise.state == PromiseShopTypes.State.Error && !approve)) {          // error not confirmed
      loss(promise, complexity);
    } else {
      // Any other state is not posssible
      assert(false);
    }

    promisesData.setPromise(promiseId, promise);
    emit Promise(promise.sender,
                 promise.deposit,
                 promise.bonus,
                 promise.deadline,
                 promiseId,
                 promise.activity,
                 promise.parameter,
                 promise.state);
  }

  // Returns error code, possible values:
  // ------------------------------------
  //   0 - success
  //   1 - not enough money to make Oraclize query
  // Parameters:
  // -----------
  //   deadline - seconds to promise deadline
  //   activity - activity type
  //   parameter - target parameter for activity, e.g. distance, time, weight, etc
  //   token - encrypted security token, could be used to access external API
  function promise(uint32 deadline,
                   uint16 activity,
                   uint32 parameter,
                   string token) public payable returns(uint8) {
    require(msg.value != 0);
    require(activity != 0);

    uint oraclizePrice = getQueryPrice();
    if (msg.value < oraclizePrice) {
      return 1;
    }

    uint deposit = msg.value - oraclizePrice;
    promisesData.setOverallComplexity(
        promisesData.getOverallComplexity() + getComplexity(activity, parameter));
    promisesData.setOverallDeposits(
        promisesData.getOverallDeposits() + deposit);
    uint absoluteDeadline = now + deadline;
    uint32 promiseId = promisesData.addPromise(
        PromiseShopTypes.Data(msg.sender,
                              deposit,
                              0,
                              absoluteDeadline,
                              activity,
                              parameter,
                              PromiseShopTypes.State.Active));
    // Set custom gas limit to prevent "out of gas" on callback, default was 200,000 gas
    promisesData.setQuery(
        oraclize_query(deadline, "nested", createQuery(token, activity), 400000), promiseId);

    emit Promise(msg.sender,
                 deposit,
                 0,
                 absoluteDeadline,
                 promiseId,
                 activity,
                 parameter,
                 PromiseShopTypes.State.Active);
    return 0;
  }
}
