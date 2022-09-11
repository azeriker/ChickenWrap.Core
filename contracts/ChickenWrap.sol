// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Import this file to use console.log
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20 {
    function transfer(address _to, uint256 _value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

contract ChickenWrap is Ownable {
    struct Plan {
        uint256 id;
        string title;
        bool reccuring; //reccuring(A) if true otherwise model(B) 
        //model A
        uint256 price; //amount of money will withdraw per one reccuringInterval
        uint256 reccuringInterval; //time between payments
        //or todo discuss
        //model B
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
    IERC20 stable;
    address adminAddress;
    uint256 multiplier;

    uint256 currentPlanId = 1;
    uint256 currentSubscriptionId = 1;
    uint256 commonFee = 20;

    //partner data
    mapping(uint256 => Plan) idToPlans;
    mapping(address => mapping(uint256 => bool)) partnerToIds;
    mapping(uint256 => mapping(uint256 => uint256)) planIdToSubscription;
    mapping(uint256 => address) planIdToPartners;

    //shared data
    mapping(uint256 => Subscription) subscriptions;

    //user data
    mapping(address => uint256) balance;
    mapping(address => mapping(uint256 => uint256)) userToSubscriptionId;

    constructor() {
        registerFee = 10;
        createPlanFee = 100;
        //busd address
        stable = IERC20(address(0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee));
        adminAddress = address(0x2bd1365a502F83fd0AEa5c0bbd8551E24e548c7C);
        multiplier = 10**18; //decimals in our stable
    }

    //partner section
    function createPlan(Plan calldata plan) external {
        //todo uncomment and withdraw stable
        //require(msg.value == createPlanFee); //check fee amount

        //todo validate plan parameters
        //todo test it
        if(stable.transferFrom(msg.sender, adminAddress, createPlanFee * multiplier)){
            idToPlans[currentPlanId] = plan;
            idToPlans[currentPlanId].id= currentPlanId;
            partnerToIds[msg.sender][currentPlanId] = true;
            planIdToPartners[currentPlanId] = msg.sender;
            currentPlanId++;
        }
    }

    function removePlan(uint256 planId) external {
        require(partnerToIds[msg.sender][planId] == true); //check plan for exist
        delete idToPlans[planId];
        partnerToIds[msg.sender][currentPlanId] = false;
        planIdToPartners[planId] = address(0);
    }

    function getPlanIds(address owner) public view returns (uint256[] memory) {
        uint256[] memory planIds = new uint256[](currentPlanId);
        uint256 counter;
        for (uint256 index = 1; index < currentPlanId; index++) {
            if(partnerToIds[owner][index]==true)
            {
               planIds[counter]= index;
               counter++;
            }            
        }
        return planIds;
    }

    function getPlanById(uint256 planId) public view returns (Plan memory) {
        return idToPlans[planId];
    }

    function getBillableSubscriptions(uint256 planId)
        public
        view
        returns (uint256[] memory)
    {
        Plan memory currentPlan = idToPlans[planId];
        require(currentPlan.price > 0); //check plan for exist
        uint256[] memory subscriptionIds;
        uint256 foundId;
        for (uint256 i = 1; i < currentSubscriptionId; i++) {
            if (planIdToSubscription[planId][i] == i) { 
                if (isSubscriptionReadyForBill(subscriptions[i], currentPlan)) 
                {
                    subscriptionIds[foundId] = i;
                    foundId++;
                }
            }
        }

        return subscriptionIds;
    }

    //todo there are two ways to implement billing.
    //1. Partner call some method and get money transfers
    //2. Oracle call some method and we transfer ready amounts to partner wallets

    //todo think about naming
    //this is main function to get money from subscribers to partners  
    function billSubscriptions(uint256[] memory subscriptionIds) public returns(address[] memory, uint256[] memory)  {
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

            paidByAddress[index] = plan.price;
            addresses[index] = subscription.user;

            transfer(subscription.user, plan.price);

            return (addresses, paidByAddress);
        }
    }

    //user section
    function deposit() external payable {
        balance[msg.sender] += msg.value;
    }

    function transfer(address from, uint256 planId) public {
        address partnerAddress = planIdToPartners[planId];
        require(partnerAddress != address(0));

        Plan memory plan = idToPlans[planId];

        uint256 feeAmount = plan.price / commonFee;
        uint256 amount = plan.price - feeAmount;
        stable.transferFrom(from, partnerAddress, amount);
        stable.transferFrom(from, address(this), feeAmount);
    }

    function triggerSubscriptionPayments(uint256 planId) public {

        uint256[] memory subscriptionIds = getBillableSubscriptions(planId);
        billSubscriptions(subscriptionIds);
    }

    function withdraw() external {
        require(balance[msg.sender] > 0); //allow withdraw only if u have more than zero
        payable(msg.sender).transfer(balance[msg.sender]);
    }

    function subscribe(uint256 planId) external {
        Plan memory currentPlan = idToPlans[planId];
        require(currentPlan.price > 0); //check plan for exist
        require(userToSubscriptionId[msg.sender][planId] == 0); //check that user doesnt have this plan already

        transfer(msg.sender, planId);

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

    function getSubscriptionIds(address owner) public view returns (uint256[] memory){
        uint256[] memory subIds = new uint256[](currentSubscriptionId);
        uint256 counter;
        for (uint256 index = 1; index < currentSubscriptionId; index++) {
            if(userToSubscriptionId[owner][index]==index)
            {
               subIds[counter] = index;
               counter++;
            }            
        }
        return subIds;
    }

    function getSubscriptionById(uint256 subId) public view returns (Subscription memory){
        return subscriptions[subId];
    }

    //pure section
    function isSubscriptionReadyForBill(
        Subscription memory subscription,
        Plan memory plan
    ) public view returns (bool) {
        return subscription.lastWithdrawTime + plan.reccuringInterval < block.timestamp;
    }
}
