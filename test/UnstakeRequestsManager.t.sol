// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.sol";

import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import {METH, IMETH} from "../src/METH.sol";
import {UnstakeRequestsManager, UnstakeRequestsManagerEvents, UnstakeRequest} from "../src/UnstakeRequestsManager.sol";
import {Staking} from "../src/Staking.sol";
import {newMETH, newUnstakeRequestsManager} from "./utils/Deploy.sol";
import {ReentrancyForwarder} from "./utils/Reentrancy.sol";
import {upgradeToAndCall} from "../script/helpers/Proxy.sol";

import {StakingStub} from "./doubles/StakingStub.sol";
import {OracleStub, OracleRecord} from "./doubles/OracleStub.sol";

contract TestableUnstakeRequestsManager is UnstakeRequestsManager {
    function setUnstakeRequests(UnstakeRequest[] memory requests) public {
        delete _unstakeRequests;
        for (uint256 i = 0; i < requests.length; i++) {
            _unstakeRequests.push(requests[i]);
        }
    }

    function setLatestCumulativeETHRequested(uint128 latestCumulativeETHRequested_) public {
        latestCumulativeETHRequested = latestCumulativeETHRequested_;
    }
}

contract UnstakeRequestsManagerTest is BaseTest, UnstakeRequestsManagerEvents {
    address public immutable manager = makeAddr("manager");
    address public immutable requestCanceller = makeAddr("requestCanceller");
    address public immutable requester = makeAddr("requester");
    address public immutable vandal = makeAddr("vandal");

    TestableUnstakeRequestsManager public tUnstakeRequests;
    UnstakeRequestsManager public unstakeRequestsManager;
    OracleStub public oracle;
    StakingStub public staking;
    METH public mETH;

    struct SampleRequest {
        address requester;
        uint128 mETHLocked;
        uint128 ethRequested;
    }

    SampleRequest public generalTest;
    UnstakeRequest public emptyRequest = UnstakeRequest({
        id: 0,
        requester: address(0),
        mETHLocked: 0,
        ethRequested: 0,
        cumulativeETHRequested: 0,
        blockNumber: 0
    });

    function setUp() public {
        oracle = new OracleStub();
        staking = new StakingStub();

        // Create proxy manually because we use stubbed version of the URM
        TestableUnstakeRequestsManager _urm = new TestableUnstakeRequestsManager();
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(
            address(
                new TransparentUpgradeableProxy(
                    address(_urm),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        mETH = newMETH(
            proxyAdmin,
            METH.Init({
                admin: admin,
                staking: staking,
                unstakeRequestsManager: UnstakeRequestsManager(payable(address(proxy)))
            })
        );

        UnstakeRequestsManager.Init memory init = UnstakeRequestsManager.Init({
            admin: admin,
            manager: manager,
            requestCanceller: requestCanceller,
            mETH: mETH,
            oracle: oracle,
            stakingContract: staking,
            numberOfBlocksToFinalize: 100
        });

        upgradeToAndCall(proxyAdmin, proxy, address(_urm), abi.encodeCall(UnstakeRequestsManager.initialize, init));
        unstakeRequestsManager = UnstakeRequestsManager(payable(address(proxy)));
        tUnstakeRequests = TestableUnstakeRequestsManager(payable(unstakeRequestsManager));

        generalTest = SampleRequest({requester: requester, mETHLocked: 0.1 ether, ethRequested: 0.1 ether});
    }

    function createRequest() public returns (uint256) {
        uint256 requestID = createRequest(generalTest);
        return requestID;
    }

    function createRequest(SampleRequest memory request) public returns (uint256) {
        vm.prank(address(staking));
        uint256 requestID = unstakeRequestsManager.create({
            requester: request.requester,
            mETHLocked: request.mETHLocked,
            ethRequested: request.ethRequested
        });
        return requestID;
    }

    function assertEq(UnstakeRequest memory got, UnstakeRequest memory want) internal {
        assertEq(got.requester, want.requester);
        assertEq(got.blockNumber, want.blockNumber);
        assertEq(got.mETHLocked, want.mETHLocked);
        assertEq(got.ethRequested, want.ethRequested);
        assertEq(got.cumulativeETHRequested, want.cumulativeETHRequested);
        assertEq(keccak256(abi.encode(got)), keccak256(abi.encode(want)));
    }

    function _mintMETH(uint256 amount) internal {
        _mintMETH(address(staking), amount);
    }

    function _mintMETH(address to, uint256 amount) internal {
        vm.prank(address(staking));
        mETH.mint(to, amount);
    }

    // Mocks the Staking contract.
    function receiveFromUnstakeRequestsManager() external payable {}
}

contract UnstakeRequestsSettersTest is UnstakeRequestsManagerTest {
    function testSetNumberOfBlocksToFinalize(uint256 numOfBlocks) public {
        expectProtocolConfigEvent(
            address(unstakeRequestsManager), "setNumberOfBlocksToFinalize(uint256)", abi.encode(numOfBlocks)
        );

        vm.prank(manager);
        unstakeRequestsManager.setNumberOfBlocksToFinalize(numOfBlocks);
        assertEq(unstakeRequestsManager.numberOfBlocksToFinalize(), numOfBlocks);
    }
}

contract UnstakeRequestsVandalTest is UnstakeRequestsManagerTest {
    function testSetNumberOfBlocksToFinalizeUnauthorized(uint256 numberOfBlocks) public {
        assumeMissingRolePrankAndExpectRevert(
            vandal, address(unstakeRequestsManager), unstakeRequestsManager.MANAGER_ROLE()
        );
        unstakeRequestsManager.setNumberOfBlocksToFinalize(numberOfBlocks);
    }

    function testCreateUnauthorized(address requester_, uint128 mETHLocked, uint128 ethRequested) public {
        vm.expectRevert(UnstakeRequestsManager.NotStakingContract.selector);
        vm.prank(vandal);
        unstakeRequestsManager.create(requester_, mETHLocked, ethRequested);
    }

    function testClaimUnauthorized(uint256 requestID, address requester_) public {
        vm.expectRevert(UnstakeRequestsManager.NotStakingContract.selector);
        vm.prank(vandal);
        unstakeRequestsManager.claim(requestID, requester_);
    }

    function testAllocateETHUnauthorized(uint256 value) public {
        vm.deal(vandal, value);
        vm.expectRevert(UnstakeRequestsManager.NotStakingContract.selector);
        vm.prank(vandal);
        unstakeRequestsManager.allocateETH{value: value}();
    }

    function testWithdrawAllocatedETHSurplusUnauthorized() public {
        vm.expectRevert(UnstakeRequestsManager.NotStakingContract.selector);
        vm.prank(vandal);
        unstakeRequestsManager.withdrawAllocatedETHSurplus();
    }

    function testCancelUnfinalizedRequestsUnauthorized(uint256 maxCancel) public {
        assumeMissingRolePrankAndExpectRevert(
            vandal, address(unstakeRequestsManager), unstakeRequestsManager.REQUEST_CANCELLER_ROLE()
        );
        unstakeRequestsManager.cancelUnfinalizedRequests(maxCancel);
    }
}

contract UnstakeRequestsAllocateETHTest is UnstakeRequestsManagerTest {
    function testAllocateETH() public {
        uint256 value = 0.5 ether;
        vm.deal(address(staking), value);

        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: value}();
        assertEq(unstakeRequestsManager.allocatedETHForClaims(), value);
    }

    function testAllocateETHMultiple() public {
        uint128 firstAllocation = 0.5 ether;
        uint128 secondAllocation = 1 ether;
        vm.deal(address(staking), uint256(firstAllocation) + secondAllocation);

        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: firstAllocation}();
        assertEq(unstakeRequestsManager.allocatedETHForClaims(), firstAllocation);

        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: secondAllocation}();
        assertEq(unstakeRequestsManager.allocatedETHForClaims(), uint256(firstAllocation) + secondAllocation);
    }

    function testAllocateETHFuzzed(uint256 value) public {
        vm.deal(address(staking), value);

        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: value}();
        assertEq(unstakeRequestsManager.allocatedETHForClaims(), value);
    }

    function testAllocateETHFuzzedMultiple(uint128 firstAllocation, uint128 secondAllocation) public {
        vm.deal(address(staking), uint256(firstAllocation) + secondAllocation);

        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: firstAllocation}();
        assertEq(unstakeRequestsManager.allocatedETHForClaims(), firstAllocation);

        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: secondAllocation}();
        assertEq(unstakeRequestsManager.allocatedETHForClaims(), uint256(firstAllocation) + secondAllocation);
    }
}

