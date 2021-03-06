// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./SMinter.sol";
import "./Proxy.sol";

contract CurveGauge is SSimpleGauge {

	function initialize(address governor, address _minter, address _lp_token, address _rewarded_token) public initializer {
	    super.initialize(governor, _minter, _lp_token);
	    
	    rewarded_token = _rewarded_token;
	    IERC20(_rewarded_token).totalSupply();           // just check
	}
    
    function claim_rewards(address addr) override public {
        rewarded_token.safeTransfer(addr, 10000);
    }
    function claimable_reward(address addr) override public view returns (uint) {
        addr;
        return 10000;
    }
}


contract CurveToken is ERC20 {

	constructor(address recipient) ERC20("CRV Token for Test", "CRV") public {
		uint8 decimals = 0;
		_setupDecimals(decimals);
		
		_mint(recipient,  1000000 * 10 ** uint256(decimals));
	}
}


contract RewardToken is ERC20 {

	constructor(address recipient) ERC20("SNX Reward for Test", "SNX") public {
		uint8 decimals = 0;
		_setupDecimals(decimals);
		
		_mint(recipient,  1000000 * 10 ** uint256(decimals));
	}
}


contract LPToken is ERC20 {

	constructor(address recipient) ERC20("LPToken for Test", "LPT") public {
		uint8 decimals = 0;
		_setupDecimals(decimals);
		
		_mint(recipient,  1000000 * 10 ** uint256(decimals));
	}
}


struct S {
    address adminProxy;
    address admin;
    
    address pcMinter;
    address pcsGauge;
    address pgMinter;
    address pgsGauge;
    //address pyMinter;
    
    address CRV;
    address SNX;
    address SFG;
    address LPT;
    
    address cMinter;
    address gMinter;
    address csGauge;
    address gsGauge;
}
    
contract DeployMinter {
    event Deploy(string name, address addr);
    
    //function deploy(address adminProxy, address admin) public {
    constructor(address adminProxy, address admin) public {
        S memory s;
        
        //s.pcMinter  = address(new InitializableAdminUpgradeabilityProxy());             
        //s.pcsGauge  = address(new InitializableAdminUpgradeabilityProxy());             
        s.pgMinter  = address(new InitializableAdminUpgradeabilityProxy());             
        s.pgsGauge  = address(new InitializableAdminUpgradeabilityProxy());             
        //s.pyMinter  = address(new InitializableAdminUpgradeabilityProxy());             
        
        //s.CRV       = address(new CurveToken(  s.pcMinter ));                           
        //s.SNX       = address(new RewardToken( s.pcsGauge ));                           
        s.SFG       = address(new SfgToken(    s.pgMinter ));                           
        //s.LPT       = address(new LPToken(     admin      ));                           

        //s.cMinter   = address(new SMinter());                                           
        s.gMinter   = address(new SMinter());                                           

        //emit Deploy('pcMinter', s.pcMinter);
        //emit Deploy('pcsGauge', s.pcsGauge);
        emit Deploy('pgMinter', s.pgMinter);
        emit Deploy('pgsGauge', s.pgsGauge);
        //emit Deploy('pyMinter', s.pyMinter);
        //emit Deploy('CRV', s.CRV);
        //emit Deploy('SNX', s.SNX);
        emit Deploy('SFG', s.SFG);
        //emit Deploy('LPT', s.LPT);
        //emit Deploy('cMinter', s.cMinter);
        emit Deploy('gMinter', s.gMinter);
        
        selfdestruct(msg.sender);
    }
}
    
contract DeployGauge {
    event Deploy(bytes32 name, address addr);
    
    //constructor(address adminProxy, address admin, S memory s) public {
    //function deploy(address adminProxy, address admin, S memory s) public {
    function deploy(address adminProxy, address admin, address pgMinter, address pgsGauge, address SFG, address gMinter) public {
        S memory s;
        s.pgMinter  = pgMinter;
        s.pgsGauge  = pgsGauge;
        s.SFG       = SFG;
        s.gMinter   = gMinter;
        
        s.pcMinter  = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;
        s.pcsGauge  = 0xA90996896660DEcC6E997655E065b23788857849;
        s.CRV       = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        s.SNX       = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
        s.LPT       = 0xC25a3A3b969415c80451098fa907EC722572917F;
        //s.cMinter   = ;
        
        //s.csGauge   = address(new CurveGauge());                                        emit Deploy('csGauge', s.csGauge);
        s.gsGauge   = address(new SNestGauge());                                        emit Deploy('gsGauge', s.gsGauge);
        
        //IProxy(s.pcMinter).initialize(adminProxy, s.cMinter, abi.encodeWithSignature('initialize(address,address)', address(this), s.CRV));
        //IProxy(s.pcsGauge).initialize(adminProxy, s.csGauge, abi.encodeWithSignature('initialize(address,address,address,address)', address(this), s.pcMinter, s.LPT, s.SNX));
        IProxy(s.pgMinter).initialize(adminProxy, s.gMinter, abi.encodeWithSignature('initialize(address,address)', address(this), s.SFG));
        IProxy(s.pgsGauge).initialize(adminProxy, s.gsGauge, abi.encodeWithSignature('initialize(address,address,address,address,address[])', address(this), s.pgMinter, s.LPT, s.pcsGauge, new address[](0)));
        
        //SMinter(s.pcMinter).setGaugeQuota(s.pcsGauge, IERC20(s.CRV).totalSupply());
        //CurveGauge(s.pcsGauge).setSpan(IERC20(s.CRV).totalSupply(), true);
        
        SMinter(s.pgMinter).setGaugeQuota(s.pgsGauge, IERC20(s.SFG).totalSupply());
        SNestGauge(s.pgsGauge).setSpan(IERC20(s.SFG).totalSupply() / 1 ether, false);
        
        SNestGauge(s.pgsGauge).setConfig('devAddr', uint(msg.sender));
        SNestGauge(s.pgsGauge).setConfig('devRatio', 0.05 ether);
        SNestGauge(s.pgsGauge).setConfig('ecoAddr', uint(0x445DfB4d52b7BCA4557Dd6df8ca8D2D2a7a832d6));
        SNestGauge(s.pgsGauge).setConfig('ecoRatio', 0.05 ether);

        //Governable(s.pcMinter).transferGovernorship(admin);
        //Governable(s.pcsGauge).transferGovernorship(admin);
        Governable(s.pgMinter).transferGovernorship(admin);
        Governable(s.pgsGauge).transferGovernorship(admin);

        selfdestruct(msg.sender);
    }
}

