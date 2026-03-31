pragma solidity ^0.5.1;

import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import { ERC20Detailed } from "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import { IERC1155TokenReceiver } from "./ERC1155/IERC1155TokenReceiver.sol";

/// @dev Interface for the ConditionalTokens functions we need.
interface IConditionalTokens {
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external;
    function balanceOf(address owner, uint256 id) external view returns (uint256);
}

/// @title WrappedPositionToken
/// @dev ERC20 wrapper around a single ERC1155 position from ConditionalTokens.
///      Wrapping: ERC1155 tokens are transferred to this contract, ERC20 minted 1:1.
///      Unwrapping: ERC20 burned, ERC1155 returned 1:1.
///      Deployed via CREATE2 from the ConditionalTokens contract for deterministic addresses.
contract WrappedPositionToken is ERC20, ERC20Detailed {
    IConditionalTokens public conditionalTokens;
    uint256 public positionId;

    event Deposit(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);

    constructor(address _conditionalTokens, uint256 _positionId)
        ERC20Detailed("Wrapped CT Position", "wCTPos", 18)
        public
    {
        conditionalTokens = IConditionalTokens(_conditionalTokens);
        positionId = _positionId;
    }

    /// @dev Called by the ERC1155 contract when tokens are transferred to this wrapper.
    ///      Mints ERC20 to the depositor. Supports two flows:
    ///      1. Via ConditionalTokens.wrap() — _from is address(0) (mint), recipient decoded from _data.
    ///      2. Via direct safeTransferFrom to this contract — _from is the depositor.
    function onERC1155Received(
        address,
        address _from,
        uint256 _id,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bytes4) {
        require(msg.sender == address(conditionalTokens), "only CT contract");
        require(_id == positionId, "wrong position ID");

        address recipient = _from;
        if (_from == address(0) && _data.length >= 32) {
            (recipient) = abi.decode(_data, (address));
        }
        require(recipient != address(0), "cannot mint to zero address");

        _mint(recipient, _amount);
        emit Deposit(recipient, _amount);

        return this.onERC1155Received.selector;
    }

    /// @dev Reject batch transfers — each wrapper handles exactly one position ID.
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external returns (bytes4) {
        revert("batch transfers not supported");
    }

    /// @dev Burns ERC20 and returns the underlying ERC1155 position tokens to the caller.
    /// @param _amount Amount of wrapped tokens to unwrap.
    function unwrap(uint256 _amount) external {
        _burn(msg.sender, _amount);
        conditionalTokens.safeTransferFrom(address(this), msg.sender, positionId, _amount, "");
        emit Withdrawal(msg.sender, _amount);
    }

    /// @dev Returns the total ERC1155 tokens held by this wrapper (should equal totalSupply).
    function underlyingBalance() external view returns (uint256) {
        return conditionalTokens.balanceOf(address(this), positionId);
    }
}
