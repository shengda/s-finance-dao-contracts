// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;

import "./SToken.sol";
import "./Governable.sol";

interface IFarm {
    function crop() external view returns (address);
}

interface ISPool {
    event Farming(address indexed farmer, address indexed from, uint amount);
    event Unfarming(address indexed farmer, address indexed to, uint amount);
    event Harvest(address indexed farmer, address indexed to, uint[] amounts);
    
    function setHarvestSpan(uint _span, bool isLinear) external;
    function farming(uint amount) external;
    function farming(address from, uint amount) external;
    function unfarming() external returns (uint amount);
    function unfarming(uint amount) external returns (uint);
    function unfarming(address to, uint amount) external returns (uint);
    function harvest() external returns (uint[] memory amounts);
    function harvest(address to) external returns (uint[] memory amounts);
    function harvestCapacity(address farmer) external view returns (uint[] memory amounts);
}

contract SStakingPool is ISPool, Governable {
    using SafeMath for uint;
    using TransferHelper for address;

	address public farm;
	address public underlying;
	uint public span;
	uint public end;
	uint public totalStaking;
	mapping(address => uint) public stakingOf;
	mapping(address => uint) public sumRewardPerOf;
	uint public sumRewardPer;
	uint public bufReward;
	uint public lasttime;
	
	constructor(address _farm, address _underlying) public {
		initialize(msg.sender, _farm, _underlying);
	}
	
	function initialize(address governor, address _farm, address _underlying) public initializer {
	    super.initialize(governor);
	    
	    farm     = _farm;
	    underlying  = _underlying;
	    
	    IFarm(farm).crop();                         // just check
	    IERC20(underlying).totalSupply();           // just check
	}
    
    function setHarvestSpan(uint _span, bool isLinear) virtual override external governance {
        span = _span;
        if(isLinear)
            end = now + _span;
        else
            end = 0;
        lasttime = now;
    }
    
    function farming(uint amount) virtual override external {
        farming(msg.sender, amount);
    }
    function farming(address from, uint amount) virtual override public {
        harvest();
        
        _farming(from, amount);
        
        stakingOf[msg.sender] = stakingOf[msg.sender].add(amount);
        totalStaking = totalStaking.add(amount);
        
        emit Farming(msg.sender, from, amount);
    }
    function _farming(address from, uint amount) virtual internal {
        underlying.safeTransferFrom(from, address(this), amount);
    }
    
    function unfarming() virtual override external returns (uint amount){
        return unfarming(msg.sender, stakingOf[msg.sender]);
    }
    function unfarming(uint amount) virtual override external returns (uint){
        return unfarming(msg.sender, amount);
    }
    function unfarming(address to, uint amount) virtual override public returns (uint){
        harvest();
        
        totalStaking = totalStaking.sub(amount);
        stakingOf[msg.sender] = stakingOf[msg.sender].sub(amount);
        
        _unfarming(to, amount);
        
        emit Unfarming(msg.sender, to, amount);
        return amount;
    }
    function _unfarming(address to, uint amount) virtual internal returns (uint){
        underlying.safeTransfer(to, amount);
        return amount;
    }
    
    function harvest() virtual override public returns (uint[] memory amounts) {
        return harvest(msg.sender);
    }
    function harvest(address to) virtual override public returns (uint[] memory amounts) {
        amounts = new uint[](1);
        amounts[0] = 0;
        if(span == 0 || totalStaking == 0)
            return amounts;
        
        uint delta = _harvestDelta();
        amounts[0] = _harvestCapacity(msg.sender, delta, sumRewardPer, sumRewardPerOf[msg.sender]);
        
        if(delta != amounts[0])
            bufReward = bufReward.add(delta).sub(amounts[0]);
        if(delta > 0)
            sumRewardPer = sumRewardPer.add(delta.mul(1 ether).div(totalStaking));
        if(sumRewardPerOf[msg.sender] != sumRewardPer)
            sumRewardPerOf[msg.sender] = sumRewardPer;
        lasttime = now;

        _harvest(to, amounts);
    
        emit Harvest(msg.sender, to, amounts);
    }
    function _harvest(address to, uint[] memory amounts) virtual internal {
        if(amounts.length > 0 && amounts[0] > 0)
            IFarm(farm).crop().safeTransferFrom(farm, to, amounts[0]);
    }
    
    function harvestCapacity(address farmer) virtual override public view returns (uint[] memory amounts) {
        amounts = new uint[](1);
        amounts[0] = _harvestCapacity(farmer, _harvestDelta(), sumRewardPer, sumRewardPerOf[farmer]);
    }
    function _harvestCapacity(address farmer, uint delta, uint sumPer, uint lastSumPer) virtual internal view returns (uint amount) {
        if(span == 0 || totalStaking == 0)
            return 0;
        
        amount = sumPer.sub(lastSumPer);
        amount = amount.add(delta.mul(1 ether).div(totalStaking));
        amount = amount.mul(stakingOf[farmer]).div(1 ether);
    }
    function _harvestDelta() virtual internal view returns(uint amount) {
        amount = IERC20(IFarm(farm).crop()).allowance(farm, address(this)).sub(bufReward);

        if(end == 0) {                                                         // isNonLinear, endless
            if(now.sub(lasttime) < span)
                amount = amount.mul(now.sub(lasttime)).div(span);
        }else if(now < end)
            amount = amount.mul(now.sub(lasttime)).div(end.sub(lasttime));
        else if(lasttime >= end)
            amount = 0;
    }
} 