contract DeployPool2 {
    event Deploy(bytes32 name, address addr);
    
    constructor(address adminProxy, address admin, address pgMinter, address LPT) public {
        address proxy  = address(new InitializableAdminUpgradeabilityProxy());             
        address gauge = address(new SExactGauge());

        IProxy(proxy).initialize(adminProxy, gauge, abi.encodeWithSignature('initialize(address,address,address)', address(this), pgMinter, LPT));
        
        SExactGauge(proxy).setSpan(5000 days, false);

        SExactGauge(proxy).setConfig('devAddr', uint(admin));
        SExactGauge(proxy).setConfig('devRatio', 0.05 ether);
        SExactGauge(proxy).setConfig('ecoAddr', uint(0x3F55534FCe61474AF125c19C752448dc225f081f));
        SExactGauge(proxy).setConfig('ecoRatio', 0.05 ether);

        Governable(proxy).transferGovernorship(admin);

        emit Deploy('proxy', proxy);
        emit Deploy('gauge', gauge);
    
        selfdestruct(msg.sender);
    }
}

contract DeployHelper {
    constructor() public {
        S memory s;
        
        s.adminProxy= 0x3F55534FCe61474AF125c19C752448dc225f081f;       // 15
        s.admin     = 0x71e3216f355113d2DA7f27C9c5B0F83c816fb04B;       // 16
        
        s.pgMinter  = 0x3b46D3C8Aea72575C2C17f5604A0916e5A994A3b;
        s.pgsGauge  = 0xA8EeDB4201bC2951dc8946C0A139ffd0b5E8CBfB;
        s.SFG       = 0x8a6ACA71A218301c7081d4e96D64292D3B275ce0;
        s.gMinter   = 0x4ebBcE881f5f233c4bF68328E9bB98BeE4985680;
        s.gsGauge   = 0x41517D4102Cc6ddB4f6daCf19284E6CA54aad0AB;
        
        s.pcMinter  = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;
        s.pcsGauge  = 0xA90996896660DEcC6E997655E065b23788857849;
        s.CRV       = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        s.SNX       = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
        s.LPT       = 0xC25a3A3b969415c80451098fa907EC722572917F;

        IProxy(s.pgMinter).initialize(s.adminProxy, s.gMinter, abi.encodeWithSignature('initialize(address,address)', address(this), s.SFG));
        IProxy(s.pgsGauge).initialize(s.adminProxy, s.gsGauge, abi.encodeWithSignature('initialize(address,address,address,address,address[])', address(this), s.pgMinter, s.LPT, s.pcsGauge, new address[](0)));

        SMinter(s.pgMinter).setGaugeQuota(s.pgsGauge, IERC20(s.SFG).totalSupply());
        //SNestGauge(s.pgsGauge).setSpan(5000 days, false);
        
        SNestGauge(s.pgsGauge).setConfig('devAddr', uint(0x0Cc674efa6a477fa52b31eFA10633A9428Afb022));
        SNestGauge(s.pgsGauge).setConfig('devRatio', 0.05 ether);
        SNestGauge(s.pgsGauge).setConfig('ecoAddr', uint(0x46287423a6939c1393e1078eE4A5656f733f80F2));
        SNestGauge(s.pgsGauge).setConfig('ecoRatio', 0.05 ether);

        Governable(s.pgMinter).transferGovernorship(s.admin);
        Governable(s.pgsGauge).transferGovernorship(s.admin);

        selfdestruct(msg.sender);
    }
}

interface IProxy {
    function initialize(address _admin, address _logic, bytes memory _data) external payable;
}
