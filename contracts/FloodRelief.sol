// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title FloodRelief - Transparent Disaster Relief & Verified Aid Payout
/// @author Pratik Pokhrel (Enhanced & Audited)
/// @notice Production-grade disaster relief fund with verifiable ward-level audit trail,
///         stale claim cancellation, batch operations, and non-reentrant payouts.
contract FloodRelief {
    // ---------------------------------------------------------------- errors
    error NotAdmin();
    error NotOracle();
    error NotVerifier();
    error NotNGO();
    error ReentrantCall();
    error MaxAidIsZero();
    error DisasterNotActive();
    error DisasterStillActive();
    error NoValueDonated();
    error HouseholdAlreadyRegistered();
    error HouseholdNotRegistered();
    error HouseholdAlreadyEvacuated();
    error HouseholdNotVerified();
    error AidAlreadyClaimed();
    error AidAmountOutOfRange();
    error InsufficientPoolFunds();
    error NothingToConfirm();
    error ClaimNotCancellable();
    error PayoutFailed();

    // ---------------------------------------------------------------- roles
    address public admin;
    mapping(address => bool) public isOracle;
    mapping(address => bool) public isVerifier;
    mapping(address => bool) public isNGO;

    // ---------------------------------------------------------------- data
    struct Disaster {
        string name; // e.g. "Bhote Koshi flash flood 2026"
        bool active;
        uint256 pool; // total donated
        uint256 reserved; // locked for submitted aid claims
        uint256 paidOut; // released to NGOs after confirmed receipt
        uint256 maxAidPerHousehold;
    }

    struct Household {
        bool registered;
        bool evacuated;
        bool claimed; // one aid claim per household per disaster (prevents duplication)
        bool received;
        address ngo;
        uint256 amount;
    }

    uint256 public disasterCount;
    mapping(uint256 => Disaster) public disasters;
    mapping(uint256 => mapping(bytes32 => Household)) public households;
    mapping(uint256 => mapping(address => uint256)) public donations; // disasterId => donor => amount

    uint256 private _reentrancyStatus = 1; // 1 = NOT_ENTERED, 2 = ENTERED

    // ---------------------------------------------------------------- events
    event DisasterCreated(uint256 indexed id, string name, uint256 maxAidPerHousehold);
    event DisasterClosed(uint256 indexed id);
    event AlertAnchored(uint256 indexed disasterId, bytes32 alertHash, uint256 timestamp);
    event Donated(uint256 indexed disasterId, address indexed donor, uint256 amount);
    event HouseholdRegistered(uint256 indexed disasterId, bytes32 indexed householdHash, address verifier);
    event EvacuationConfirmed(uint256 indexed disasterId, bytes32 indexed householdHash, address verifier);
    event AidClaimSubmitted(
        uint256 indexed disasterId, bytes32 indexed householdHash, address indexed ngo, uint256 amount
    );
    event AidClaimCancelled(
        uint256 indexed disasterId, bytes32 indexed householdHash, address indexed cancelledBy, uint256 amount
    );
    event ReceiptConfirmed(uint256 indexed disasterId, bytes32 indexed householdHash, address ngo, uint256 amount);
    event RemainingFundsSwept(uint256 indexed disasterId, address indexed recipient, uint256 amount);

    // ---------------------------------------------------------------- modifiers
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyOracle() {
        if (!isOracle[msg.sender]) revert NotOracle();
        _;
    }

    modifier onlyVerifier() {
        if (!isVerifier[msg.sender]) revert NotVerifier();
        _;
    }

    modifier onlyNGO() {
        if (!isNGO[msg.sender]) revert NotNGO();
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyStatus == 2) revert ReentrantCall();
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

    constructor() {
        admin = msg.sender;
    }

    // ---------------------------------------------------------------- admin
    function setOracle(address a, bool ok) external onlyAdmin {
        isOracle[a] = ok;
    }

    function setVerifier(address a, bool ok) external onlyAdmin {
        isVerifier[a] = ok;
    }

    function setNGO(address a, bool ok) external onlyAdmin {
        isNGO[a] = ok;
    }

    function createDisaster(string calldata name, uint256 maxAidPerHousehold) external onlyAdmin returns (uint256 id) {
        if (maxAidPerHousehold == 0) revert MaxAidIsZero();
        id = ++disasterCount;
        disasters[id] = Disaster(name, true, 0, 0, 0, maxAidPerHousehold);
        emit DisasterCreated(id, name, maxAidPerHousehold);
    }

    function closeDisaster(uint256 id) external onlyAdmin {
        disasters[id].active = false;
        emit DisasterClosed(id);
    }

    /// @notice Allows admin to sweep unreserved remaining funds from a closed disaster to a relief treasury.
    function sweepRemainingFunds(uint256 disasterId, address payable recipient) external onlyAdmin nonReentrant {
        Disaster storage d = disasters[disasterId];
        if (d.active) revert DisasterStillActive();
        uint256 remaining = d.pool - d.reserved - d.paidOut;
        if (remaining == 0) revert InsufficientPoolFunds();
        d.paidOut += remaining;
        (bool ok,) = recipient.call{value: remaining}("");
        if (!ok) revert PayoutFailed();
        emit RemainingFundsSwept(disasterId, recipient, remaining);
    }

    // ---------------------------------------------------------------- 1. early-warning anchor
    function anchorAlert(uint256 disasterId, bytes32 alertHash) external onlyOracle {
        emit AlertAnchored(disasterId, alertHash, block.timestamp);
    }

    // ---------------------------------------------------------------- 2. donations
    function donate(uint256 disasterId) external payable {
        Disaster storage d = disasters[disasterId];
        if (!d.active) revert DisasterNotActive();
        if (msg.value == 0) revert NoValueDonated();
        d.pool += msg.value;
        donations[disasterId][msg.sender] += msg.value;
        emit Donated(disasterId, msg.sender, msg.value);
    }

    // ---------------------------------------------------------------- 3. verified registry
    function registerHousehold(uint256 disasterId, bytes32 householdHash) external onlyVerifier {
        _registerHousehold(disasterId, householdHash);
    }

    function registerHouseholdsBatch(uint256 disasterId, bytes32[] calldata householdHashes) external onlyVerifier {
        uint256 len = householdHashes.length;
        for (uint256 i = 0; i < len;) {
            _registerHousehold(disasterId, householdHashes[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _registerHousehold(uint256 disasterId, bytes32 householdHash) internal {
        if (!disasters[disasterId].active) revert DisasterNotActive();
        Household storage h = households[disasterId][householdHash];
        if (h.registered) revert HouseholdAlreadyRegistered();
        h.registered = true;
        emit HouseholdRegistered(disasterId, householdHash, msg.sender);
    }

    function confirmEvacuation(uint256 disasterId, bytes32 householdHash) external onlyVerifier {
        _confirmEvacuation(disasterId, householdHash);
    }

    function confirmEvacuationsBatch(uint256 disasterId, bytes32[] calldata householdHashes) external onlyVerifier {
        uint256 len = householdHashes.length;
        for (uint256 i = 0; i < len;) {
            _confirmEvacuation(disasterId, householdHashes[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _confirmEvacuation(uint256 disasterId, bytes32 householdHash) internal {
        Household storage h = households[disasterId][householdHash];
        if (!h.registered) revert HouseholdNotRegistered();
        if (h.evacuated) revert HouseholdAlreadyEvacuated();
        h.evacuated = true;
        emit EvacuationConfirmed(disasterId, householdHash, msg.sender);
    }

    // ---------------------------------------------------------------- 4. aid claim -> receipt -> payout
    function submitAidClaim(uint256 disasterId, bytes32 householdHash, uint256 amount) external onlyNGO {
        Disaster storage d = disasters[disasterId];
        Household storage h = households[disasterId][householdHash];
        if (!d.active) revert DisasterNotActive();
        if (!h.registered || !h.evacuated) revert HouseholdNotVerified();
        if (h.claimed) revert AidAlreadyClaimed();
        if (amount == 0 || amount > d.maxAidPerHousehold) revert AidAmountOutOfRange();
        if (d.pool - d.reserved - d.paidOut < amount) revert InsufficientPoolFunds();

        h.claimed = true;
        h.ngo = msg.sender;
        h.amount = amount;
        d.reserved += amount;

        emit AidClaimSubmitted(disasterId, householdHash, msg.sender, amount);
    }

    /// @notice Allows the claiming NGO, verifier, or admin to cancel an undelivered claim, freeing reserved funds and unblocking the household.
    function cancelAidClaim(uint256 disasterId, bytes32 householdHash) external {
        Household storage h = households[disasterId][householdHash];
        if (!h.claimed || h.received) revert ClaimNotCancellable();
        if (msg.sender != h.ngo && !isVerifier[msg.sender] && msg.sender != admin) revert NotNGO();

        uint256 amount = h.amount;
        Disaster storage d = disasters[disasterId];
        d.reserved -= amount;

        h.claimed = false;
        h.ngo = address(0);
        h.amount = 0;

        emit AidClaimCancelled(disasterId, householdHash, msg.sender, amount);
    }

    function confirmReceipt(uint256 disasterId, bytes32 householdHash) external onlyVerifier nonReentrant {
        _confirmReceipt(disasterId, householdHash);
    }

    function confirmReceiptsBatch(uint256 disasterId, bytes32[] calldata householdHashes)
        external
        onlyVerifier
        nonReentrant
    {
        uint256 len = householdHashes.length;
        for (uint256 i = 0; i < len;) {
            _confirmReceipt(disasterId, householdHashes[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _confirmReceipt(uint256 disasterId, bytes32 householdHash) internal {
        Disaster storage d = disasters[disasterId];
        Household storage h = households[disasterId][householdHash];
        if (!h.claimed || h.received) revert NothingToConfirm();

        h.received = true;
        uint256 amount = h.amount;
        address ngoAddress = h.ngo;

        d.reserved -= amount;
        d.paidOut += amount;

        (bool ok,) = payable(ngoAddress).call{value: amount}("");
        if (!ok) revert PayoutFailed();

        emit ReceiptConfirmed(disasterId, householdHash, ngoAddress, amount);
    }

    // ---------------------------------------------------------------- views
    function available(uint256 disasterId) external view returns (uint256) {
        Disaster storage d = disasters[disasterId];
        return d.pool - d.reserved - d.paidOut;
    }
}
