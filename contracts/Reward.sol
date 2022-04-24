// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IGovernance{
    function setRewardAddr(address _rewardAddr) external;
    function stkTokenAddr() external view returns (address);
    function getCalTime() external view returns(uint);
}

interface IPool{
    function memberTotal() external view returns (uint);
    function memberAddrs(uint _index) external view returns (address);
    function memberTimes(address _account) external view returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

contract Reward{
    using SafeMath for uint256;

    IGovernance public Igovern;
    IPool public Ipool;
    //lock锁
    bool private unlocked = true;
    //DAO奖励
    mapping(address => uint256) public daoRewards;

    constructor (){
    }

    //克隆合约初始化调用
    function initialize (address _governAddr) external{
        require(address(Igovern) == address(0),'Igovern seted!');
        Igovern = IGovernance(_governAddr);
        //设置Government的奖励地址
        Igovern.setRewardAddr(address(this));
        //克隆合约需要初始化非默认值非constant的参数值
        unlocked = true;
    }

    modifier lock() {
        require(unlocked, 'Reward: LOCKED!');
        unlocked = false;
        _;
        unlocked = true;
    }

    fallback () external payable{}

    receive () external payable{
        assignReward();
    }

    //接收委托人和收集人的奖励，达到分配条件进行奖励分配（stkToken持有人）
    function assignReward() public lock{
        require(Igovern.stkTokenAddr() != address(0),'stkTokenAddr not seted!');
        uint calTime = Igovern.getCalTime();
        require(calTime > 0,'assignReward:calTime is zero!');
        require(address(this).balance > 0,'Less then rewardDownLimit');
        Ipool = IPool(Igovern.stkTokenAddr());
        uint totalSupply = Ipool.totalSupply();

        uint256 newReward = address(this).balance;
        for(uint i = 0; i < Ipool.memberTotal(); i++){
            address account = Ipool.memberAddrs(i);
            uint256 memberTime = Ipool.memberTimes(account);
            uint256 amount = Ipool.balanceOf(account);
            if(memberTime > 0 && amount > 0){
                uint256 day = (block.timestamp).sub(memberTime).div(60 * 60 *24);
                if(day >= calTime){
                    uint256 reward = newReward.mul(amount).div(totalSupply);
                    daoRewards[account] = daoRewards[account].add(reward);
                    Address.sendValue(payable(account),reward);
                }
            }
        }
    }

    //原生质押token余额
    function balance() public view returns(uint256){
        return address(this).balance;
    }
}