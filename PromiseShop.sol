pragma solidity ^0.4.22;

import "../installed_contracts/oraclize-api/contracts/usingOraclize.sol";

contract PromiseShop is usingOraclize {
  enum PromiseState {
    Active,        // Promise is in progress
    Succeded,      // Promise is finished with performed conditions
    Failed,        // Promise is finished with failed conditions
    PendingReward, // Promise succeded, reward is posponed
    PendingLoss,   // Promise failed, loss is posponed
    Error          // Error while getting query response
  }

  struct PromiseData {
    address sender;
    uint deposit;
    uint bonus;
    uint deadline;      // Absolute timestamp in future, seconds since unix epoch
    uint16 activity;    // Activity ID
    uint32 parameter;   // Parameter value for activity
    PromiseState state;
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

  event Promise(
    address indexed sender,
    uint deposit,
    uint bonus,
    uint deadline,
    uint32 promiseId,
    uint16 activity,
    uint32 parameter,
    PromiseState state
  );

  event Response(
    uint32 promiseId,
    string response,
    uint32 parsed
  );

  modifier adminOrOwner(uint16 requiredAccess) {
    require(msg.sender == owner || 
           ((admins[msg.sender] & requiredAccess) == 0 ? false : true));
    _;
  }

  address public owner;

  // Contains all promises
  PromiseData[] public promises;
  // Contains all promise IDs (indexes in "promises" array)
  // of specified sender (address)
  mapping(address => uint32[]) public senderPromises;

  // Maps query id to existing promise ID
  mapping(bytes32 => ExistingID) public queries;

  // Summ off complexity of all promises
  uint32 public overallComplexity;
  // Summ off deposits af all promises
  uint public overallDeposits;

  // Rewards (bonuses) fund
  uint public fund;
  // Rewards in pending state
  uint public hold;

  // Rewards are paid automatically without approve
  bool public autoReward;
  // Losses are withdrawn automatically without approve
  bool public autoLoss;
  // IPFS hash of docker file containing script to be executed while quering
  string public oraclizeScript;
  // Promise base time stamp, defines promise start time. Only for tests.
  uint32 public baseTimeStamp;
  // Configurable activity traits
  mapping(uint16 => ActivityData) public activityTraits;
  // List of admins, maps address to access rights
  mapping(address => uint16) public admins;
  // Promise fee
  uint public fee;

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

    owner = msg.sender;
    overallComplexity = 0;
    overallDeposits = 0;
    fund = 0;
    hold = 0;

    // Settings
    autoReward = true;
    autoLoss = true;
    oraclizeScript = "";
    baseTimeStamp = 0;
    fee = 0;
  }

  function setAutoReward(bool enabled) public adminOrOwner(ACCESS_SET_AUTO_REWARD) {
    autoReward = enabled;
  }

  function setAutoLoss(bool enabled) public adminOrOwner(ACCESS_SET_AUTO_LOSS) {
    autoLoss = enabled;
  }

  function setBaseTimeStamp(uint32 timeStamp) public adminOrOwner(ACCESS_SET_BASE_TIMESTAMP) {
    baseTimeStamp = timeStamp;
  }

  function setActivityTraits(uint16 activity,
                             bool lessIsBetter,
                             uint32 minParameter,
                             uint32 maxParameter) public adminOrOwner(ACCESS_SET_ACTIVITY_TRAITS) {
    activityTraits[activity] =
      ActivityData(minParameter, maxParameter, lessIsBetter);
  }

  function setOraclizeScript(string newScript) public adminOrOwner(ACCESS_SET_ORACLIZE_SCRIPT) {
    oraclizeScript = newScript;
  }

  function setFee(uint newFee) public adminOrOwner(ACCESS_SET_FEE) {
    fee = newFee;
  }

  function addAdmin(address admin, uint16 rights) public adminOrOwner(ACCESS_ADD_ADMIN) {
    admins[admin] = rights;
  }

  function isAdmin(address user) public constant returns(bool) {
    return user == owner || admins[user] != 0;
  }

  function checkCondition(uint32 targetParameter,
                          uint32 actualParameter,
                          bool lessIsBetter) public pure returns(bool) {
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
                         uint32 parameter) public constant returns(uint8) {
    ActivityData storage activityData = activityTraits[activity];
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
                    uint32 parameter) public constant returns(uint) {
    uint8 complexity = getComplexity(activity, parameter);
    return getBonusInternal(deposit, complexity,
        overallComplexity + complexity, overallDeposits + deposit);
  }

  // Calculate bonus for already commited promise.
  // Only for internal call.
  function getBonusInternal(uint deposit,
                            uint8 currentComplexity,
                            uint32 totalComplexity,
                            uint totalDeposits) private constant returns(uint) {
    assert(totalComplexity != 0 && totalDeposits != 0);
    uint bonus_complexity_based = (currentComplexity * (fund - hold)) / totalComplexity;
    uint bonus_deposit_based = (deposit * (fund - hold)) / totalDeposits;
    return (bonus_complexity_based > bonus_deposit_based) ? bonus_deposit_based
                                                          : bonus_complexity_based;
  }

  function getQueryPrice() public constant returns(uint) {
    return oraclize_getPrice("computation") + fee;
  }

  function getWithdrawAmount() public constant returns(uint) {
    assert(address(this).balance >= overallDeposits + fund + hold);
    return address(this).balance - overallDeposits - fund - hold;
  }

  function getPromisesCount() public constant returns(uint) {
    return promises.length;
  }

  function getSenderPromisesCount(address sender) public constant returns(uint) {
    return senderPromises[sender].length;
  }

  function withdraw() public adminOrOwner(ACCESS_WITHDRAW) {
    msg.sender.transfer(getWithdrawAmount());
  }

  function createQuery(string token,
                       uint16 activity) private constant returns(string) {
    assert(bytes(oraclizeScript).length != 0);

    uint promiseTime = baseTimeStamp != 0 ? baseTimeStamp : now;
    string memory part1 = strConcat("[computation] ['",
                                    oraclizeScript,
                                    "', '${[decrypt] ",
                                    token,
                                    "}', '");
    string memory part2 = strConcat(uint2str(activity),
                                    " ', '",
                                    uint2str(activityTraits[activity].lessIsBetter ? 1 : 0),
                                    " ', '",
                                    uint2str(promiseTime));
    return strConcat(part1, part2, "']");
  }

  function __callback(bytes32 id, string result) public {
    // @todo reschedule query if deadline > 60 days
    require(msg.sender == oraclize_cbAddress());
    require(queries[id].exists);
    assert(fund >= hold);

    uint32 promiseId = queries[id].id;
    uint32 actualParameter = uint32(parseInt(result));

    emit Response(promiseId, result, actualParameter);

    PromiseData storage promise = promises[promiseId];
    uint8 complexity = getComplexity(promise.activity, promise.parameter);
    promise.bonus = getBonusInternal(promise.deposit,
                                     complexity,
                                     overallComplexity,
                                     overallDeposits);
    hold += promise.bonus;

    uint resultLength = bytes(result).length;
    bool resultIsNotANumber = actualParameter == 0 && resultLength > 1;
    if (resultLength == 0 || resultIsNotANumber) {
      promise.state = PromiseState.Error;
    } else
    if (checkCondition(promise.parameter,
                       actualParameter,
                       activityTraits[promise.activity].lessIsBetter)) {
      if (autoReward)
        reward(promise, complexity, false);  // Cannot throw
      else
        promise.state = PromiseState.PendingReward;
    } else {
      if (autoLoss)
        loss(promise, complexity);
      else
        promise.state = PromiseState.PendingLoss;
    }

    emit Promise(promise.sender,
                 promise.deposit,
                 promise.bonus,
                 promise.deadline,
                 promiseId,
                 promise.activity,
                 promise.parameter,
                 promise.state);
  }

  // Send reward for succedded promise.
  // If canThrow == false, if sending is failed, promise moves to PendingReward state
  function reward(PromiseData storage promise, uint8 complexity, bool canThrow) internal {
    bool sendResult = true;
    if (canThrow) {
      promise.sender.transfer(promise.deposit + promise.bonus);
    } else {
      sendResult = promise.sender.send(promise.deposit + promise.bonus);
    }

    if (sendResult) {
      overallComplexity -= complexity;
      overallDeposits -= promise.deposit;
      fund -= promise.bonus;
      hold -= promise.bonus;
      promise.state = PromiseState.Succeded;
    } else {
      promise.state = PromiseState.PendingReward;
    }
  }

  // Add money to fund, after failed promise
  function loss(PromiseData storage promise, uint8 complexity) internal {
    overallComplexity -= complexity;
    overallDeposits -= promise.deposit;
    fund += promise.deposit;
    hold -= promise.bonus;
    promise.state = PromiseState.Failed;
  }

  // Resolves pending promise
  // approve - promise resolution
  function resolve(uint32 promiseId, bool approve) public adminOrOwner(ACCESS_RESOLVE) {
    PromiseData storage promise = promises[promiseId];
    require(promise.deposit != 0);
    require(promise.state == PromiseState.PendingReward ||
            promise.state == PromiseState.PendingLoss ||
            promise.state == PromiseState.Error);

    assert(address(this).balance >= promise.deposit + promise.bonus);
    assert(fund >= promise.bonus);

    bool rewardApproved = promise.state == PromiseState.PendingReward && approve;
    bool lossRejected = promise.state == PromiseState.PendingLoss && !approve;
    bool rewardRejected = promise.state == PromiseState.PendingReward && !approve;
    bool lossApproved = promise.state == PromiseState.PendingLoss && approve;
    bool error = promise.state == PromiseState.Error;

    uint8 complexity = getComplexity(promise.activity, promise.parameter);
    if (rewardApproved || lossRejected || (error && approve)) {
      reward(promise, complexity, true);
    } else if (rewardRejected || lossApproved || (error && !approve)) {
      loss(promise, complexity);
    } else {
      assert(false);
    }

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
    uint8 complexity = getComplexity(activity, parameter);
    overallComplexity += complexity;
    overallDeposits += deposit;
    uint absoluteDeadline = now + deadline;
    promises.push(PromiseData(msg.sender,
                              deposit,
                              0,
                              absoluteDeadline,
                              activity,
                              parameter,
                              PromiseState.Active));

    uint32 promiseId = uint32(promises.length) - 1;
    senderPromises[msg.sender].push(promiseId);

    bytes32 queryId = oraclize_query(deadline, "nested", createQuery(token, activity));
    queries[queryId] = ExistingID(promiseId, true);

    emit Promise(msg.sender,
                 deposit,
                 0,
                 absoluteDeadline,
                 promiseId,
                 activity,
                 parameter,
                 PromiseState.Active);
    return 0;
  }
}