contract UnstakeRequestsBalanceCalculationsTest is UnstakeRequestsManagerTest {
    function testCalculateAllocateETHDeficit() public {
        vm.deal(address(staking), 1 ether);
        assertEq(unstakeRequestsManager.allocatedETHDeficit(), 0);

        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: 0.5 ether}();
        assertEq(unstakeRequestsManager.allocatedETHDeficit(), 0);

        vm.prank(address(staking));
        unstakeRequestsManager.create({
            requester: generalTest.requester,
            mETHLocked: generalTest.mETHLocked,
            ethRequested: 1 ether
        });
        assertEq(unstakeRequestsManager.allocatedETHDeficit(), 1 ether - 0.5 ether);

        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: 0.5 ether}();
        assertEq(unstakeRequestsManager.allocatedETHDeficit(), 0);
    }

    function testCalculateAllocatedETHSurplus() public {
        vm.deal(address(staking), 1.5 ether);
        assertEq(unstakeRequestsManager.allocatedETHSurplus(), 0);

        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: 0.5 ether}();
        assertEq(unstakeRequestsManager.allocatedETHSurplus(), 0.5 ether);

        vm.prank(address(staking));
        unstakeRequestsManager.create({
            requester: generalTest.requester,
            mETHLocked: generalTest.mETHLocked,
            ethRequested: 1 ether
        });
        assertEq(unstakeRequestsManager.allocatedETHSurplus(), 0);

        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: 1 ether}();
        assertEq(unstakeRequestsManager.allocatedETHSurplus(), 0.5 ether);
    }

    function testCalculateBalance() public {
        vm.deal(address(staking), 0.5 ether);
        assertEq(unstakeRequestsManager.balance(), 0);

        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: 0.5 ether}();
        assertEq(unstakeRequestsManager.balance(), 0.5 ether);

        vm.prank(address(staking));
        uint256 requestID = unstakeRequestsManager.create({
            requester: generalTest.requester,
            mETHLocked: generalTest.mETHLocked,
            ethRequested: 0.5 ether
        });
        assertEq(unstakeRequestsManager.balance(), 0.5 ether);

        OracleRecord memory record;
        record.updateEndBlock = uint64(block.number + unstakeRequestsManager.numberOfBlocksToFinalize());
        oracle.pushRecord(record);

        _mintMETH(address(unstakeRequestsManager), generalTest.mETHLocked);

        vm.prank(address(staking));
        unstakeRequestsManager.claim(requestID, generalTest.requester);
        assertEq(unstakeRequestsManager.balance(), 0);
    }
}

