// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IPool} from "aave-v3/interfaces/IPool.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {Staking} from "../src/Staking.sol";
import {ILiquidityBuffer} from "../src/liquidityBuffer/interfaces/ILiquidityBuffer.sol";
import {LiquidityBuffer} from "../src/liquidityBuffer/LiquidityBuffer.sol";
import {IWETH} from "../src/liquidityBuffer/interfaces/IWETH.sol";
import {PositionManager} from "../src/liquidityBuffer/PositionManager.sol";
import {PositionManager as OldPositionManagerNewImpl} from "../src/liquidityBuffer/OldPositionManagerNewImpl.sol";
import {initPositionManager,newProxy,EmptyContract} from "./liquidityBuffer.s.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "./helpers/TransparentUpgradeableProxy.sol";
import {console2} from "forge-std/console2.sol";
/**
 * @title MainnetIntegrationTest
 * @notice test mainnet integration
 */
contract MainnetIntegrationTest is Script {
    // owner address
    address public constant lsp_sec_msig = 0x849738999Ba1F3D995d28bDB35efA2E47B4c8203;
    address public constant mantle_sec_msig = 0x4e59e778a0fb77fBb305637435C62FaeD9aED40f;
    address public constant allocator_wallet = 0xC62cE6fDff7B1374971A5F6f04f4aabc464e1447;
    address public constant topup_wallet = 0x55b798738345290e99640a3e292D0D4b48d2CDa8;
    // upgrade address
    TimelockController public timelockController = TimelockController(payable(0xc26016f1166bE7b6c5611AAB104122E0f6c2aCE2));
    Staking public staking = Staking(payable(0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f));
    LiquidityBuffer public liquidityBuffer = LiquidityBuffer(payable(0x006FaD88c35D973A87E451CF8D000c7e83Dad409));
    PositionManager public oldPositionManager = PositionManager(payable(0xcF2d33883B60C80174B21d7013958076eCcCEC7A));
    PositionManager public newPositionManager;

    IWETH public weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IPool public aavePool = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    IERC20 public awETH = IERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    
    function run() public {
      _deployNewPositionManagerWithProxy();
      _addNewPositionManagerToLiquidityBuffer();
      _setDefaultManagerIdTo1();
      _upgradeOldPositionManagerSendAndReceiveETH();
      uint256 amount = awETH.balanceOf(address(oldPositionManager));
      _emergencyTokenTransferToMsigWallet(amount);
      _withdrawWETHFromAavePoolAndUnwrapWETHToETH(amount);
      _sendETHToOldPositionManagerAndCallSendETHToLiquidityBuffer(amount);
      _setPositionManagerStatusToInactive();
      uint256 newAmount = 10 ether;
      _allocateETHToManager(newAmount);
      _withdrawAndReturn(newAmount);
    }
    // 1. Deploy a new positionManager contract, proxy update receive method
    function _deployNewPositionManagerWithProxy() internal {
      console2.log("-----1. Deploy a new positionManager contract, proxy update receive method------");
      console2.log("===ethToMETH(1 ether): %s", staking.ethToMETH(1 ether));
      address deployer = 0x207E804758e28F2b3fD6E4219671B327100b82f8;// yoda wallet address
      EmptyContract empty = EmptyContract(0x8B6c86D2C0cc65CB4138CC01C97EC4E1D5712478);
      PositionManager pm = PositionManager(payable(address(newProxy(empty, deployer))));
      vm.startPrank(deployer);
      newPositionManager = initPositionManager(
        ITransparentUpgradeableProxy(address(pm)),
        PositionManager.Init({
            admin: lsp_sec_msig,
            manager: lsp_sec_msig,
            liquidityBuffer: ILiquidityBuffer(address(liquidityBuffer)),
            weth: weth,
            pool: aavePool
        })
      );
      vm.stopPrank();
      console2.log("deploy new positionManager with new proxy: %s", address(newPositionManager));
    }
    // 2. Add New PositionManager to liquidityBuffer
    function _addNewPositionManagerToLiquidityBuffer() internal {
      console2.log("-----2. Add New PositionManager to liquidityBuffer------");
      vm.prank(lsp_sec_msig);
      liquidityBuffer.addPositionManager(address(newPositionManager), 30000 ether);
      (address manager, uint256 allocationCap, bool isActive) = liquidityBuffer.positionManagerConfigs(1);
      console2.log("manager: %s", manager);
      console2.log("allocationCap: %s", allocationCap);
      console2.log("isActive: %s", isActive);
    }

    // 3. Call setDefaultManagerId to set default id to 1
    function _setDefaultManagerIdTo1() internal {
      console2.log("-----3. Call setDefaultManagerId to set default id to 1------");
      vm.prank(lsp_sec_msig);
      liquidityBuffer.setDefaultManagerId(1);
      console2.log("default manager id: %s", liquidityBuffer.defaultManagerId());
    }

    // 4. Upgrade Old PositionManager add sendETHToLiquidityBuffer method
    function _upgradeOldPositionManagerSendAndReceiveETH() internal {
      console2.log("-----4. Upgrade Old PositionManager add sendETHToLiquidityBuffer and receiveETHFromManager method------");
      OldPositionManagerNewImpl oldPositionManagerNewImpl = new OldPositionManagerNewImpl();
      vm.startPrank(mantle_sec_msig);
      bytes memory callData = abi.encodeCall(ITransparentUpgradeableProxy.upgradeToAndCall, (address(oldPositionManagerNewImpl), ""));
      _scheduleAndExecute(timelockController, address(oldPositionManager), 0, callData);
      vm.stopPrank();
      console2.log("old positionManager new implementation: %s", address(oldPositionManagerNewImpl));
    }

    function _scheduleAndExecute(TimelockController controller, address target, uint256 value, bytes memory data) internal {
      controller.schedule({target: target, value: value, data: data, predecessor: bytes32(0), delay: 0, salt: bytes32(0)});
      controller.execute{value: value}({
          target: target,
          value: value,
          payload: data,
          predecessor: bytes32(0),
          salt: bytes32(0)
      });
    } 

    // 5. GrantRole EMERGENCY_ROLE to lsp_sec_msig and Call emergencyTokenTransfer to transfer aWETH to msig wallet 
    function _emergencyTokenTransferToMsigWallet(uint256 amount) internal {
      console2.log("-----5 GrantRole EMERGENCY_ROLE to lsp_sec_msig and Call emergencyTokenTransfer to transfer aWETH to msig wallet ------");
      vm.startPrank(lsp_sec_msig);
      oldPositionManager.grantRole(oldPositionManager.EMERGENCY_ROLE(), lsp_sec_msig);
      console2.log("===before emergencyTokenTransfer ethToMETH(1 ether): %s", staking.ethToMETH(1 ether));
      oldPositionManager.emergencyTokenTransfer(address(awETH), lsp_sec_msig, amount);
      console2.log("===after emergencyTokenTransfer ethToMETH(1 ether): %s", staking.ethToMETH(1 ether));
      vm.stopPrank();
      console2.log("msig wallet aWETH balance: %s", awETH.balanceOf(lsp_sec_msig));
    }

    // 6. Call withdraw to withdraw wETH from AAVE Pool and call withdraw to Unwrap WETH to ETH
    function _withdrawWETHFromAavePoolAndUnwrapWETHToETH(uint256 amount) internal {
      console2.log("-----6. Call withdraw to withdraw wETH from AAVE Pool and call withdraw to Unwrap WETH to ETH------");
      // console log lsp_sec_msig address ETH balance
      console2.log("lsp_sec_msig address ETH balance: %s", address(lsp_sec_msig).balance);
      vm.startPrank(lsp_sec_msig);
      aavePool.withdraw(address(weth), amount, lsp_sec_msig);
      console2.log("msig wallet wETH balance: %s", IERC20(address(weth)).balanceOf(lsp_sec_msig));
      // weth.withdraw(amount); // will get an error: [Revert] EvmError: Revert, because we don't get the Safe contract, just mock lsp_sec_msig as a normal address
      vm.deal(address(lsp_sec_msig), amount);
      console2.log("msig wallet ETH balance: %s", address(lsp_sec_msig).balance);
      vm.stopPrank();
      console2.log("===ethToMETH(1 ether): %s", staking.ethToMETH(1 ether));
    }
    
    // 7. Send ETH to Old PositionManager Then call withdrawAndReturn and claimInterestAndTopUp to return principal and interest to staking contract
    function _sendETHToOldPositionManagerAndCallSendETHToLiquidityBuffer(uint256 amount) internal {
      console2.log("-----7. Grant topup role to liquidityBuffer in Staking Contract, then Send ETH to Old PositionManager Then call withdrawAndReturn and claimInterestAndTopUp to return principal and interest to staking contract------");
      vm.prank(lsp_sec_msig);
      OldPositionManagerNewImpl(payable(address(oldPositionManager))).receiveETHFromManager{value: amount}();
      console2.log("before execute staking ETH balance: %s", address(staking).balance);
      uint256 principalBalance = liquidityBuffer.getAvailableBalance();
      console2.log("principalBalance: %s", principalBalance);
      uint256 interestAmount = liquidityBuffer.getInterestAmount(0);
      console2.log("interestAmount: %s", interestAmount);

      vm.prank(allocator_wallet);
      liquidityBuffer.withdrawAndReturn(0, principalBalance);
      vm.startPrank(mantle_sec_msig);
      staking.grantRole(staking.TOP_UP_ROLE(), address(liquidityBuffer));
      vm.stopPrank();
      console2.log("===before topup interest ethToMETH(1 ether): %s", staking.ethToMETH(1 ether));
      vm.prank(topup_wallet);
      liquidityBuffer.claimInterestAndTopUp(0, interestAmount);
      console2.log("===after topup interest ethToMETH(1 ether): %s", staking.ethToMETH(1 ether));
      console2.log("oldPositionManager ETH balance: %s", address(oldPositionManager).balance);
      console2.log("liquidityBuffer ETH balance: %s", address(liquidityBuffer).balance);
      console2.log("after execute staking ETH balance: %s", address(staking).balance);
    }

    // 8. Call setPositionManagerStatus to set old PositionManager to inActive
    function _setPositionManagerStatusToInactive() internal {
      console2.log("-----8. Call setPositionManagerStatus to set old PositionManager to inActive------");
      vm.prank(lsp_sec_msig);
      liquidityBuffer.setPositionManagerStatus(0, false);
      (address manager, uint256 allocationCap, bool isActive) = liquidityBuffer.positionManagerConfigs(0);
      console2.log("--old PositionManager status--");
      console2.log("manager: %s", manager);
      console2.log("allocationCap: %s", allocationCap);
      console2.log("isActive: %s", isActive);
      (uint256 allocatedBalance, uint256 interestClaimedFromManager) = liquidityBuffer.positionAccountants(0);
      console2.log("--old PositionManager accountant--");
      console2.log("allocatedBalance: %s", allocatedBalance);
      console2.log("interestClaimedFromManager: %s", interestClaimedFromManager);
      console2.log("totalAllocatedBalance: %s", liquidityBuffer.totalAllocatedBalance());
    }
    // 9. Call allocateETH to allocate ETH to new PositionManager
    function _allocateETHToManager(uint256 amount) internal {
      console2.log("-----9. Call allocateETH to allocate 10 ETH to new PositionManager------");
      vm.prank(allocator_wallet);
      console2.log("before allocateETH staking ETH balance: %s", address(staking).balance);
      staking.allocateETH(0, 0, amount);
      console2.log("after allocateETH staking ETH balance: %s", address(staking).balance);
      (uint256 allocatedBalance, uint256 interestClaimedFromManager) = liquidityBuffer.positionAccountants(1);
      console2.log("PM1 allocatedBalance: %s", allocatedBalance);
      console2.log("PM1 interestClaimedFromManager: %s", interestClaimedFromManager);
      console2.log("LB totalAllocatedBalance: %s", liquidityBuffer.totalAllocatedBalance());
    }
    // 10. Call withdrawAndReturn to withdraw ETH from new PositionManager
    function _withdrawAndReturn(uint256 amount) internal {
      console2.log("-----10. Call withdrawAndReturn to withdraw ETH from new PositionManager------");
      vm.startPrank(allocator_wallet);
      console2.log("liquidityBuffer getAvailableBalance: %s", liquidityBuffer.getAvailableBalance());
      console2.log("liquidityBuffer getInterestAmount: %s", liquidityBuffer.getInterestAmount(1));
      console2.log("getUnderlyingBalance: %s", newPositionManager.getUnderlyingBalance());
      if (newPositionManager.getUnderlyingBalance() > amount) {
        liquidityBuffer.withdrawAndReturn(1, amount);
      } else {
        liquidityBuffer.withdrawAndReturn(1, newPositionManager.getUnderlyingBalance());
      }
      vm.stopPrank();
      console2.log("staking ETH balance: %s", address(staking).balance);
    }
}
