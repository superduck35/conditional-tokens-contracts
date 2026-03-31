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
    address constant VM = address(uint160(uint256(keccak256("hevm cheat code"))));

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

    /// @dev Call vm.expectEmit(true, true, true, true, address)
    function _expectEmit() internal {
        (bool ok, ) = VM.call(
            abi.encodeWithSignature("expectEmit(bool,bool,bool,bool,address)", true, true, true, true, address(ct))
        );
        require(ok, "expectEmit failed");
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

    // =========================================================================
    // Event emission tests
    // =========================================================================

    function testEmitConditionPreparation() public {
        bytes32 questionId = bytes32(uint256(0xe0e0));
        uint outcomeSlotCount = 3;
        bytes32 conditionId = ct.getConditionId(address(oracle), questionId, outcomeSlotCount);

        _expectEmit();
        emit ConditionPreparation(conditionId, address(oracle), questionId, outcomeSlotCount);
        oracle.prepareCondition(address(oracle), questionId, outcomeSlotCount);
    }

    function testEmitPositionSplit() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint splitAmount = 4e18;
        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        _expectEmit();
        emit PositionSplit(address(trader), IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);
        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);
    }

    function testEmitPositionsMerge() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint splitAmount = 4e18;
        uint mergeAmount = 3e18;
        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);

        _expectEmit();
        emit PositionsMerge(address(trader), IERC20(address(token)), NULL_BYTES32, conditionId, partition, mergeAmount);
        trader.mergePositions(IERC20(address(token)), NULL_BYTES32, conditionId, partition, mergeAmount);
    }

    function testEmitConditionResolution() public {
        (bytes32 questionId, bytes32 conditionId) = _setupSplitMerge();

        uint[] memory payouts = new uint[](2);
        payouts[0] = 3;
        payouts[1] = 7;

        _expectEmit();
        emit ConditionResolution(conditionId, address(oracle), questionId, 2, payouts);
        oracle.reportPayouts(questionId, payouts);
    }

    function testEmitPayoutRedemption() public {
        (bytes32 questionId, bytes32 conditionId) = _setupSplitMerge();

        uint splitAmount = 4e18;
        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);

        uint[] memory payouts = new uint[](2);
        payouts[0] = 3;
        payouts[1] = 7;
        oracle.reportPayouts(questionId, payouts);

        // Expected payout: splitAmount * 3/10 + splitAmount * 7/10 = splitAmount
        uint expectedPayout = splitAmount;

        _expectEmit();
        emit PayoutRedemption(address(trader), IERC20(address(token)), NULL_BYTES32, conditionId, partition, expectedPayout);
        trader.redeemPositions(IERC20(address(token)), NULL_BYTES32, conditionId, partition);
    }

    // =========================================================================
    // Missing logic tests
    // =========================================================================

    function testRevertMergeAfterTransferReducesBalance() public {
        (,bytes32 conditionId) = _setupSplitMerge();

        uint splitAmount = 4e18;
        uint transferAmount = 1e18;
        uint[] memory partition = new uint[](2);
        partition[0] = 0x01;
        partition[1] = 0x02;

        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, conditionId, partition, splitAmount);

        // Transfer part of position[0] to counterparty
        bytes32 collectionId0 = ct.getCollectionId(NULL_BYTES32, conditionId, partition[0]);
        uint positionId0 = ct.getPositionId(IERC20(address(token)), collectionId0);
        trader.safeTransferFrom(address(trader), address(counterparty), positionId0, transferAmount, "");

        // Report
        uint[] memory payouts = new uint[](2);
        payouts[0] = 3;
        payouts[1] = 7;
        oracle.reportPayouts(bytes32(uint256(0x1234)), payouts);

        // Merge full splitAmount should fail — trader no longer has enough of partition[0]
        _expectRevertOn(
            address(trader),
            abi.encodeWithSelector(
                trader.mergePositions.selector,
                address(token), NULL_BYTES32, conditionId, partition, splitAmount
            )
        );
    }

    function testRevertDuplicateReportDifferentValues() public {
        (bytes32 questionId,) = _setupSplitMerge();

        uint[] memory payouts = new uint[](2);
        payouts[0] = 3;
        payouts[1] = 7;
        oracle.reportPayouts(questionId, payouts);

        // Try to update with different values
        uint[] memory badUpdate = new uint[](2);
        badUpdate[0] = 0;
        badUpdate[1] = 7;

        _expectRevertOn(
            address(oracle),
            abi.encodeWithSelector(oracle.reportPayouts.selector, questionId, badUpdate)
        );
    }

    function testCombinesCollectionIds() public {
        _setupDeepConditions();

        uint collateralTokenCount = 1e19;
        token.mint(address(trader), collateralTokenCount);
        trader.approveToken(token, address(ct), collateralTokenCount);

        // Split on condition[0]
        uint[] memory partition1 = new uint[](2);
        partition1[0] = 0x07; // 0b0111
        partition1[1] = 0x08; // 0b1000
        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, _conditionIds[0], partition1, collateralTokenCount);

        bytes32 parentCollectionId = ct.getCollectionId(NULL_BYTES32, _conditionIds[0], partition1[0]);

        // Verify getCollectionId with parent produces consistent, non-trivial results
        uint[] memory partition2 = new uint[](3);
        partition2[0] = 0x01;
        partition2[1] = 0x02;
        partition2[2] = 0x0C;

        for (uint i = 0; i < partition2.length; i++) {
            bytes32 childWithParent = ct.getCollectionId(parentCollectionId, _conditionIds[1], partition2[i]);
            bytes32 childWithoutParent = ct.getCollectionId(NULL_BYTES32, _conditionIds[1], partition2[i]);

            // Combined collection ID should differ from standalone
            require(childWithParent != childWithoutParent, "combined collection ID should differ from standalone");
            require(childWithParent != bytes32(0), "combined collection ID should not be zero");
        }
    }

    function testEmitPositionSplitDeep() public {
        _setupDeepConditions();

        uint collateralTokenCount = 1e19;
        token.mint(address(trader), collateralTokenCount);
        trader.approveToken(token, address(ct), collateralTokenCount);

        uint[] memory partition1 = new uint[](2);
        partition1[0] = 0x07;
        partition1[1] = 0x08;
        trader.splitPosition(IERC20(address(token)), NULL_BYTES32, _conditionIds[0], partition1, collateralTokenCount);

        bytes32 parentCollectionId = ct.getCollectionId(NULL_BYTES32, _conditionIds[0], partition1[0]);
        uint deepSplitAmount = 4e18;

        uint[] memory partition2 = new uint[](3);
        partition2[0] = 0x01;
        partition2[1] = 0x02;
        partition2[2] = 0x0C;

        _expectEmit();
        emit PositionSplit(address(trader), IERC20(address(token)), parentCollectionId, _conditionIds[1], partition2, deepSplitAmount);
        trader.splitPosition(IERC20(address(token)), parentCollectionId, _conditionIds[1], partition2, deepSplitAmount);
    }

    // =========================================================================
    // ID cross-validation tests
    // Reference values computed off-chain via utils/id-helpers.js
    // These verify the Solidity implementation matches the JS reference.
    // =========================================================================

    // Fixed oracle address for reference tests (not an Actor — just a raw address)
    address constant REF_ORACLE = address(0x1);
    address constant REF_TOKEN = address(0x99);

    function testConditionIdMatchesOffChainReference() public {
        // Vector 1: 256 outcomes
        bytes32 qid1 = bytes32(uint256(0x0100000000000000000000000000000000000000000000000000000000000000));
        // Reverse because Solidity bytes32 is big-endian
        qid1 = 0x0100000000000000000000000000000000000000000000000000000000000000;
        bytes32 expected1 = 0xacffa9a9ff3fa8e5e92ce5138e4a2ba22b98eee9d0dcd298d6f75a6bd5ec4404;
        require(ct.getConditionId(REF_ORACLE, qid1, 2) == expected1, "conditionId mismatch (2 outcomes)");

        // Vector 2: 256 outcomes
        bytes32 qid2 = 0x000000000000000000000000000000000000000000000000000000000000cafe;
        bytes32 expected2 = 0x20cc103253ccbcb4db08dbe88b5f68be8471d9663db82d56450521a9de762144;
        require(ct.getConditionId(REF_ORACLE, qid2, 256) == expected2, "conditionId mismatch (256 outcomes)");
    }

    function testCollectionIdMatchesOffChainReference() public {
        bytes32 conditionId = 0xacffa9a9ff3fa8e5e92ce5138e4a2ba22b98eee9d0dcd298d6f75a6bd5ec4404;

        bytes32 expected_01 = 0x6f2dd2e938aa3203c5862bd1af73958a34c15979bb13cda4a6d108c23c459444;
        bytes32 expected_02 = 0x6f031fa4e3efa0a26f95469ddc4985109837ef568b60f990a768c653c46d0636;

        require(ct.getCollectionId(NULL_BYTES32, conditionId, 1) == expected_01, "collectionId(1) mismatch");
        require(ct.getCollectionId(NULL_BYTES32, conditionId, 2) == expected_02, "collectionId(2) mismatch");
    }

    function testPositionIdMatchesOffChainReference() public {
        bytes32 collId_01 = 0x6f2dd2e938aa3203c5862bd1af73958a34c15979bb13cda4a6d108c23c459444;
        bytes32 collId_02 = 0x6f031fa4e3efa0a26f95469ddc4985109837ef568b60f990a768c653c46d0636;

        bytes32 expected_pos1 = 0xca96f0128ed7435e65cad8aed3a98cb19c13cdb7fb5c86cea9561588e9eb7501;
        bytes32 expected_pos2 = 0x90e174e5adb40b2db618d72107d5a3ff8d3159a1d345e0aa2cac1caa24f5c839;

        require(ct.getPositionId(IERC20(REF_TOKEN), collId_01) == uint256(expected_pos1), "positionId(1) mismatch");
        require(ct.getPositionId(IERC20(REF_TOKEN), collId_02) == uint256(expected_pos2), "positionId(2) mismatch");
    }

    function testCombinedCollectionIdMatchesOffChainReference() public {
        // Parent: conditionId3 with indexSet 7
        bytes32 conditionId3 = 0xcc4d53c710a5b110c6d3a439729bd6d6063c12328e412d58e1da3489ff3f5b3c;
        bytes32 parentCollId = 0x6e551715d0a681c1d8ee93161b44ebc8073f59f73cb2f08fb7316332c014352e;

        // Verify the parent collectionId itself
        require(ct.getCollectionId(NULL_BYTES32, conditionId3, 7) == parentCollId, "parent collectionId mismatch");

        // Child: conditionId4 with indexSet 1, combined with parent
        bytes32 conditionId4 = 0xe35d7e4183eea46617ab4a4586fb4cdeb86aa62bf0574f4733bba6503bed47a8;
        bytes32 expectedCombined = 0x6b3e0f684572bb8adcc379c630e5cb0ee9c308ead99cc8f003840192cec639a5;

        require(
            ct.getCollectionId(parentCollId, conditionId4, 1) == expectedCombined,
            "combined collectionId mismatch"
        );
    }

    // =========================================================================
    // Event declarations (for expectEmit)
    // =========================================================================

    event ConditionPreparation(bytes32 indexed conditionId, address indexed oracle, bytes32 indexed questionId, uint outcomeSlotCount);
    event ConditionResolution(bytes32 indexed conditionId, address indexed oracle, bytes32 indexed questionId, uint outcomeSlotCount, uint[] payoutNumerators);
    event PositionSplit(address indexed stakeholder, IERC20 collateralToken, bytes32 indexed parentCollectionId, bytes32 indexed conditionId, uint[] partition, uint amount);
    event PositionsMerge(address indexed stakeholder, IERC20 collateralToken, bytes32 indexed parentCollectionId, bytes32 indexed conditionId, uint[] partition, uint amount);
    event PayoutRedemption(address indexed redeemer, IERC20 indexed collateralToken, bytes32 indexed parentCollectionId, bytes32 conditionId, uint[] indexSets, uint payout);
}