contract UnstakeRequestsWithdrawAllocatedETHSurplusTest is UnstakeRequestsManagerTest {
    function testWithdrawAllocatedETHSurplusNone() public {
        vm.prank(address(staking));
        unstakeRequestsManager.withdrawAllocatedETHSurplus();
        assertEq(unstakeRequestsManager.allocatedETHForClaims(), 0);
    }

    function testWithdrawAllocatedETHSurplusWithDeposit() public {
        createRequest(generalTest);

        uint256 allocatedETHSurplus = 1 ether;
        uint256 allocatedETHDeficit = unstakeRequestsManager.allocatedETHDeficit();
        vm.deal(address(staking), allocatedETHSurplus + allocatedETHDeficit);

        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: allocatedETHSurplus + allocatedETHDeficit}();

        uint256 prevBalance = address(unstakeRequestsManager).balance;
        vm.prank(address(staking));
        unstakeRequestsManager.withdrawAllocatedETHSurplus();

        assertEq(unstakeRequestsManager.allocatedETHForClaims(), allocatedETHDeficit);
        assertEq(address(unstakeRequestsManager).balance, prevBalance - allocatedETHSurplus);
        assertEq(staking.valueReceivedRequestsManager(), allocatedETHSurplus);
    }
}

contract UnstakeRequestsCreateTest is UnstakeRequestsManagerTest {
    struct TestCase {
        address requester;
        uint128 mETHLocked;
        uint128 ethRequested;
    }

    function _testCreate(TestCase memory tt) internal {
        uint256 nextId = unstakeRequestsManager.nextRequestId();
        uint256 prevLatestCumulativeETHRequested = unstakeRequestsManager.latestCumulativeETHRequested();

        vm.expectEmit(address(unstakeRequestsManager));
        emit UnstakeRequestCreated({
            id: nextId,
            requester: tt.requester,
            mETHLocked: tt.mETHLocked,
            ethRequested: tt.ethRequested,
            cumulativeETHRequested: uint256(prevLatestCumulativeETHRequested) + uint256(tt.ethRequested),
            blockNumber: block.number
        });

        vm.prank(address(staking));
        uint256 requestID = unstakeRequestsManager.create({
            requester: tt.requester,
            mETHLocked: tt.mETHLocked,
            ethRequested: tt.ethRequested
        });
        assertEq(requestID, nextId);
        assertEq(
            unstakeRequestsManager.latestCumulativeETHRequested(),
            uint256(prevLatestCumulativeETHRequested) + uint256(tt.ethRequested)
        );
        assertEq(unstakeRequestsManager.nextRequestId(), nextId + 1);
    }

    function testSuccess() public {
        TestCase memory tt = TestCase({requester: makeAddr("requester"), mETHLocked: 1 ether, ethRequested: 1 ether});
        uint128 prevLatestCumulativeETHRequested = 1 ether;
        tUnstakeRequests.setLatestCumulativeETHRequested(prevLatestCumulativeETHRequested);
        _testCreate(tt);
    }

    function testSuccessRepeated() public {
        // Test that the first request was made.
        _testCreate(TestCase({requester: makeAddr("requester1"), mETHLocked: 1 ether, ethRequested: 1 ether}));

        // Test that a second request was made.
        _testCreate(TestCase({requester: makeAddr("requester2"), mETHLocked: 2 ether, ethRequested: 2 ether}));
    }

    function testSuccessFuzzed(TestCase memory tt, uint128 prevLatestCumulativeETHRequested) public {
        vm.assume(uint256(prevLatestCumulativeETHRequested) + uint256(tt.ethRequested) <= type(uint128).max);
        tUnstakeRequests.setLatestCumulativeETHRequested(prevLatestCumulativeETHRequested);
        _testCreate(tt);
    }
}

