// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITokenSplitter} from "./interfaces/ITokenSplitter.sol";

/**
 * @title TokenSplitter
 * @author Space and Time Labs
 * @notice A contract that distributes ERC20 tokens to a fixed set of recipients based on percentage allocations
 * @dev This contract only distributes multiples of 100 tokens and keeps any remainder for future distributions.
 * Key features:
 * - Only distributes multiples of 100 tokens for efficient percentage-based calculations
 * - Holds onto any remainder until the next distribution
 * - Returns early if there are fewer than 100 tokens to distribute
 * - Uses an advanced storage pattern that combines security and gas efficiency
 * - Packs recipient address (160 bits) and percentage (8 bits) into single storage slot
 * - Requires recipient addresses to be provided in ascending order for gas efficiency
 */
contract TokenSplitter is ITokenSplitter {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error NoRecipients();
    error ArrayLengthMismatch();
    error ZeroPercentage();
    error InvalidTotalPercentage();
    error NothingToDistribute();
    error TooManyRecipients();
    error TokenAsRecipient();
    error AddressesNotAscending();

    /// @notice The ERC20 token to be distributed
    IERC20 public immutable TOKEN;

    /// @notice Maximum number of recipients (for gas efficiency)
    /// @dev Limited to 32 to ensure predictable gas costs and prevent array-related exploits
    uint8 public constant MAX_RECIPIENTS = 32;

    /// @notice Struct to store recipient data
    /// @dev Contains the recipient address and their percentage allocation
    struct Recipient {
        address recipientAddress;
        uint8 percentage;
    }

    /// @notice Array of recipients with their percentage allocations
    Recipient[] private _recipients;

    /// @notice Number of recipients
    /// @dev Immutable to save gas on length checks and prevent dynamic array issues
    uint8 private immutable _RECIPIENT_COUNT;

    /// @dev Ensures arrays are equal length and percentages sum to 100
    /// @param tokenAddress The ERC20 token address
    /// @param recipients Array of recipient addresses in ascending order
    /// @param percentages Array of percentage allocations
    /// @dev Uses memory instead of calldata for constructor parameters as required by Solidity
    /// @dev Note: The Foundry coverage tool has a bug where it fails to recognize certain branches
    /// in constructors, particularly with array length checks. This affects our coverage metrics.
    /// @dev Note: This constructor has high cyclomatic complexity due to thorough validation checks.
    /// This is a deliberate trade-off for security, as the contract is immutable after deployment.
    constructor(address tokenAddress, address[] memory recipients, uint8[] memory percentages) {
        // Initial validation
        if (tokenAddress == address(0)) revert ZeroAddress();
        if (recipients.length == 0) revert NoRecipients();
        if (recipients.length != percentages.length) revert ArrayLengthMismatch();
        if (recipients.length > MAX_RECIPIENTS) revert TooManyRecipients();

        // Initialize immutable variables
        _RECIPIENT_COUNT = uint8(recipients.length);
        TOKEN = IERC20(tokenAddress);

        // Validate recipients and percentages and store in storage
        _validateAndStoreRecipients(tokenAddress, recipients, percentages);
    }

    /// @dev Internal function to validate recipients and percentages and store them in storage
    /// @dev This function is extracted to reduce cyclomatic complexity in the constructor
    function _validateAndStoreRecipients(address tokenAddress, address[] memory recipients, uint8[] memory percentages)
        internal
    {
        uint8 totalPercentage;
        uint256 recipientsLength = recipients.length;
        address previousAddress = address(0);

        for (uint256 i = 0; i < recipientsLength; ++i) {
            address recipient = recipients[i];
            uint8 percentage = percentages[i];

            if (recipient == address(0)) revert ZeroAddress();
            if (recipient == tokenAddress) revert TokenAsRecipient();
            if (percentage == 0) revert ZeroPercentage();

            // Ensure addresses are in ascending order, which also prevents duplicates
            if (!(recipient > previousAddress)) {
                revert AddressesNotAscending();
            }
            previousAddress = recipient;

            totalPercentage += percentage;
            _recipients.push(Recipient(recipient, percentage));
        }

        if (totalPercentage != 100) revert InvalidTotalPercentage();
    }

    /**
     * @notice Distributes tokens to recipients based on their percentages
     * @dev This function only distributes multiples of 100 tokens and keeps any remainder
     * for future distributions. If there are fewer than 100 tokens available, nothing is distributed.
     * This approach allows for more efficient gas usage by pre-calculating the distribution amount
     * per percentage point.
     */
    function distribute() external {
        uint256 balance = TOKEN.balanceOf(address(this));

        // If the balance is less than 100, then we won't have enough to distribute evenly. The remaining code would distribute nothing. Instead, we revert to save the caller gas.
        // slither-disable-next-line incorrect-equality
        if (balance < 100) revert NothingToDistribute();

        // Pre-calculate amount per percentage point for gas optimization
        // slither-disable-next-line divide-before-multiply
        uint256 distributionAmountPerPercent = balance / 100;

        // Single pass: Calculate and distribute amounts
        for (uint256 i = 0; i < _RECIPIENT_COUNT; ++i) {
            Recipient memory recipient = _recipients[i];

            // Since all percentages are > 0 (validated in constructor)
            // and distributionAmountPerPercent >= 1 (since amountToDistribute >= 100),
            // amount will always be > 0, so we can skip the zero check
            uint256 amount = distributionAmountPerPercent * recipient.percentage;
            TOKEN.safeTransfer(recipient.recipientAddress, amount);
        }
    }

    /// @inheritdoc ITokenSplitter
    /// @dev Returns arrays of recipients and their percentages
    /// Note: This is a view function, so gas cost is not critical
    /// Uses uint8 for percentages to match the storage format and interface
    function getDistributionInfo() external view returns (address[] memory recipients, uint8[] memory percentages) {
        recipients = new address[](_RECIPIENT_COUNT);
        percentages = new uint8[](_RECIPIENT_COUNT);

        for (uint256 i = 0; i < _RECIPIENT_COUNT; ++i) {
            Recipient memory recipient = _recipients[i];
            recipients[i] = recipient.recipientAddress;
            percentages[i] = recipient.percentage;
        }
    }
}
