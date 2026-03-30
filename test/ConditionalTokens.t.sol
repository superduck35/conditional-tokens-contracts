pragma solidity ^0.5.1;

import { ConditionalTokens } from "../contracts/ConditionalTokens.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { ERC20Mintable } from "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";
import { ERC1155TokenReceiver } from "../contracts/ERC1155/ERC1155TokenReceiver.sol";

/// @dev Actor contract that can call ConditionalTokens on behalf of a test address.
///      Needed because Solidity 0.5 has no vm.prank().
contract Actor is ERC1155TokenReceiver {
    ConditionalTokens public ct;

    constructor(ConditionalTokens _ct) public {
        ct = _ct;
    }

    function prepareCondition(address oracle, bytes32 questionId, uint outcomeSlotCount) external {
        ct.prepareCondition(oracle, questionId, outcomeSlotCount);
    }

    function reportPayouts(bytes32 questionId, uint[] calldata payouts) external {
        ct.reportPayouts(questionId, payouts);
    }

    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata partition,
        uint amount
    ) external {
        ct.splitPosition(collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata partition,
        uint amount
    ) external {
        ct.mergePositions(collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    function redeemPositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint[] calldata indexSets
    ) external {
        ct.redeemPositions(collateralToken, parentCollectionId, conditionId, indexSets);
    }

    function approveToken(ERC20Mintable token, address spender, uint amount) external {
        token.approve(spender, amount);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external {
        ct.safeTransferFrom(from, to, id, value, data);
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}

contract ConditionalTokensTest is ERC1155TokenReceiver {
    ConditionalTokens ct;
    ERC20Mintable token;
    Actor trader;
    Actor oracle;
    Actor notOracle;
    Actor counterparty;

    bytes32 constant NULL_BYTES32 = bytes32(0);

    function onERC1155Received(
        address, address, uint256, uint256, bytes calldata
    ) external returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, address, uint256[] calldata, uint256[] calldata, bytes calldata
    ) external returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function setUp() public {
        ct = new ConditionalTokens();
        token = new ERC20Mintable();
        trader = new Actor(ct);
        oracle = new Actor(ct);
        notOracle = new Actor(ct);
        counterparty = new Actor(ct);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _expectRevert(bytes memory callData) internal {
        (bool success, ) = address(ct).call(callData);
        require(!success, "expected revert but call succeeded");
    }

    function _expectRevertOn(address target, bytes memory callData) internal {
        (bool success, ) = target.call(callData);
        require(!success, "expected revert but call succeeded");
    }

    // =========================================================================
    // prepareCondition tests
    // =========================================================================

    function testRevertPrepareConditionZeroOutcomes() public {
        bytes32 questionId = bytes32(uint256(0xdead));
        _expectRevert(
            abi.encodeWithSelector(ct.prepareCondition.selector, address(oracle), questionId, uint(0))
        );
    }

    function testRevertPrepareConditionOneOutcome() public {
        bytes32 questionId = bytes32(uint256(0xbeef));
        _expectRevert(
            abi.encodeWithSelector(ct.prepareCondition.selector, address(oracle), questionId, uint(1))
        );
    }

    function testPrepareConditionValid() public {
        bytes32 questionId = bytes32(uint256(0xc0ffee));
        uint outcomeSlotCount = 256;

        ct.prepareCondition(address(oracle), questionId, outcomeSlotCount);

        bytes32 conditionId = ct.getConditionId(address(oracle), questionId, outcomeSlotCount);
        require(ct.getOutcomeSlotCount(conditionId) == outcomeSlotCount, "outcome slot count mismatch");
        require(ct.payoutDenominator(conditionId) == 0, "payout denominator should be 0");
    }

    function testRevertPrepareConditionDuplicate() public {
        bytes32 questionId = bytes32(uint256(0xc0ffee));
        uint outcomeSlotCount = 256;

        ct.prepareCondition(address(oracle), questionId, outcomeSlotCount);

        _expectRevert(
            abi.encodeWithSelector(ct.prepareCondition.selector, address(oracle), questionId, outcomeSlotCount)
        );
    }

    // =========================================================================
    // Splitting and merging - EOA trader with ERC-20 collateral
    // =========================================================================

    function _setupSplitMerge() internal returns (bytes32 questionId, bytes32 conditionId) {
        questionId = bytes32(uint256(0x1234));
        uint outcomeSlotCount = 2;
        conditionId = ct.getConditionId(address(oracle), questionId, outcomeSlotCount);

        // Mint tokens to trader and approve CT contract
        uint collateralAmount = 1e19;
        token.mint(address(trader), collateralAmount);
        trader.approveToken(token, address(ct), collateralAmount);

        // Prepare the condition (called from oracle)
        oracle.prepareCondition(address(oracle), questionId, outcomeSlotCount);
    }

    function testRevertSplitUnpreparedCondition() public {
        bytes32 questionId = bytes32(uint256(0x9999));
        bytes32 conditionId = ct.getConditionId(address(oracle), questionId, 2);
        uint collateralAmount = 1e19;
        token.mint(address(trader), collateralAmount);
        trader.approveToken(token, address(ct), collateralAmount);

        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        _expectRevertOn(
            address(trader),
            abi.encodeWithSelector(trader.splitPosition.selector, address(token), NULL_BYTES32, conditionId, partition, uint(4e18))
        );
    }

    function testRevertSplitNonDisjointPartition() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint[] memory partition = new uint[](2);
        partition[0] = 0x03; // 0b11
        partition[1] = 0x02; // 0b10 — overlaps

        _expectRevertOn(
            address(trader),
            abi.encodeWithSelector(trader.splitPosition.selector, address(token), NULL_BYTES32, conditionId, partition, uint(4e18))
        );
    }

    function testRevertSplitExceedingOutcomeSlots() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint[] memory partition = new uint[](3);
        partition[0] = 0x01;
        partition[1] = 0x02;
        partition[2] = 0x04; // 3 slots but condition has 2

        _expectRevertOn(
            address(trader),
            abi.encodeWithSelector(trader.splitPosition.selector, address(token), NULL_BYTES32, conditionId, partition, uint(4e18))
        );
    }

    function testRevertSplitSingletonPartition() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint[] memory partition = new uint[](1);
        partition[0] = 0x03; // 0b11 — full set but singleton array

        _expectRevertOn(
            address(trader),
            abi.encodeWithSelector(trader.splitPosition.selector, address(token), NULL_BYTES32, conditionId, partition, uint(4e18))
        );
    }

    function testRevertSplitIncompleteSingletonPartition() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint[] memory partition = new uint[](1);
        partition[0] = 0x01; // 0b01 — incomplete

        _expectRevertOn(
            address(trader),
            abi.encodeWithSelector(trader.splitPosition.selector, address(token), NULL_BYTES32, conditionId, partition, uint(4e18))
        );
    }

    function testValidSplit() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint splitAmount = 4e18;
        uint collateralTokenCount = 1e19;
        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);

        // Collateral transferred from trader
        require(token.balanceOf(address(trader)) == collateralTokenCount - splitAmount, "trader collateral balance wrong");
        require(token.balanceOf(address(ct)) == splitAmount, "CT collateral balance wrong");

        // Position tokens minted
        for (uint i = 0; i < partition.length; i++) {
            bytes32 collectionId = ct.getCollectionId(NULL_BYTES32, conditionId, partition[i]);
            uint positionId = ct.getPositionId(IERC20(address(token)), collectionId);
            require(ct.balanceOf(address(trader), positionId) == splitAmount, "position balance wrong after split");
        }
    }

    function testRevertMergeExceedingBalance() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint splitAmount = 4e18;
        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);

        _expectRevertOn(
            address(trader),
            abi.encodeWithSelector(
                trader.mergePositions.selector,
                address(token), NULL_BYTES32, conditionId, partition, splitAmount + 1
            )
        );
    }

    function testValidMerge() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint splitAmount = 4e18;
        uint mergeAmount = 3e18;
        uint collateralTokenCount = 1e19;
        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);
        trader.mergePositions(IERC20(address(token)), NULL_BYTES32, conditionId, partition, mergeAmount);

        // Collateral returned to trader
        require(
            token.balanceOf(address(trader)) == collateralTokenCount - splitAmount + mergeAmount,
            "trader collateral wrong after merge"
        );
        require(
            token.balanceOf(address(ct)) == splitAmount - mergeAmount,
            "CT collateral wrong after merge"
        );

        // Position tokens burned
        for (uint i = 0; i < partition.length; i++) {
            bytes32 collectionId = ct.getCollectionId(NULL_BYTES32, conditionId, partition[i]);
            uint positionId = ct.getPositionId(IERC20(address(token)), collectionId);
            require(
                ct.balanceOf(address(trader), positionId) == splitAmount - mergeAmount,
                "position balance wrong after merge"
            );
        }
    }

    // =========================================================================
    // Transfer tests
    // =========================================================================

    function testRevertTransferExceedingBalance() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint splitAmount = 4e18;
        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);

        bytes32 collectionId = ct.getCollectionId(NULL_BYTES32, conditionId, partition[0]);
        uint positionId = ct.getPositionId(IERC20(address(token)), collectionId);

        _expectRevertOn(
            address(trader),
            abi.encodeWithSelector(
                trader.safeTransferFrom.selector,
                address(trader), address(counterparty), positionId, splitAmount + 1, ""
            )
        );
    }

    // =========================================================================
    // Report payout tests
    // =========================================================================

    function testRevertReportByWrongOracle() public {
        (bytes32 questionId,) = _setupSplitMerge();

        uint[] memory payouts = new uint[](2);
        payouts[0] = 3;
        payouts[1] = 7;

        _expectRevertOn(
            address(notOracle),
            abi.encodeWithSelector(notOracle.reportPayouts.selector, questionId, payouts)
        );
    }

    function testRevertReportWrongQuestionId() public {
        _setupSplitMerge();

        bytes32 wrongQuestionId = bytes32(uint256(0xbadbadbad));
        uint[] memory payouts = new uint[](2);
        payouts[0] = 3;
        payouts[1] = 7;

        _expectRevertOn(
            address(oracle),
            abi.encodeWithSelector(oracle.reportPayouts.selector, wrongQuestionId, payouts)
        );
    }

    function testRevertReportNoSlots() public {
        (bytes32 questionId,) = _setupSplitMerge();

        uint[] memory payouts = new uint[](0);
        _expectRevertOn(
            address(oracle),
            abi.encodeWithSelector(oracle.reportPayouts.selector, questionId, payouts)
        );
    }

    function testRevertReportWrongSlotCount() public {
        (bytes32 questionId,) = _setupSplitMerge();

        uint[] memory payouts = new uint[](3);
        payouts[0] = 2;
        payouts[1] = 3;
        payouts[2] = 5;

        _expectRevertOn(
            address(oracle),
            abi.encodeWithSelector(oracle.reportPayouts.selector, questionId, payouts)
        );
    }

    function testRevertReportAllZeroPayouts() public {
        (bytes32 questionId,) = _setupSplitMerge();

        uint[] memory payouts = new uint[](2);
        payouts[0] = 0;
        payouts[1] = 0;

        _expectRevertOn(
            address(oracle),
            abi.encodeWithSelector(oracle.reportPayouts.selector, questionId, payouts)
        );
    }

    function testValidReport() public {
        (bytes32 questionId, bytes32 conditionId) = _setupSplitMerge();

        uint[] memory payouts = new uint[](2);
        payouts[0] = 3;
        payouts[1] = 7;

        oracle.reportPayouts(questionId, payouts);

        // Verify payout numerators
        require(ct.payoutNumerators(conditionId, 0) == 3, "numerator 0 wrong");
        require(ct.payoutNumerators(conditionId, 1) == 7, "numerator 1 wrong");
        require(ct.payoutDenominator(conditionId) == 10, "denominator wrong");
    }

    function testRevertDuplicateReport() public {
        (bytes32 questionId,) = _setupSplitMerge();

        uint[] memory payouts = new uint[](2);
        payouts[0] = 3;
        payouts[1] = 7;

        oracle.reportPayouts(questionId, payouts);

        _expectRevertOn(
            address(oracle),
            abi.encodeWithSelector(oracle.reportPayouts.selector, questionId, payouts)
        );
    }

    // =========================================================================
    // Full flow: split, transfer, report, redeem
    // =========================================================================

    function testFullFlowSplitTransferReportRedeem() public {
        (bytes32 questionId, bytes32 conditionId) = _setupSplitMerge();

        uint splitAmount = 4e18;
        uint transferAmount = 1e18;
        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        // Split
        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);

        // Transfer position[0] partially to counterparty
        bytes32 collectionId0 = ct.getCollectionId(NULL_BYTES32, conditionId, partition[0]);
        uint positionId0 = ct.getPositionId(IERC20(address(token)), collectionId0);
        trader.safeTransferFrom(address(trader), address(counterparty), positionId0, transferAmount, "");

        // Report
        uint[] memory payoutNumerators = new uint[](2);
        payoutNumerators[0] = 3;
        payoutNumerators[1] = 7;
        oracle.reportPayouts(questionId, payoutNumerators);

        // Merge should fail (trader transferred some of partition[0])
        _expectRevertOn(
            address(trader),
            abi.encodeWithSelector(
                trader.mergePositions.selector,
                address(token), NULL_BYTES32, conditionId, partition, splitAmount
            )
        );

        // Redeem
        uint traderBalBefore = token.balanceOf(address(trader));
        trader.redeemPositions(IERC20(address(token)), NULL_BYTES32, conditionId, partition);

        // Verify positions zeroed out for trader
        for (uint i = 0; i < partition.length; i++) {
            bytes32 colId = ct.getCollectionId(NULL_BYTES32, conditionId, partition[i]);
            uint posId = ct.getPositionId(IERC20(address(token)), colId);
            require(ct.balanceOf(address(trader), posId) == 0, "trader position should be zero after redeem");
        }

        // Counterparty position unaffected
        require(
            ct.balanceOf(address(counterparty), positionId0) == transferAmount,
            "counterparty position should be unchanged"
        );

        // Calculate expected payout:
        // position[0]: (splitAmount - transferAmount) * 3/10
        // position[1]: splitAmount * 7/10
        uint payoutDenominator = 10;
        uint expectedPayout =
            ((splitAmount - transferAmount) * payoutNumerators[0] / payoutDenominator) +
            (splitAmount * payoutNumerators[1] / payoutDenominator);

        uint traderBalAfter = token.balanceOf(address(trader));
        require(
            traderBalAfter - traderBalBefore == expectedPayout,
            "trader payout wrong"
        );
    }

    // =========================================================================
    // Deep position tests - multi-condition
    // =========================================================================

    // Store deep test state to avoid stack-too-deep
    bytes32[3] internal _questionIds;
    bytes32[3] internal _conditionIds;

    function _setupDeepConditions() internal {
        uint outcomeSlotCount = 4;
        for (uint i = 0; i < 3; i++) {
            _questionIds[i] = bytes32(uint256(0xaa00 + i));
            _conditionIds[i] = ct.getConditionId(address(oracle), _questionIds[i], outcomeSlotCount);
            oracle.prepareCondition(address(oracle), _questionIds[i], outcomeSlotCount);
        }
    }

    function testDeepPositionSplitAndVerify() public {
        _setupDeepConditions();

        uint collateralTokenCount = 1e19;
        token.mint(address(trader), collateralTokenCount);
        trader.approveToken(token, address(ct), collateralTokenCount);

        // Split on condition[0]: partition [0b0111, 0b1000]
        uint[] memory partition1 = new uint[](2);
        partition1[0] = 0x07;
        partition1[1] = 0x08;
        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, _conditionIds[0], partition1, collateralTokenCount);

        // Transfer partition1[1] to counterparty
        {
            bytes32 collId1 = ct.getCollectionId(NULL_BYTES32, _conditionIds[0], partition1[1]);
            uint posId1 = ct.getPositionId(IERC20(address(token)), collId1);
            trader.safeTransferFrom(address(trader), address(counterparty), posId1, collateralTokenCount, "");
        }

        // Deep split on condition[1] under parent from condition[0]
        bytes32 parentCollectionId = ct.getCollectionId(NULL_BYTES32, _conditionIds[0], partition1[0]);
        uint deepSplitAmount = 4e18;

        uint[] memory partition2 = new uint[](3);
        partition2[0] = 0x01;
        partition2[1] = 0x02;
        partition2[2] = 0x0C;

        trader.splitPosition(IERC20(address(token)), parentCollectionId, _conditionIds[1], partition2, deepSplitAmount);

        // Verify parent position burn
        {
            uint parentPosId = ct.getPositionId(IERC20(address(token)), parentCollectionId);
            require(
                ct.balanceOf(address(trader), parentPosId) == collateralTokenCount - deepSplitAmount,
                "parent position not burned correctly"
            );
        }

        // Verify child position mint
        for (uint i = 0; i < partition2.length; i++) {
            bytes32 childCollId = ct.getCollectionId(parentCollectionId, _conditionIds[1], partition2[i]);
            uint childPosId = ct.getPositionId(IERC20(address(token)), childCollId);
            require(
                ct.balanceOf(address(trader), childPosId) == deepSplitAmount,
                "child position not minted correctly"
            );
        }
    }

    function testDeepPositionReportAndRedeem() public {
        _setupDeepConditions();

        uint amt = 1e19;
        token.mint(address(trader), amt);
        trader.approveToken(token, address(ct), amt);

        uint[] memory partition1 = new uint[](2);
        partition1[0] = 0x07;
        partition1[1] = 0x08;
        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, _conditionIds[0], partition1, amt);

        // Transfer partition1[1] away
        {
            bytes32 collId1 = ct.getCollectionId(NULL_BYTES32, _conditionIds[0], partition1[1]);
            uint posId1 = ct.getPositionId(IERC20(address(token)), collId1);
            trader.safeTransferFrom(address(trader), address(counterparty), posId1, amt, "");
        }

        // Report on condition[0]
        uint[] memory finalReport = new uint[](4);
        finalReport[0] = 0;
        finalReport[1] = 33;
        finalReport[2] = 289;
        finalReport[3] = 678;
        oracle.reportPayouts(_questionIds[0], finalReport);

        // Verify report
        for (uint i = 0; i < finalReport.length; i++) {
            require(ct.payoutNumerators(_conditionIds[0], i) == finalReport[i], "payout numerator wrong");
        }

        // Cannot update report
        _expectRevertOn(
            address(oracle),
            abi.encodeWithSelector(oracle.reportPayouts.selector, _questionIds[0], finalReport)
        );

        // Redeem partition1[0]
        uint[] memory redeemSets = new uint[](1);
        redeemSets[0] = partition1[0];

        uint traderBalBefore = token.balanceOf(address(trader));
        trader.redeemPositions(IERC20(address(token)), NULL_BYTES32, _conditionIds[0], redeemSets);
        uint traderBalAfter = token.balanceOf(address(trader));

        // Expected payout: amt * (0 + 33 + 289) / (0 + 33 + 289 + 678)
        // = 1e19 * 322 / 1000 = 322e16
        uint expectedPayout = amt * 322 / 1000;
        require(traderBalAfter - traderBalBefore == expectedPayout, "deep position payout wrong");
    }

    // =========================================================================
    // Edge cases
    // =========================================================================

    function testRevertSplitWithInsufficientCollateral() public {
        bytes32 questionId = bytes32(uint256(0x5555));
        bytes32 conditionId = ct.getConditionId(address(oracle), questionId, 2);
        oracle.prepareCondition(address(oracle), questionId, 2);

        // Mint only 1 token but try to split 1e18
        token.mint(address(trader), 1);
        trader.approveToken(token, address(ct), 1e18);

        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        _expectRevertOn(
            address(trader),
            abi.encodeWithSelector(trader.splitPosition.selector, address(token), NULL_BYTES32, conditionId, partition, uint(1e18))
        );
    }

    function testRevertRedeemBeforeReport() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint splitAmount = 4e18;
        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);

        // Try to redeem before report
        _expectRevertOn(
            address(trader),
            abi.encodeWithSelector(
                trader.redeemPositions.selector,
                address(token), NULL_BYTES32, conditionId, partition
            )
        );
    }

    function testSplitMergeFullRoundTrip() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint splitAmount = 4e18;
        uint collateralTokenCount = 1e19;
        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        // Split and merge same amount — should return to original state
        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);
        trader.mergePositions(IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);

        require(token.balanceOf(address(trader)) == collateralTokenCount, "should be fully restored after split+merge");
        require(token.balanceOf(address(ct)) == 0, "CT should hold no collateral after full merge");

        for (uint i = 0; i < partition.length; i++) {
            bytes32 collectionId = ct.getCollectionId(NULL_BYTES32, conditionId, partition[i]);
            uint positionId = ct.getPositionId(IERC20(address(token)), collectionId);
            require(ct.balanceOf(address(trader), positionId) == 0, "position should be 0 after full merge");
        }
    }

    function testPrepareConditionTooManyOutcomes() public {
        bytes32 questionId = bytes32(uint256(0xfff));
        _expectRevert(
            abi.encodeWithSelector(ct.prepareCondition.selector, address(oracle), questionId, uint(257))
        );
    }

    function testPrepareConditionMaxOutcomes() public {
        bytes32 questionId = bytes32(uint256(0xeee));
        ct.prepareCondition(address(oracle), questionId, 256);
        bytes32 conditionId = ct.getConditionId(address(oracle), questionId, 256);
        require(ct.getOutcomeSlotCount(conditionId) == 256, "max outcome slot count wrong");
    }

    function testRedeemZeroBalance() public {
        (bytes32 questionId, bytes32 conditionId) = _setupSplitMerge();

        uint[] memory payouts = new uint[](2);
        payouts[0] = 1;
        payouts[1] = 1;
        oracle.reportPayouts(questionId, payouts);

        // Redeem without having any positions — should succeed with 0 payout
        uint[] memory indexSets = new uint[](1);
        indexSets[0] = 0x01;

        uint balBefore = token.balanceOf(address(trader));
        trader.redeemPositions(IERC20(address(token)), NULL_BYTES32, conditionId, indexSets);
        uint balAfter = token.balanceOf(address(trader));
        require(balAfter == balBefore, "balance should not change when redeeming zero");
    }
}