contract UnstakeRequestsRequestInfoTest is UnstakeRequestsManagerTest {
    function testRequestInfo() public {
        uint256 requestID = createRequest();

        (bool isFinalized, uint256 claimableAmount) = unstakeRequestsManager.requestInfo(requestID);

        assertFalse(isFinalized);
        assertEq(claimableAmount, 0);
    }

    function testRequestInfoIsPartiallyFilled() public {
        uint256 requestID = createRequest();
        UnstakeRequest memory request = unstakeRequestsManager.requestByID(requestID);

        uint256 missingEth = 0.01 ether;
        uint256 expectedClaimableAmount = request.ethRequested - missingEth;
        vm.deal(address(staking), expectedClaimableAmount);
        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: expectedClaimableAmount}();

        (bool isFinalized, uint256 claimableAmount) = unstakeRequestsManager.requestInfo(requestID);

        assertFalse(isFinalized);
        assertEq(claimableAmount, expectedClaimableAmount);
    }

    function testRequestInfoIsClaimable() public {
        uint256 requestID = createRequest();
        UnstakeRequest memory request = unstakeRequestsManager.requestByID(requestID);

        OracleRecord memory record;
        record.updateEndBlock = uint64(request.blockNumber) + uint64(unstakeRequestsManager.numberOfBlocksToFinalize());
        oracle.pushRecord(record);

        vm.deal(address(staking), request.ethRequested);
        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: request.ethRequested}();

        (bool isFinalized, uint256 claimableAmount) = unstakeRequestsManager.requestInfo(requestID);

        assertTrue(isFinalized);
        assertEq(claimableAmount, request.ethRequested);
    }

    function testRequestInfoIsClaimableWhenOverallocated() public {
        uint256 requestID = createRequest();
        UnstakeRequest memory request = unstakeRequestsManager.requestByID(requestID);

        OracleRecord memory record;
        record.updateEndBlock = uint64(request.blockNumber) + uint64(unstakeRequestsManager.numberOfBlocksToFinalize());
        oracle.pushRecord(record);

        uint256 doubledRequested = request.ethRequested * 2;
        vm.deal(address(staking), doubledRequested);
        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: doubledRequested}();

        (bool isFinalized, uint256 claimableAmount) = unstakeRequestsManager.requestInfo(requestID);

        assertTrue(isFinalized);
        assertEq(claimableAmount, request.ethRequested);
    }
}

