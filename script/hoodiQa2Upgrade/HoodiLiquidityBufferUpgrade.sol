// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Staking} from "../../src/Staking.sol";
import {IPauserRead} from "../../src/interfaces/IPauser.sol";
import {IStakingReturnsWrite} from "../../src/interfaces/IStaking.sol";
import {LiquidityBuffer} from "../../src/liquidityBuffer/LiquidityBuffer.sol";
import {PositionManager} from "../../src/liquidityBuffer/PositionManager.sol";
import {ILiquidityBuffer} from "../../src/liquidityBuffer/interfaces/ILiquidityBuffer.sol";
import {IWETH} from "../../src/liquidityBuffer/interfaces/IWETH.sol";
import {MockPool} from "../../test/doubles/MockAavePool.sol";
import {WETH} from "../../test/doubles/WETH.sol";
import {IPool} from "aave-v3/interfaces/IPool.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Script} from "forge-std/Script.sol";
import {StdChains} from "forge-std/StdChains.sol";
import {StdCheatsSafe} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

contract HoodiLiquidityBufferUpgrade is Script {
    uint256 liquidityBufferAdminPrivateKey = uint256(0xc5d4e51d1b26ead66d28ba807168ecf47273fec0d32db8ab15b729a1ca8d7);
    uint256 liquidityBufferOwnerPrivateKey = uint256(0x14221b49f87827c8ba4c58888a66ebda6379d004fcf12d46f7136388acb8e36a);
    uint256 originalDeployerPrivateKey = uint256(0xac9513ad671e8f0354ec7c8394588c6a2d4a8d41148cabec4fd4452b1983bea2);
    address public lbAdmin = vm.addr(liquidityBufferAdminPrivateKey);
    address public lbOwner = vm.addr(liquidityBufferOwnerPrivateKey);
    TimelockController public stakingAdmin = TimelockController(payable(0x1ceB9049A1E8de1f33dB308a4F21E2FB161711fA));
    Staking public staking;
    WETH public weth;
    MockPool public aavePool;
    PositionManager public aavePM;
    LiquidityBuffer public buffer;

    function run() public {
        vm.startBroadcast();

        staking = Staking(payable(0x20Af67691cE2eD4e502e5b0746C89F7d42740ed9));
        address newStakingImpl = address(new Staking());
        weth = new WETH();
        aavePool = new MockPool(address(weth));

        address bufferImpl = address(new LiquidityBuffer());
        buffer = LiquidityBuffer(payable(address(new TransparentUpgradeableProxy(
            bufferImpl,
            lbAdmin,
            abi.encodeCall(
                LiquidityBuffer.initialize,
                (
                    LiquidityBuffer.Init(
                    lbOwner,
                    lbOwner,
                    lbOwner,
                    lbOwner,
                    lbOwner,
                    payable(lbOwner),
                    IStakingReturnsWrite(address(staking)),
                    IPauserRead(address(0x62f89b3A5AeB42F646A15E769885158cdc95951d))
                )
                )
            )
        ))));

        address aavePMImpl = address(new PositionManager());
        aavePM = PositionManager(payable(address(new TransparentUpgradeableProxy(
            aavePMImpl,
            lbAdmin,
            abi.encodeCall(
                PositionManager.initialize,
                (
                    PositionManager.Init(
                    lbOwner,
                    lbOwner,
                    ILiquidityBuffer(address(buffer)),
                    IWETH(address(weth)),
                    IPool(address(aavePool))
                )
                )
            )
        ))));

        vm.stopBroadcast();

        vm.broadcast(liquidityBufferOwnerPrivateKey);
        buffer.addPositionManager(address(aavePM), 10000 ether);

        vm.startBroadcast(originalDeployerPrivateKey);
        bytes memory initiateData = abi.encodeCall(
            Staking.initializeV2,
            (
                ILiquidityBuffer(address(buffer))
            )
        );
        bytes memory updateData = abi.encodeCall(
            ITransparentUpgradeableProxy.upgradeToAndCall,
            (
                address(newStakingImpl),
                initiateData
            )
        );

        stakingAdmin.schedule(
            address(staking),
            0,
            updateData,
            bytes32(0),
            bytes32(0),
            uint256(0)
        );

        stakingAdmin.execute(
            address(staking),
            0,
            updateData,
            bytes32(0),
            bytes32(0)
        );
    }

    function run1() public {
        vm.startBroadcast();

        address newStakingImpl = address(new Staking());
    }

}