contract SCurvePool is SStakingPool {
	address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
	address public minter;
	address public gauge;
	address public reward;
	mapping(address => uint) public sumReward2PerOf;
	mapping(address => uint) public sumReward3PerOf;
	uint public sumReward2Per;
	uint public sumReward3Per;
	
	constructor(address _farm, address _underlying, address _minter, address _gauge, address _reward) SStakingPool(_farm, _underlying) public {
		initialize(msg.sender, _farm, _underlying, _minter, _gauge, _reward);
	}
	
	function initialize(address governor, address _farm, address _underlying, address _minter, address _gauge, address _reward) public initializer {
	    super.initialize(governor, _farm, _underlying);
	    
	    minter = _minter;
	    gauge  = _gauge;
	    reward  = _reward;
	    
	    ICurveGauge(gauge).integrate_checkpoint();      // just check
	    ICurveMinter(minter).token();                   // just check
	    IERC20(reward).totalSupply();                   // just check
	}
    
    function _farming(address from, uint amount) virtual override internal {
        super._farming(from, amount);                   // underlying.safeTransferFrom(from, address(this), amount);
        ICurveGauge(gauge).deposit(amount);
    }

    function _unfarming(address to, uint amount) virtual override internal returns (uint){
        ICurveGauge(gauge).withdraw(amount);
        super._unfarming(to, amount);                   // underlying.safeTransfer(to, amount);
        return amount;
    }
    
    function harvest(address to) virtual override public returns (uint[] memory amounts) {
        uint amount = super.harvest(to)[0];
        
        if(reward == address(0))
            amounts = new uint[](2);
        else
            amounts = new uint[](3);
        
        amounts[1] = 0;
        amounts[0] = amount;
        
        if(span == 0 || totalStaking == 0)
            return amounts;
        
        uint delta = IERC20(CRV).balanceOf(address(this));
        ICurveMinter(minter).mint(gauge);
        delta = IERC20(CRV).balanceOf(address(this)).sub(delta);
        //uint delta = _harvestDelta2();
        amounts[1] = _harvestCapacity(msg.sender, delta, sumReward2Per, sumReward2PerOf[msg.sender]);
        
        if(delta > 0)
            sumReward2Per = sumReward2Per.add(delta.mul(1 ether).div(totalStaking));
        if(sumReward2PerOf[msg.sender] != sumReward2Per)
            sumReward2PerOf[msg.sender] = sumReward2Per;
            
        if(reward != address(0)) {
            delta = IERC20(reward).balanceOf(address(this));
            ICurveGauge(gauge).claim_rewards();
            delta = IERC20(reward).balanceOf(address(this)).sub(delta);
            amounts[2] = _harvestCapacity(msg.sender, delta, sumReward3Per, sumReward3PerOf[msg.sender]);
            
            if(delta > 0)
                sumReward3Per = sumReward3Per.add(delta.mul(1 ether).div(totalStaking));
            if(sumReward3PerOf[msg.sender] != sumReward3Per)
                sumReward3PerOf[msg.sender] = sumReward3Per;
        } else
            amounts[2] = 0;

        _harvest2(to, amounts);
    
        emit Harvest(msg.sender, to, amounts);
    }
    function _harvest2(address to, uint[] memory amounts) virtual internal {
        if(amounts.length > 1 && amounts[1] > 0)
            CRV.safeTransfer(to, amounts[1]);
            
        if(amounts.length > 2 && amounts[2] > 0 && reward != address(0))
            reward.safeTransfer(to, amounts[2]);
    }

    function harvestCapacity(address farmer) virtual override public view returns (uint[] memory amounts) {
        amounts = new uint[](2);
        amounts[0] = _harvestCapacity(farmer, _harvestDelta(),  sumRewardPer,  sumRewardPerOf[farmer]);
        amounts[1] = _harvestCapacity(farmer, _harvestDelta2(), sumReward2Per, sumReward2PerOf[farmer]);
    }    
    function _harvestDelta2() virtual internal view returns(uint amount) {
        amount = ICurveGauge(gauge).claimable_tokens(address(this));
    }
}


contract SFarm is IFarm, Governable {
    using TransferHelper for address;

    address override public crop;

	constructor(address governor, address crop_) public {
		initialize(governor, crop_);
	}
	
    function initialize(address governor, address crop_) public initializer {
        super.initialize(governor);
        crop = crop_;
    }
    
    function approvePool(address pool, uint amount) public governance {
        crop.safeApprove(pool, amount);
    }
    
}


interface ICurveGauge {
    function deposit(uint _value) external;
    function deposit(uint _value, address addr) external;
    function withdraw(uint _value) external;
    function withdraw(uint _value, bool claim_rewards) external;
    function claim_rewards() external;
    function claim_rewards(address addr) external;
    function claimable_reward(address addr) external view returns (uint);
    function claimable_tokens(address addr) external view returns (uint);
    function integrate_checkpoint() external view returns (uint);
}

interface ICurveMinter {
    function token() external view returns (address);
    function mint(address _gauge) external;
}


// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}

