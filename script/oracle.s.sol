// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {stdJson} from "forge-std/Script.sol";
import {Base} from "./base.s.sol";
import {Staking, Deployments} from "./helpers/Proxy.sol";

import {OracleRecord} from "../src/Oracle.sol";

contract SteerOracle is Base {
    using stdJson for string;

    function setFinalizationBlockNumberDelta(uint256 finalizationBlockNumberDelta) public {
        Deployments memory depls = readDeployments();

        require(
            depls.oracle.hasRole(depls.oracle.ORACLE_MANAGER_ROLE(), msg.sender), "sender is not ORACLE_MANAGER_ROLE"
        );

        vm.startBroadcast();
        depls.oracle.setFinalizationBlockNumberDelta(finalizationBlockNumberDelta);
        vm.stopBroadcast();
    }

    function setMinReportSizeBlocks(uint16 minReportSizeBlocks) public {
        Deployments memory depls = readDeployments();

        require(
            depls.oracle.hasRole(depls.oracle.ORACLE_MANAGER_ROLE(), msg.sender), "sender is not ORACLE_MANAGER_ROLE"
        );

        vm.startBroadcast();
        depls.oracle.setMinReportSizeBlocks(minReportSizeBlocks);
        vm.stopBroadcast();
    }

    function setMaxConsensusLayerGainPerBlockPPT(uint40 maxConsensusLayerGainPerBlockPPT) public {
        Deployments memory depls = readDeployments();

        require(
            depls.oracle.hasRole(depls.oracle.ORACLE_MANAGER_ROLE(), msg.sender), "sender is not ORACLE_MANAGER_ROLE"
        );

        vm.startBroadcast();
        depls.oracle.setMaxConsensusLayerGainPerBlockPPT(maxConsensusLayerGainPerBlockPPT);
        vm.stopBroadcast();
    }

    function modifyOracleRecords(string calldata pathToJson) public {
        Deployments memory depls = readDeployments();

        require(depls.oracle.hasRole(depls.oracle.ORACLE_MODIFIER_ROLE(), msg.sender), "sender cannot modify records");

        string memory json = _readRecords(pathToJson);
        uint256 numRecords = json.readUint(".numRecords");
        uint256 startIdx = json.readUint(".startIndex");

        vm.startBroadcast();
        for (uint256 i = 0; i < numRecords; i++) {
            OracleRecord memory record = _parseRecord(json, i);
            uint256 recordIdx = startIdx + i;
            depls.oracle.modifyExistingRecord(recordIdx, record);
        }
        vm.stopBroadcast();
    }

    function _parseRecord(string memory json, uint256 idx) internal returns (OracleRecord memory) {
        string memory baseKey = string.concat(".records[", vm.toString(idx), "].");
        OracleRecord memory record = OracleRecord({
            updateStartBlock: uint64(json.readUint(string.concat(baseKey, "UpdateStartBlock"))),
            updateEndBlock: uint64(json.readUint(string.concat(baseKey, "UpdateEndBlock"))),
            currentNumValidatorsNotWithdrawable: uint64(
                json.readUint(string.concat(baseKey, "CurrentNumValidatorsNotWithdrawable"))
                ),
            cumulativeNumValidatorsWithdrawable: uint64(
                json.readUint(string.concat(baseKey, "CumulativeNumValidatorsWithdrawable"))
                ),
            windowWithdrawnPrincipalAmount: uint128(json.readUint(string.concat(baseKey, "WindowWithdrawnPrincipalAmount"))),
            windowWithdrawnRewardAmount: uint128(json.readUint(string.concat(baseKey, "WindowWithdrawnRewardAmount"))),
            currentTotalValidatorBalance: uint128(json.readUint(string.concat(baseKey, "CurrentTotalValidatorBalance"))),
            cumulativeProcessedDepositAmount: uint128(
                json.readUint(string.concat(baseKey, "CumulativeProcessedDepositAmount"))
                )
        });
        return record;
    }

    function _readRecords(string calldata relativePathToJson) internal view returns (string memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", relativePathToJson);
        string memory json = vm.readFile(path);
        return json;
    }
}
