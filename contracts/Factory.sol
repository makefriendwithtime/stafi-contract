// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";

interface IGovernance{
    function initialize(
        uint256 _authorAmount,
        uint _blockHeight,
        address _ownerAddress
    ) external;
}

interface IPool{
    function initialize (
        address _governAddr,
        string memory name_,
        string memory symbol_,
        address _faucetModelAddr
    ) external;
}

interface IAirdrop{
    function initialize (
        address _governAddr,
        string memory name_,
        string memory symbol_,
        address _account,
        uint _amount
    ) external;
}

interface IReward{
    function initialize (address _governAddr) external;
}

contract Factory is Ownable{
    mapping(uint => address[]) private daoAddrs;
    uint public len = 0;
    //governance模板地址
    address  public governModelAddr;
    //pool模板地址
    address  public poolModelAddr;
    //airdrop模板地址
    address  public airdropModelAddr;
    //reward模板地址
    address  public rewardModelAddr;
    //faucet模板地址
    address public faucetModelAddr;

    function createClone(address target) internal returns (address result) {
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            result := create(0, clone, 0x37)
        }
    }

    function createDAO(
        uint256 _authorAmount, //100000000000000000000
        uint _blockHeight,//1200 部署时根据实际网络调整
        string memory _stkName,//stkToken票据所有权
        string memory _stkSymbol,//stkToken
        string memory _retName,//retToken票据使用权
        string memory _retSymbol,//retToken
        uint _retAmount//10000000000000000000000
    ) public onlyOwner(){
        require(governModelAddr != address(0)
        && poolModelAddr != address(0)
        && airdropModelAddr != address(0)
        && rewardModelAddr != address(0)
            && faucetModelAddr != address(0),'ModelAddress not seted!');
        IGovernance Igovern = IGovernance(createClone(governModelAddr));
        Igovern.initialize(_authorAmount,_blockHeight,msg.sender);

        IPool Ipool = IPool(createClone(poolModelAddr));
        Ipool.initialize(address(Igovern),_stkName,_stkSymbol,faucetModelAddr);

        IAirdrop Iairdrop = IAirdrop(createClone(airdropModelAddr));
        Iairdrop.initialize(address(Igovern),_retName,_retSymbol,msg.sender,_retAmount);

        IReward Ireward = IReward(createClone(rewardModelAddr));
        Ireward.initialize(address(Igovern));

        address[] storage addrs = daoAddrs[len];
        addrs.push(address(Igovern));
        addrs.push(address(Ipool));
        addrs.push(address(Iairdrop));
        addrs.push(address(Ireward));
        daoAddrs[len] = addrs;
        len += 1;
    }

    function setGovernModelAddr(address _modelAddr) public onlyOwner(){
        governModelAddr = _modelAddr;
    }

    function setPoolModelAddr(address _modelAddr) public onlyOwner(){
        poolModelAddr = _modelAddr;
    }

    function setAirdropModelAddr(address _modelAddr) public onlyOwner(){
        airdropModelAddr = _modelAddr;
    }

    function setRewardModelAddr(address _modelAddr) public onlyOwner(){
        rewardModelAddr = _modelAddr;
    }

    function setFaucetModelAddr(address _modelAddr) public onlyOwner(){
        faucetModelAddr = _modelAddr;
    }

    function getDaoAddrs(uint _index) public view returns(address[] memory){
        return daoAddrs[_index];
    }
}