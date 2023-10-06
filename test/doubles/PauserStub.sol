// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPauser} from "../../src/interfaces/IPauser.sol";

contract PauserStub is IPauser {
    bool public isStakingPaused = false;
    bool public isUnstakeRequestsAndClaimsPaused = false;
    bool public isInitiateValidatorsPaused = false;
    bool public isSubmitOracleRecordsPaused = false;
    bool public isAllocateETHPaused = false;
    bool public isProcessRecordsPaused = false;

    function pauseAll() external {}
}
