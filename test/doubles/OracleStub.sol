// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IOracleReadRecord, OracleRecord} from "../../src/interfaces/IOracle.sol";

contract OracleStub is IOracleReadRecord {
    OracleRecord[] internal _records;

    constructor() {
        OracleRecord memory zero;
        pushRecord(zero);
    }

    function setRecords(OracleRecord[] memory records) public {
        delete _records;
        for (uint256 i; i < records.length; ++i) {
            _records.push(records[i]);
        }
    }

    function pushRecord(OracleRecord memory record) public {
        _records.push(record);
    }

    function latestRecord() public view returns (OracleRecord memory) {
        return _records[_records.length - 1];
    }

    function recordAt(uint256 idx) public view returns (OracleRecord memory) {
        return _records[idx];
    }

    function numRecords() public view returns (uint256) {
        return _records.length;
    }
}
