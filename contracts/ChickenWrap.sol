// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Import this file to use console.log
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ChickenWrap is Ownable {
    struct Plan {
        uint256 price; //max amount of money that can be paid in one interval
        uint256 interval; //min time between payments
        uint256 reward;
    }

    struct Subscription {
        uint256 id;
        address user;
        uint256 planId;
        uint256 lastWithdrawTime;
    }

    uint256 registerFee;
    uint256 createPlanFee;

    uint256 currentPlanId = 1;
    uint256 currentSubscriptionId = 1;

    //partner data
    mapping(address => bool) registeredPartners;
    mapping(uint256 => Plan) idToPlans;
    mapping(address => mapping(uint256 => bool)) partnerToIds;
    mapping(uint256 => mapping(uint256 => uint256)) planIdToSubscription;

    //shared data
    mapping(uint256 => Subscription) subscriptions;

    //user data
    mapping(address => uint256) balance;
    mapping(address => mapping(uint256 => uint256)) userToSubscriptionId;

    constructor(uint256 _registerFee, uint256 _createPlanFee) {
        registerFee = _registerFee;
        createPlanFee = _createPlanFee;
    }

    //partner section
    function register() external payable {
        require(msg.value == registerFee); //check fee
        require(!isRegistered(msg.sender)); //check for not registered yet

        registeredPartners[msg.sender] = true;
    }

    function isRegistered(address addr) public view returns (bool) {
        return registeredPartners[addr];
    }

    function createPlan(Plan calldata plan) external payable {
        require(msg.value == createPlanFee); //check fee amount

        //todo validate plan parameters

        idToPlans[currentPlanId] = plan;
        partnerToIds[msg.sender][currentPlanId] = true;
        currentPlanId++;
    }

    function removePlan(uint256 planId) external {
        require(partnerToIds[msg.sender][planId] == true); //check plan for exist
        delete idToPlans[planId];
        partnerToIds[msg.sender][currentPlanId] = false;
    }

    function getBillableSubscriptions(uint256 planId)
        external
        view
        returns (uint256[] memory)
    {
        Plan memory currentPlan = idToPlans[planId];
        require(currentPlan.price > 0); //check plan for exist
        uint256[] memory subscriptionIds;
        uint256 foundId;
        for (uint256 i = 1; i < currentSubscriptionId; i++) {
            if (planIdToSubscription[planId][i] == i) {
                if (
                    isSubscriptionReadyForBill(subsription, plan)
                ) subscriptionIds[foundId] = i;
            }
        }

        return subscriptionIds;
    }

    //todo there are two ways to implement billing.
    //1. Partner call some method and get money transfers for ready for bill subscriptions
    //2. Oracle call some method and increase internal balances of partners. Partners can withdraw balance on demand

    //todo think about naming
    //this is main function to get money from subscribers to partners  
    function billSubscriptions(uint256[] calldata subscriptionIds) external returns(address[] memory, uint256[] memory) {
        //todo check that msg.sender owner of plans in ids, or maybe allow to one plan per method call
        
        address[] memory addresses = new address(subscriptionIds.length);
        uint256[] memory paid = new uint256(subscriptionIds.length);

        for (uint256 index = 0; index < subscriptionIds.length; index++) {
            uint256 subscriptionId = subscriptionIds[index];
            Subscription storage subscription = subscriptions[subscriptionId];
            Plan memory plan = idToPlans[subscription.planId];
            require(
                isSubscriptionReadyForBill(subsription, plan)
            );
            subscription.lastWithdrawTime = block.timestamp;
            balance[subscription.user] -= plan.price;
            payable(msg.sender).transfer(plan.price);
            paidByAddress[subscription.user] = plan.price;
        }
    }

    //user section
    function deposit() external payable {
        balance[msg.sender] += msg.value;
    }

    function withdraw() external {
        require(balance[msg.sender] > 0); //allow withdraw only if u have more than zero
        payable(msg.sender).transfer(balance[msg.sender]);
    }

    function subscribe(uint256 planId) external {
        Plan memory currentPlan = idToPlans[planId];
        require(currentPlan.price > 0); //check plan for exist
        require(balance[msg.sender] >= currentPlan.price); //balance enough to at least one withdraw
        require(userToSubscriptionId[msg.sender][planId] == 0); //check that user doesnt have this plan already

        Subscription memory subscription = Subscription(
            currentSubscriptionId,
            msg.sender,
            planId,
            0
        );

        subscriptions[currentSubscriptionId] = subscription;
        planIdToSubscription[planId][
            currentSubscriptionId
        ] = currentSubscriptionId;
        currentSubscriptionId++;
    }

    function unsubscribe(uint256 unsubscribeId) external {
        require(subscriptions[unsubscribeId].user == msg.sender); //check that user are owner of subscription
        Subscription memory unsubscribing = subscriptions[unsubscribeId];

        planIdToSubscription[unsubscribing.planId][unsubscribeId] = 0;
        userToSubscriptionId[msg.sender][unsubscribeId] = 0;
        delete subscriptions[unsubscribeId];
    }

    //pure section
    function isSubscriptionReadyForBill(
        Subscription calldata subscription,
        Plan calldata plan
    ) public pure returns (bool) {
        return subscription.lastWithdrawTime + plan.interval < block.timestamp
    }
}