contract UnstakeRequestsClaimTest is UnstakeRequestsManagerTest {
    function _testClaim(uint256 requestID, address requester) internal {
        UnstakeRequest memory request = unstakeRequestsManager.requestByID(requestID);
        uint256 prevRequesterBalance = requester.balance;
        uint256 prevMntTotalSupply = mETH.totalSupply();
        uint256 prevMETHBalance = mETH.balanceOf(address(unstakeRequestsManager));
        uint256 prevTotalClaimed = unstakeRequestsManager.totalClaimed();

        vm.expectEmit(address(unstakeRequestsManager));
        emit UnstakeRequestClaimed(
            request.id,
            request.requester,
            request.mETHLocked,
            request.ethRequested,
            request.cumulativeETHRequested,
            request.blockNumber
        );
        vm.prank(address(staking));
        unstakeRequestsManager.claim(requestID, requester);

        UnstakeRequest memory emptiedRequest = unstakeRequestsManager.requestByID(requestID);
        assertEq(emptiedRequest, emptyRequest);
        assertEq(unstakeRequestsManager.totalClaimed(), prevTotalClaimed + request.ethRequested);
        assertEq(requester.balance, prevRequesterBalance + request.ethRequested);
        assertEq(mETH.totalSupply(), prevMntTotalSupply - request.mETHLocked);
        assertEq(mETH.balanceOf(address(unstakeRequestsManager)), prevMETHBalance - request.mETHLocked);
    }

    function testSuccess() public {
        uint256 requestID = createRequest();
        UnstakeRequest memory request = unstakeRequestsManager.requestByID(requestID);
        OracleRecord memory record;
        record.updateEndBlock = uint64(block.number + unstakeRequestsManager.numberOfBlocksToFinalize());
        oracle.pushRecord(record);

        vm.deal(address(staking), request.ethRequested);
        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: request.ethRequested}();
        _mintMETH(address(unstakeRequestsManager), request.mETHLocked);

        _testClaim(requestID, request.requester);
    }

    function reentrantTest(uint256 requestID, uint256 wantTotalClaimed, uint256 wantMETHTotalSupply) public {
        UnstakeRequest memory emptiedRequest = unstakeRequestsManager.requestByID(requestID);
        assertEq(emptiedRequest, emptyRequest);
        assertEq(unstakeRequestsManager.totalClaimed(), wantTotalClaimed);
        assertEq(mETH.totalSupply(), wantMETHTotalSupply);
    }

    function testSuccessReentrant() public {
        ReentrancyForwarder forwarder = new ReentrancyForwarder();

        SampleRequest memory request =
            SampleRequest({requester: address(forwarder), mETHLocked: 0.1 ether, ethRequested: 0.1 ether});
        uint256 requestID = createRequest(request);

        OracleRecord memory record;
        record.updateEndBlock = uint64(block.number + unstakeRequestsManager.numberOfBlocksToFinalize());
        oracle.pushRecord(record);

        vm.deal(address(staking), request.ethRequested);
        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: request.ethRequested}();
        _mintMETH(address(unstakeRequestsManager), request.mETHLocked);

        forwarder.setTarget(address(this));
        forwarder.setCallData(abi.encodeCall(this.reentrantTest, (requestID, 0.1 ether, 0 ether)));

        _testClaim(requestID, request.requester);
    }

    function testNotRequester() public {
        uint256 requestID = createRequest();

        vm.expectRevert(UnstakeRequestsManager.NotRequester.selector);
        vm.prank(address(staking));
        unstakeRequestsManager.claim(requestID, vandal);
    }

    function testCannotClaimFirstRequestAgain() public {
        // Create a valid request and claim it.
        uint256 requestID = createRequest();
        UnstakeRequest memory request = unstakeRequestsManager.requestByID(requestID);
        OracleRecord memory record;
        record.updateEndBlock = uint64(block.number + unstakeRequestsManager.numberOfBlocksToFinalize());
        oracle.pushRecord(record);

        vm.deal(address(staking), request.ethRequested);
        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: request.ethRequested}();
        _mintMETH(address(unstakeRequestsManager), request.mETHLocked);

        vm.prank(address(staking));
        unstakeRequestsManager.claim(requestID, request.requester);

        // Try to claim the same request again.
        vm.expectRevert(UnstakeRequestsManager.AlreadyClaimed.selector);
        vm.prank(address(staking));
        unstakeRequestsManager.claim(0, address(0));
    }

    function testAllocatedButNotFinalized() public {
        uint256 requestID = createRequest();
        UnstakeRequest memory request = unstakeRequestsManager.requestByID(requestID);

        vm.deal(address(staking), request.ethRequested);
        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: request.ethRequested}();
        _mintMETH(address(unstakeRequestsManager), request.mETHLocked);

        vm.expectRevert(abi.encodeWithSelector(UnstakeRequestsManager.NotFinalized.selector));
        vm.prank(address(staking));
        unstakeRequestsManager.claim(requestID, request.requester);
    }

    function testFinalizedButNotEnoughFunds() public {
        uint256 requestID = createRequest();
        UnstakeRequest memory request = unstakeRequestsManager.requestByID(requestID);

        OracleRecord memory record;
        record.updateEndBlock = uint64(block.number + unstakeRequestsManager.numberOfBlocksToFinalize());
        oracle.pushRecord(record);

        vm.deal(address(staking), request.ethRequested);
        vm.prank(address(staking));
        // 1 less wei allocated than requested.
        unstakeRequestsManager.allocateETH{value: request.ethRequested - 1}();
        _mintMETH(address(unstakeRequestsManager), request.mETHLocked);

        vm.expectRevert(
            abi.encodeWithSelector(
                UnstakeRequestsManager.NotEnoughFunds.selector, request.ethRequested, request.ethRequested - 1
            )
        );
        vm.prank(address(staking));
        unstakeRequestsManager.claim(requestID, request.requester);
    }

    function testFlowWithAllocation() public {
        SampleRequest memory aTestCase =
            SampleRequest({requester: makeAddr("a"), mETHLocked: 0.1 ether, ethRequested: 2 ether});
        SampleRequest memory bTestCase =
            SampleRequest({requester: makeAddr("b"), mETHLocked: 0.1 ether, ethRequested: 1 ether});
        SampleRequest memory cTestCase =
            SampleRequest({requester: makeAddr("c"), mETHLocked: 0.1 ether, ethRequested: 3 ether});
        uint256 aRequestID = createRequest(aTestCase);
        uint256 bRequestID = createRequest(bTestCase);
        uint256 cRequestID = createRequest(cTestCase);

        vm.deal(address(staking), aTestCase.ethRequested + bTestCase.ethRequested + cTestCase.ethRequested);
        _mintMETH(address(unstakeRequestsManager), 0.1 ether * 3);

        uint256 allocatedETHDeficit = unstakeRequestsManager.allocatedETHDeficit();
        assertEq(allocatedETHDeficit, aTestCase.ethRequested + bTestCase.ethRequested + cTestCase.ethRequested);
        OracleRecord memory record;
        record.updateEndBlock = uint64(block.number + unstakeRequestsManager.numberOfBlocksToFinalize() + 1);
        oracle.pushRecord(record);

        // Allocate enough for a and b to claim
        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: aTestCase.ethRequested + bTestCase.ethRequested}();

        // Only C's amount should be missing.
        allocatedETHDeficit = unstakeRequestsManager.allocatedETHDeficit();
        assertEq(allocatedETHDeficit, cTestCase.ethRequested);

        // C tries to claim but fails.
        vm.expectRevert(
            abi.encodeWithSelector(
                UnstakeRequestsManager.NotEnoughFunds.selector,
                aTestCase.ethRequested + bTestCase.ethRequested + cTestCase.ethRequested,
                aTestCase.ethRequested + bTestCase.ethRequested
            )
        );
        vm.prank(address(staking));
        unstakeRequestsManager.claim(cRequestID, cTestCase.requester);

        // A can claim
        _testClaim(aRequestID, aTestCase.requester);

        // A tries to claim again
        vm.expectRevert(abi.encodeWithSelector(UnstakeRequestsManager.AlreadyClaimed.selector));
        vm.prank(address(staking));
        unstakeRequestsManager.claim(aRequestID, aTestCase.requester);

        // Allocate the rest.
        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: allocatedETHDeficit}();
        uint256 newAllocatedETHDeficit = unstakeRequestsManager.allocatedETHDeficit();
        assertEq(newAllocatedETHDeficit, 0);

        // B and C can claim.
        _testClaim(bRequestID, bTestCase.requester);
        _testClaim(cRequestID, cTestCase.requester);
    }
}

