// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IGovernance{
    function stkTokenAddr() external view returns (address);
    function getCalTime() external  view returns(uint);
    function getFundsDownLimit() external  view returns(uint);
    function getZeroTimeLimit() external  view returns(uint);
    function dropProportion() external  view returns(uint);
    function dayLen() external  view returns(uint);
}

interface IPool{
    function memberTotal() external view returns (uint);
    function memberAddrs(uint _index) external view returns (address);
    function memberTimes(address _account) external view returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

contract Airdrop is ERC20{
    using SafeMath for uint256;

    IGovernance public Igovern;
    IPool public Ipool;

    //最后一次空投时间
    uint256 public dropLastTime = 0;
    //lock锁
    bool private unlocked = true;
    //锁定信息
    mapping(address => mapping (uint => uint)) public lockInfos;

    constructor () ERC20('THIS IS A REWARD TOKEN','retMOVR'){
    }

    //克隆合约初始化调用,_amount单位为Wei
    function initialize (
        address _governAddr,
        string memory name_,
        string memory symbol_,
        address _account,
        uint _amount
    ) external{
        require(address(Igovern) == address(0),'Igovern seted!');
        if(_amount > 0){
            _mint(_account, _amount);
        }
        _name = name_;
        _symbol = symbol_;
        Igovern = IGovernance(_governAddr);
        //克隆合约需要初始化非默认值非constant的参数值
        unlocked = true;
    }

    modifier lock() {
        require(unlocked, 'Airdrop: LOCKED!');
        unlocked = false;
        _;
        unlocked = true;
    }

    //执行空投
    function droping(uint _memberTotal, uint _calTime) private lock{
        // uint256 balance = Ipool.balance();
        // uint256 totalSupply = Ipool.totalSupply();
        for(uint i=0;i < _memberTotal;i++){
            address account = Ipool.memberAddrs(i);
            uint256 memberTime = Ipool.memberTimes(account);
            uint256 amount = Ipool.balanceOf(account);
            if(memberTime > 0 && amount > 0){
                //计算是否是_calTime的倍数
                uint256 day = (block.timestamp).sub(memberTime).div(60 * 60 *24);
                if(day > 0 && day.mod(_calTime) == 0){
                    //池子剩余token，按比例空投算法
                    // amount = balance.mul(amount).mul(Igovern.dropProportion).div(totalSupply).div(100);    
                    //池子持有stktoken，按比例空投算法
                    amount = amount.mul(Igovern.dropProportion()).div(100);
                    _mint(account, amount);
                }
            }
        }
    }

    //代币空投（定时器执行）
    function startDrop() public{
        //判断是否符合空投铸造条件
        require(Igovern.stkTokenAddr() != address(0),'stkTokenAddr is not set!');
        require((block.timestamp).sub(dropLastTime).div(60 * 60 *24) > 0,'droping!');
        uint calTime = Igovern.getCalTime();
        require(calTime > 0,'calTime is zero!');
        Ipool = IPool(Igovern.stkTokenAddr());
        require(Ipool.totalSupply() >= Igovern.getFundsDownLimit(),'Less then fundsDownLimit!');
        uint memberTotal = Ipool.memberTotal();
        require(memberTotal > 0,'memberTotal is zero!');
        dropLastTime = block.timestamp;
        droping(memberTotal,calTime);
    }

    //代币销毁,_amount单位为Wei
    function burn(address _account, uint256 _amount) public{
        require(_amount > 0, 'burn: amount is zero!');
        //判断是否符合销毁条件
        require(Igovern.stkTokenAddr() == msg.sender,'burn: msg.sender is illegal!');//保证从Pool发起
        _burn(_account, _amount);
    }

    //按地址日期租赁时限将retToken发送到合约并锁定,_amount单位为Wei
    function lockLeaseMargin(
        address _from,
        address _leaseAddr,
        uint _leaseDate,
        uint _period,
        uint256 _amount
    ) public{
        require(Igovern.stkTokenAddr() == msg.sender,'lockLeaseMargin: msg.sender is illegal!');//保证从Pool发起
        require(_from != address(0),'lockLeaseMargin: _from is illegal!');
        require(_leaseAddr != address(0),'lockLeaseMargin: _leaseAddr is illegal!');
        require(_period > 0,'lockLeaseMargin: _period is zero!');
        require(_amount > 0,'lockLeaseMargin: _amount is zero!');
        lockInfos[_leaseAddr][_leaseDate] = _period;
        _transfer(_from,_leaseAddr,_amount);
    }

    //按地址日期租赁时限将合约中retToken进行解锁,_amount单位为Wei
    function unlockLeaseMargin(
        address _account,
        uint _leaseDate,
        uint256 _amount
    ) public{
        uint period = lockInfos[msg.sender][_leaseDate];
        if(period > 0 && _leaseDate.add(period * Igovern.dayLen()) <= block.timestamp.div(24 * 60 * 60)){
            _transfer(msg.sender,_account,_amount);
        }
    }

    //按地址日期租赁时限将合约中retToken进行销毁（零收益）,_amount单位为Wei
    function zeroIncomePunish(uint _leaseDate,uint256 _amount) public{
        uint period = lockInfos[msg.sender][_leaseDate];
        if(period > 0 && _leaseDate.add(Igovern.getZeroTimeLimit()) <= block.timestamp.div(24 * 60 * 60)){
            _burn(msg.sender, _amount);
        }
    }
}