// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IGovernance{
    function stkTokenAddr() external view returns (address);
    function getCalTime() external view returns(uint);
    function rewardType() external  view returns(bool);
    function getRewardDownLimit() external  view returns(uint);
}

interface IPool{
    function getMemberAddrs() external view returns (address[] memory);
    function memberTimes(address _account) external view returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function mintReward(address _account,uint256 _amount) external;
}

contract Reward{
    using SafeMath for uint256;

    IGovernance public Igovern;
    IPool public Ipool;
    //lock锁
    bool private unlocked = true;
    //DAO奖励
    mapping(address => uint256) public daoRewards;
    //合约sudo地址
    address public owner;

    event AssignReward(
        address[] rewardAddrs,
        uint256[] rewardAmounts);

    constructor (){
    }

    //克隆合约初始化调用
    function initialize (address _governAddr,address _owner) external{
        require(address(Igovern) == address(0),'Igovern seted!');
        Igovern = IGovernance(_governAddr);
        owner = _owner;
        //克隆合约需要初始化非默认值非constant的参数值
        unlocked = true;
    }

    modifier isOwner() {
        require(msg.sender == owner,'Not management!');
        _;
    }

    function setGovernAddr(address _governAddr) public isOwner{
        Igovern = IGovernance(_governAddr);
    }

    modifier lock() {
        require(unlocked, 'Reward: LOCKED!');
        unlocked = false;
        _;
        unlocked = true;
    }

    fallback () external payable{}

    receive () external payable{
        if(address(this).balance >= Igovern.getRewardDownLimit()){
            assignReward();
        }
    }

    //接收委托人和收集人的奖励，达到分配条件进行奖励分配（stkToken持有人）
    function assignReward() public lock{
        require(Igovern.stkTokenAddr() != address(0),'assignReward:stkTokenAddr not seted!');
        uint calTime = Igovern.getCalTime();
        require(calTime > 0,'assignReward:calTime is zero!');
        require(address(this).balance > 0,'assignReward:balance is zero!');
        Ipool = IPool(Igovern.stkTokenAddr());
        uint totalSupply = Ipool.totalSupply();

        uint256 newReward = address(this).balance;
        //奖励类型
        bool rewardType = Igovern.rewardType();
        address[] memory rewardAddrs = new address[](Ipool.getMemberAddrs().length);
        uint index = 0;
        for(uint i = 0;i < Ipool.getMemberAddrs().length ;i++){
            address account = Ipool.getMemberAddrs()[i];
            uint256 memberTime = Ipool.memberTimes(account);
            uint256 day = (block.timestamp).sub(memberTime).div(60 * 60 *24);
            if(Address.isContract(account)//排除对合约地址的奖励
            || memberTime == 0
                || day < calTime){
                totalSupply -= Ipool.balanceOf(account);
            }else{
                rewardAddrs[index] = account;
                index++;
            }
        }
        require(index > 0  && totalSupply > 0,'assignReward:reward illegal');
        uint256 sendReward = 0;
        uint256[] memory rewardAmounts = new uint256[](index);
        for(uint i = 0;i < index;i++){
            address account = rewardAddrs[i];
            uint256 reward = 0;
            if(i == index -1){
                reward = newReward.sub(sendReward);
            }else{
                reward = newReward.mul(Ipool.balanceOf(account)).div(totalSupply);
                sendReward += reward;
            }
            daoRewards[account] = daoRewards[account].add(reward);
            if(rewardType){
                //铸造stkToken奖励
                Ipool.mintReward(account,reward);
            }else{
                Address.sendValue(payable(account),reward);
            }
            rewardAmounts[i] = reward;
        }
        if(rewardType){
            Address.sendValue(payable(address(Ipool)),newReward);
        }
        emit AssignReward(rewardAddrs,rewardAmounts);
    }

    //原生质押token余额
    function balance() public view returns(uint256){
        return address(this).balance;
    }
}