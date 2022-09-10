// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Import this file to use console.log
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20 {
    function transfer(address _to, uint256 _value) external returns (bool);

    function transferFrom(address from, address to, uint value) external return (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

contract ChickenWrap is Ownable {
    struct Plan {
        uint256 price; //amount of money will withdraw per one reccuringInterval
        uint256 reccuringInterval; //time between payments
        //or todo discuss
        uint256 maxAmount; //max amount of money that can be withdrawed in one period
        uint256 period; //period per maxAmount

        uint256 reward; // todo remove this bullshit
    }

    struct Subscription {
        uint256 id;
        address user;
        uint256 planId;
        uint256 lastWithdrawTime;
    }

    uint256 registerFee;
    uint256 createPlanFee;
    IERC20 usdt;

    uint256 currentPlanId = 1;
    uint256 currentSubscriptionId = 1;
    uint256 commonFee = 20;

    //partner data
    mapping(address => bool) registeredPartners;
    mapping(uint256 => Plan) idToPlans;
    mapping(address => mapping(uint256 => bool)) partnerToIds;
    mapping(uint256 => mapping(uint256 => uint256)) planIdToSubscription;
    mapping(uint256 => address) planIdToPartners;

    //shared data
    mapping(uint256 => Subscription) subscriptions;

    //user data
    mapping(address => uint256) balance;
    mapping(address => mapping(uint256 => uint256)) userToSubscriptionId;

        usdt = IERC20(address(_usdt));
    constructor() {
        registerFee = 10;
        createPlanFee = 100;
    }

    //partner section
    function register() external payable {
        //todo uncomment and withdraw stable
        //require(msg.value == registerFee); //check fee
        require(!isRegistered(msg.sender)); //check for not registered yet

        registeredPartners[msg.sender] = true;
    }

    function isRegistered(address addr) public view returns (bool) {
        return registeredPartners[addr];
    }

    function createPlan(Plan calldata plan) external payable {
        //todo uncomment and withdraw stable
        //require(msg.value == createPlanFee); //check fee amount

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

    // function getBillableSubscriptions(uint256 planId)
    //     external
    //     view
    //     returns (uint256[] memory)
    // {
    //     Plan memory currentPlan = idToPlans[planId];
    //     require(currentPlan.price > 0); //check plan for exist
    //     uint256[] memory subscriptionIds;
    //     uint256 foundId;
    //     for (uint256 i = 1; i < currentSubscriptionId; i++) {
    //         if (planIdToSubscription[planId][i] == i) {
    //             Subscription 
    //             if (isSubscriptionReadyForBill(subsription, plan)) 
    //             {
    //                 subscriptionIds[foundId] = i;
    //                 foundId++;
    //             }
    //         }
    //     }

    //     return subscriptionIds;
    // }

    //todo there are two ways to implement billing.
    //1. Partner call some method and get money transfers
    //2. Oracle call some method and we transfer ready amounts to partner wallets

    //todo think about naming
    //this is main function to get money from subscribers to partners  
    function billSubscriptions(uint256[] calldata subscriptionIds) external returns(address[] memory, uint256[] memory) {
        //todo check that msg.sender owner of plans in ids, or maybe allow to one plan per method call
        
        address[] memory addresses = new address[](subscriptionIds.length);
        uint256[] memory paidByAddress = new uint256[](subscriptionIds.length);

        for (uint256 index = 0; index < subscriptionIds.length; index++) {
            uint256 subscriptionId = subscriptionIds[index];
            Subscription storage subscription = subscriptions[subscriptionId];
            Plan memory plan = idToPlans[subscription.planId];
            require(
                isSubscriptionReadyForBill(subscription, plan)
            );
            subscription.lastWithdrawTime = block.timestamp;
            balance[subscription.user] -= plan.price;
            payable(msg.sender).transfer(plan.price);
            paidByAddress[index] = plan.price;
            addresses[index] = subscription.user;
        }
    }

    //user section
    function deposit() external payable {
        balance[msg.sender] += msg.value;
    }

    function transfer(address from, uint256 planId) external {
        //todo: get amount of subscription from our data
        //todo: transfer 95% of amount to partner, 5% transfer to our contract
        plan = idToPlans[planId];
        partnerAddress = ;
        
        feeAmount = plan.price / commonFee;
        amount = plan.price - feeAmount;
        usdt.transferFrom(from, partnerAddress, amount);
        usdt.transferFrom(from, address(this), feeAmount);

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
        Subscription memory subscription,
        Plan memory plan
    ) public view returns (bool) {
        return subscription.lastWithdrawTime + plan.reccuringInterval < block.timestamp;
    }
}
