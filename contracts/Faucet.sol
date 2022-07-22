// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
import "./StakingInterface.sol";
import "./AuthorMappingInterface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IAirdrop{
    function zeroIncomePunish(uint _leaseDate,uint256 _amount) external;
    function unlockLeaseMargin(
        address _account,
        uint _leaseDate,
        uint256 _amount
    ) external;
}

interface IGovernance{
    function getZeroTimeLimit() external  view returns(uint);
    function stkTokenAddr() external view returns (address);
    function retTokenAddr() external view returns (address);
    function rewardAddr() external view returns (address);
    function authorAmount() external view returns(uint256);
    function blockHeight() external  view returns(uint);
    function getCollatorTechFee() external  view returns(uint);
    function getDaoTechFee() external  view returns(uint);
    function owner() external view returns (address);
    function dayLen() external  view returns(uint);
}

contract Faucet{
    using SafeMath for uint256;

    IGovernance public Igovern;
    IAirdrop public Iairdrop;

    //水龙头类型
    bool public faucetType;//真收集人，假为委托人
    //委托收集人地址(faucetType为假有效)
    address public collatorAddr;
    //收集人技术服务奖励地址(faucetType为真有效)
    address public techAddr;
    //租赁状态
    bool public bstate = false;
    //退出减少租赁时所在区块高度
    uint256 public leaveNumber = 0;
    //绑定的nimbusId
    bytes32 public nimbusId = 0;

    //租赁信息
    struct LeaseInfo{
        uint period;//租赁周期:1个周期为30天，2个周期为60天，依次类推
        uint256 leaseDate;//租赁日期
        uint256 amount;//租赁票数
        uint256 marginAmount;//抵押票数
        uint256 lessAmount;//减少票数
        address redeemAddr;//抵押赎回地址
    }
    LeaseInfo public leaseInfo;
    //预编译地址
    address private constant precompileAddress = 0x0000000000000000000000000000000000000800;
    address private constant precompileAuthorMappingAddr = 0x0000000000000000000000000000000000000807;
    //预编译接口对象
    ParachainStaking public staking;
    AuthorMapping public authorMapping;
    //无奖励计数
    uint public punishCount = 0;
    //记录最新奖励日期
    uint public recordDate;
    //收集人管理者
    address public faucetOwner;
    //合约sudo地址
    address public owner;
    //lock锁
    bool private unlocked = true;

    event SendReward(uint256 _reward);

    event RecordRewardInfo(uint _rdDate,uint256 _rdAmount);

    event LeaveRedeem(uint256 _leaveNumber);

    event Association(bytes32 _nimbusId);

    event RedeemState(bool _success);

    constructor (){
    }

    //克隆合约初始化调用
    function initialize (
        address _governAddr,
        address _collatorAddr,
        address _techAddr,
        address _faucetOwner,
        bool _faucetType,
        address _owner
    ) external{
        require(address(Igovern) == address(0),'Igovern seted!');
        Igovern = IGovernance(_governAddr);
        staking = ParachainStaking(precompileAddress);
        faucetOwner = _faucetOwner;
        owner = _owner;
        faucetType = _faucetType;
        if(faucetType){
            techAddr = _techAddr;
            authorMapping = AuthorMapping(precompileAuthorMappingAddr);
        }else{
            collatorAddr = _collatorAddr;
        }
        //克隆合约需要初始化非默认值非constant的参数值
        unlocked = true;
    }

    fallback () external payable{}

    receive () external payable{
        //判断发送地址是否来自Pool，来自Pool则调用激活委托人
        if(Igovern.stkTokenAddr() == msg.sender && !bstate){
            //激活收集人/委托人
            ActivateFaucet();
        }else{
            Address.sendValue(payable(Igovern.rewardAddr()), msg.value);
        }
    }

    modifier isOwner() {
        require(msg.sender == owner,'Not management!');
        _;
    }

    function setGovernAddr(address _governAddr) public isOwner{
        Igovern = IGovernance(_governAddr);
    }

    modifier isFaucetOwner() {
        require(msg.sender == faucetOwner,'Not management!');
        _;
    }

    modifier lock() {
        require(unlocked, 'Faucet: LOCKED!');
        unlocked = false;
        _;
        unlocked = true;
    }

    //激活收集人/委托人
    function ActivateFaucet() private {
        require(leaseInfo.amount > 0 && address(this).balance >= leaseInfo.amount,'ActivateFaucet: leaseInfo is illegal!');
        //开始抵押
        if(faucetType){
            staking.join_candidates(leaseInfo.amount, staking.candidate_count());
        }else{
            staking.delegate(collatorAddr, leaseInfo.amount, staking.candidate_delegation_count(collatorAddr), staking.delegator_delegation_count(address(this)));
        }
        bstate = true;
    }

    //按地址日期租赁时限记录选票信息,_amount、_marginAmount单位为Wei
    function setLeaseInfo(
        address _redeemAddr,
        uint _leaseDate,
        uint _period,
        uint256 _amount,
        uint256 _marginAmount
    ) external{
        require(Igovern.stkTokenAddr() == msg.sender,'setLeaseInfo: msg.sender is illegal!');//保证从Pool发起
        require(_period > 0,'setLeaseInfo: period is illegal!');
        require(_leaseDate > 0,'setLeaseInfo: _leaseDate is illegal!');
        require(leaveNumber == 0,'setLeaseInfo: redeeming!');
        require(!bstate,'setLeaseInfo: it is delegator or collator!');

        leaseInfo.leaseDate = _leaseDate;
        leaseInfo.amount = _amount;
        leaseInfo.marginAmount = _marginAmount;
        leaseInfo.period = _period;
        leaseInfo.redeemAddr = _redeemAddr;
    }

    //奖励收集人
    function collatorReward(uint256 reward) private{
        uint256 daoFee = reward.mul(Igovern.getDaoTechFee()).div(100);
        Address.sendValue(payable(Igovern.owner()), daoFee);
        uint256 techFee = reward.mul(Igovern.getCollatorTechFee()).div(100);
        Address.sendValue(payable(techAddr), techFee);
        Address.sendValue(payable(Igovern.rewardAddr()), reward.sub(techFee).sub(daoFee));
    }

    //奖励收集人
    function delegatorReward(uint256 reward) private{
        uint256 daoFee = reward.mul(Igovern.getDaoTechFee()).div(100);
        Address.sendValue(payable(Igovern.owner()), daoFee);
        Address.sendValue(payable(Igovern.rewardAddr()), reward.sub(daoFee));
    }

    //抵押收益，每日发送一次到奖励池（定时器执行）
    function sendReward() public{
        require(bstate && ((faucetType && nimbusId >0) || !faucetType),'not delegator or collator!');
        require(leaveNumber == 0 || leaveNumber.add(Igovern.blockHeight()) > block.number,'first execute RedeemStake!');
        uint date = block.timestamp.div(24 * 60 * 60);
        require(recordDate < date,'recordDate recorded!');
        if(recordDate > 0 && address(this).balance == 0){
            punishCount += date.sub(recordDate);
        }
        recordDate = date;
        emit RecordRewardInfo(date,address(this).balance);
        if(address(this).balance > 0){
            if(faucetType){
                collatorReward(address(this).balance);
            }else{
                delegatorReward(address(this).balance);
            }
            emit SendReward(address(this).balance);
        }
    }

    //清除NimbusId,退回绑定质押(收集人)
    function clearAssociation() private{
        if(nimbusId > 0){
            authorMapping.clear_association(nimbusId);
            nimbusId = 0;
            emit Association(nimbusId);
        }
        Address.sendValue(payable(Igovern.stkTokenAddr()), Igovern.authorAmount());
    }

    //零收益处罚，并强制计划回收选票（定时器执行）
    function zeroIncomePunish() public lock{
        require(bstate,'zeroIncomePunish: not delegator or collator!');
        require(leaveNumber == 0,'redeeming!');
        require(punishCount >= Igovern.getZeroTimeLimit(),'punishCount is not enough!');
        //强制计划回收
        bstate = false;
        leaveNumber = block.number;
        if(faucetType){
            staking.schedule_leave_candidates(staking.candidate_count());
            clearAssociation();
        }else{
            staking.schedule_leave_delegators();
        }
        uint256 marginAmount = leaseInfo.marginAmount;
        leaseInfo.marginAmount = 0;
        Iairdrop = IAirdrop(Igovern.retTokenAddr());
        Iairdrop.zeroIncomePunish(leaseInfo.leaseDate,marginAmount);
        emit LeaveRedeem(leaveNumber);
    }

    //手动计划租赁赎回（租赁人执行）
    function scheduleRedeemStakeManual(uint256 _lessAmount) public isFaucetOwner(){
        require(bstate,'not delegator or collator!');
        require(leaveNumber == 0,'redeeming!');
        require(punishCount < Igovern.getZeroTimeLimit(),'Execute zeroIncomePunish!');
        require(leaseInfo.amount.sub(_lessAmount) >= staking.min_delegation(),'less than min_delegation!');
        leaveNumber = block.number;
        leaseInfo.lessAmount = _lessAmount;
        if(faucetType){
            staking.schedule_candidate_bond_less(_lessAmount);
        }else{
            staking.schedule_delegator_bond_less(collatorAddr,_lessAmount);
        }
        emit LeaveRedeem(leaveNumber);
    }

    //按选票信息正常计划回收选票（定时器执行）
    function scheduleRedeemStake() public lock{
        require(bstate,'not delegator or collator!');
        require(leaveNumber == 0,'redeeming!');
        require(punishCount < Igovern.getZeroTimeLimit(),'Execute zeroIncomePunish!');
        //赎回抵押
        require(leaseInfo.leaseDate.add(leaseInfo.period * Igovern.dayLen()) <= block.timestamp.div(24 * 60 * 60),'not scheduleRedeem!');
        leaveNumber = block.number;
        bstate = false;
        if(faucetType){
            staking.schedule_leave_candidates(staking.candidate_count());
            clearAssociation();
        }else{
            staking.schedule_leave_delegators();
        }
        emit LeaveRedeem(leaveNumber);
    }

    //确认已计划回收的选票，并返还到质押池Pool（定时器执行）
    function executeRedeemStake() public lock{
        require(leaveNumber > 0,'Redeem schedule is not exists!');
        //判断区块高度是否到达设定高度
        require(leaveNumber.add(Igovern.blockHeight()) <= block.number,'not yet reached!');
        leaveNumber = 0;
        if(bstate){
            uint256 amount = leaseInfo.lessAmount;
            leaseInfo.lessAmount = 0;
            if(faucetType){
                //这里需要判断是否计划是否已经被执行
                if(staking.candidate_request_is_pending(address(this))){
                    staking.execute_candidate_bond_less(address(this));
                }
                Address.sendValue(payable(Igovern.stkTokenAddr()), amount);
            }else{
                //这里需要判断是否计划是否已经被执行
                if(staking.delegation_request_is_pending(address(this),collatorAddr)){
                    staking.execute_delegation_request(address(this),collatorAddr);
                }
                Address.sendValue(payable(Igovern.stkTokenAddr()), amount);
            }
            uint256 marginAmount = amount.mul(leaseInfo.marginAmount).div(leaseInfo.amount);
            leaseInfo.amount -= amount;
            if(marginAmount > 0){
                leaseInfo.marginAmount -= marginAmount;
                Iairdrop = IAirdrop(Igovern.retTokenAddr());
                Iairdrop.unlockLeaseMargin(leaseInfo.redeemAddr,leaseInfo.leaseDate,marginAmount);
            }
        }else{
            uint256 amount = leaseInfo.amount;
            leaseInfo.amount = 0;
            if(faucetType){
                //这里需要判断是否计划是否已经被执行
                if(staking.is_candidate(address(this))){
                    staking.execute_leave_candidates(address(this),staking.candidate_delegation_count(address(this)));
                }
                //奖励收集人
                uint256 reward = address(this).balance.sub(amount);
                Address.sendValue(payable(Igovern.stkTokenAddr()), amount);
                if(reward > 0){
                    collatorReward(reward);
                }
            }else{
                //这里需要判断是否计划是否已经被执行
                if(staking.is_delegator(address(this))){
                    staking.execute_leave_delegators(address(this),staking.delegator_delegation_count(address(this)));
                }
                //奖励委托人
                uint256 reward = address(this).balance.sub(amount);
                Address.sendValue(payable(Igovern.stkTokenAddr()), amount);
                if(reward > 0){
                    delegatorReward(reward);
                }
            }
            if(leaseInfo.marginAmount > 0){
                Iairdrop = IAirdrop(Igovern.retTokenAddr());
                Iairdrop.unlockLeaseMargin(leaseInfo.redeemAddr,leaseInfo.leaseDate,leaseInfo.marginAmount);
            }
            recordDate = 0;
            punishCount = 0;
        }
        emit RedeemState(true);
    }

    //添加NimbusId，用于绑定钱包奖励(收集人)
    function addAssociation(bytes32 newNimbusId) public isFaucetOwner(){
        require(faucetType && bstate,'not collator!');
        require(address(this).balance >= Igovern.authorAmount(),'balance not enough!');
        authorMapping.add_association(newNimbusId);
        nimbusId = newNimbusId;
        emit Association(nimbusId);
    }

    //更新NimbusId(收集人)
    function updateAssociation(bytes32 oldNimbusId,bytes32 newNimbusId) public isFaucetOwner(){
        require(nimbusId > 0,'Association not binded!');
        authorMapping.update_association(oldNimbusId,newNimbusId);
        nimbusId = newNimbusId;
        emit Association(nimbusId);
    }

    //原生质押token余额
    function balance() public view returns(uint256){
        return address(this).balance;
    }

    function getPendingRedeemDate() public view returns(uint){
        if(leaseInfo.leaseDate.add(leaseInfo.period * Igovern.dayLen()) <= block.timestamp.div(24 * 60 * 60)){
            return leaseInfo.leaseDate;
        }
        return 0;
    }

    function getPendingRedeemAmount() public view returns(uint){
        if(leaveNumber > 0){
            if(bstate){
                return leaseInfo.lessAmount;
            }else{
                return leaseInfo.amount;
            }
        }
        return 0;
    }
}