contract UnstakeRequestsEmergencyCancelUnfinalizedTest is UnstakeRequestsManagerTest {
    function testCancelRequestsWithNoRequests(uint256 fuzzCancelBound) public {
        vm.prank(requestCanceller);
        bool hasMore = unstakeRequestsManager.cancelUnfinalizedRequests(fuzzCancelBound);
        assertFalse(hasMore);
    }

    function testCancelRequestsWithLowerBound() public {
        uint256 totalMETHLocked = 0;

        UnstakeRequest[] memory unstakeRequestsToCancel = new UnstakeRequest[](
            5
        );
        for (uint256 i = 0; i < 5; i++) {
            uint256 id = createRequest(generalTest);
            UnstakeRequest memory request = unstakeRequestsManager.requestByID(id);
            unstakeRequestsToCancel[i] = request;
            totalMETHLocked += request.mETHLocked;
        }
        _mintMETH(address(unstakeRequestsManager), totalMETHLocked);

        // Should only cancel the four events up to the last two.
        for (uint256 i = unstakeRequestsToCancel.length - 1; i >= 2; --i) {
            vm.expectEmit(address(unstakeRequestsManager));
            emit UnstakeRequestCancelled(
                unstakeRequestsToCancel[i].id,
                unstakeRequestsToCancel[i].requester,
                unstakeRequestsToCancel[i].mETHLocked,
                unstakeRequestsToCancel[i].ethRequested,
                unstakeRequestsToCancel[i].cumulativeETHRequested,
                unstakeRequestsToCancel[i].blockNumber
            );
        }

        vm.prank(requestCanceller);
        bool hasMore = unstakeRequestsManager.cancelUnfinalizedRequests(3);
        assertTrue(hasMore);
        assertEq(unstakeRequestsManager.nextRequestId(), 2);

        // Cancelling the remaining two with an exceeding number of iterations.
        for (uint256 j = unstakeRequestsManager.nextRequestId(); j > 0; --j) {
            uint256 i = j - 1;
            vm.expectEmit(address(unstakeRequestsManager));
            emit UnstakeRequestCancelled(
                unstakeRequestsToCancel[i].id,
                unstakeRequestsToCancel[i].requester,
                unstakeRequestsToCancel[i].mETHLocked,
                unstakeRequestsToCancel[i].ethRequested,
                unstakeRequestsToCancel[i].cumulativeETHRequested,
                unstakeRequestsToCancel[i].blockNumber
            );
        }

        vm.prank(requestCanceller);
        hasMore = unstakeRequestsManager.cancelUnfinalizedRequests(100);
        assertFalse(hasMore);
        assertEq(unstakeRequestsManager.nextRequestId(), 0);
    }

    function testCancelRequestsEmergency() public {
        uint256 totalMETHLocked = 0;
        uint256 startingBlockNumber = block.number;
        UnstakeRequest[] memory unstakeRequestsToCancel = new UnstakeRequest[](
            5
        );
        for (uint256 i = 0; i < 5; i++) {
            uint256 id = createRequest(generalTest);
            UnstakeRequest memory request = unstakeRequestsManager.requestByID(id);
            unstakeRequestsToCancel[i] = request;
            totalMETHLocked += request.mETHLocked;

            vm.roll(block.number + 1);
        }

        // Allocate enough for all requesters.
        uint256 allocatedETHDeficit = unstakeRequestsManager.allocatedETHDeficit();
        vm.deal(address(staking), allocatedETHDeficit);
        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: allocatedETHDeficit}();

        // Only allow the first user to claim.
        OracleRecord memory record;
        record.updateEndBlock = uint64(startingBlockNumber + unstakeRequestsManager.numberOfBlocksToFinalize());
        oracle.pushRecord(record);

        _mintMETH(address(unstakeRequestsManager), totalMETHLocked);

        // Should only cancel the four events to the last one
        for (uint256 i = unstakeRequestsToCancel.length - 1; i >= 1; --i) {
            vm.expectEmit(address(unstakeRequestsManager));
            emit UnstakeRequestCancelled(
                unstakeRequestsToCancel[i].id,
                unstakeRequestsToCancel[i].requester,
                unstakeRequestsToCancel[i].mETHLocked,
                unstakeRequestsToCancel[i].ethRequested,
                unstakeRequestsToCancel[i].cumulativeETHRequested,
                unstakeRequestsToCancel[i].blockNumber
            );
        }

        // Cancel all unfinalized requests and check if calculations are correct.
        vm.prank(requestCanceller);
        bool hasMore = unstakeRequestsManager.cancelUnfinalizedRequests(5);
        assertFalse(hasMore);

        uint256 excessAllocatedETH = unstakeRequestsManager.allocatedETHSurplus();
        uint256 ethRequestedByFirstRequester = unstakeRequestsManager.requestByID(0).ethRequested;
        assertEq(allocatedETHDeficit - ethRequestedByFirstRequester, excessAllocatedETH);

        // Withdraw and check if it only receives surplus amount.
        uint256 prevBalance = address(unstakeRequestsManager).balance;
        vm.prank(address(staking));
        unstakeRequestsManager.withdrawAllocatedETHSurplus();
        assertEq(excessAllocatedETH, prevBalance - address(unstakeRequestsManager).balance);

        // Sanity check that after emergency we can add requests, finalize them, and they
        // won't be cancelled.
        for (uint256 i = 0; i < 5; i++) {
            createRequest(generalTest);
        }
        record.updateEndBlock = uint64(block.number + unstakeRequestsManager.numberOfBlocksToFinalize() + 1);
        oracle.pushRecord(record);

        // Check there were no emitted events.
        vm.prank(requestCanceller);
        hasMore = unstakeRequestsManager.cancelUnfinalizedRequests(5);
        assertFalse(hasMore);
    }

    function testCancelRequestsWithClaimed() public {
        uint256 totalMETHLocked = 0;
        uint256 startingBlockNumber = block.number;
        UnstakeRequest[] memory unstakeRequestsToCancel = new UnstakeRequest[](
            5
        );
        for (uint256 i = 0; i < 5; i++) {
            uint256 id = createRequest(generalTest);
            UnstakeRequest memory request = unstakeRequestsManager.requestByID(id);
            unstakeRequestsToCancel[i] = request;
            totalMETHLocked += request.mETHLocked;

            vm.roll(block.number + 1);
        }

        // Allocate enough for all requesters.
        uint256 allocatedETHDeficit = unstakeRequestsManager.allocatedETHDeficit();
        vm.deal(address(staking), allocatedETHDeficit);
        vm.prank(address(staking));
        unstakeRequestsManager.allocateETH{value: allocatedETHDeficit}();
        _mintMETH(address(unstakeRequestsManager), totalMETHLocked);

        // Only allow the first user to claim.
        OracleRecord memory record;
        record.updateEndBlock = uint64(startingBlockNumber + unstakeRequestsManager.numberOfBlocksToFinalize());
        oracle.pushRecord(record);

        vm.prank(address(staking));
        unstakeRequestsManager.claim(0, requester);

        // Should only cancel the four events to the last one
        for (uint256 i = unstakeRequestsToCancel.length - 1; i >= 1; --i) {
            vm.expectEmit(address(unstakeRequestsManager));
            emit UnstakeRequestCancelled(
                unstakeRequestsToCancel[i].id,
                unstakeRequestsToCancel[i].requester,
                unstakeRequestsToCancel[i].mETHLocked,
                unstakeRequestsToCancel[i].ethRequested,
                unstakeRequestsToCancel[i].cumulativeETHRequested,
                unstakeRequestsToCancel[i].blockNumber
            );
        }

        // Cancel all unfinalized requests and check if calculations are correct.
        vm.prank(requestCanceller);
        bool hasMore = unstakeRequestsManager.cancelUnfinalizedRequests(5);
        assertFalse(hasMore);

        assertEq(unstakeRequestsManager.latestCumulativeETHRequested(), 1 * generalTest.ethRequested);
    }
}
