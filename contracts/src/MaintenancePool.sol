// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// slither-disable-start timestamp
import "./IERC20Token.sol";

/// @title MaintenancePool — optional contract-governed donation pool
/// @notice Tips are irreversible donations trusted to the current governor and
/// timelock. A governor rotation increments the proposal epoch, atomically
/// invalidating every proposal queued by an earlier governor.
contract MaintenancePool {
    enum ProposalType {
        Draw,
        GovernorChange,
        Sunset
    }
    enum PoolState {
        Open,
        SunsetPending,
        Closed
    }

    struct Proposal {
        ProposalType ptype;
        address target;
        uint256 amount;
        uint256 eta;
        uint256 epoch;
        bool executed;
        bool canceled;
        string reason;
    }

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 public constant MIN_TIMELOCK_DELAY = 1 days;
    uint256 public constant MAX_TIMELOCK_DELAY = 30 days;
    uint256 public constant SUNSET_INACTIVITY = 365 days;

    IERC20Token public immutable USDC;
    address public immutable emberToken;
    uint256 public immutable timelockDelay;
    address public governor;
    uint256 public governanceEpoch;
    PoolState public state;
    uint256 public lastDrawTimestamp;
    uint256 public proposalCount;
    uint256 public pendingSunsetId;
    uint256 private _reentrancyStatus;
    mapping(uint256 => Proposal) public proposals;

    event Tipped(address indexed from, uint256 amount, string memo);
    event ForkRoyalty(address indexed fromFork, uint256 amount);
    event Claimed(address indexed to, uint256 amount, string reason);
    event GovernorChanged(address indexed oldGovernor, address indexed newGovernor, uint256 newEpoch);
    event Sunset(address indexed to, uint256 amount, string reason);
    event ProposalQueued(
        uint256 indexed id,
        ProposalType ptype,
        address target,
        uint256 amount,
        uint256 eta,
        uint256 epoch,
        string reason
    );
    event ProposalExecuted(uint256 indexed id);
    event ProposalCanceled(uint256 indexed id);
    event PoolClosed();

    modifier onlyGovernor() {
        require(msg.sender == governor, "not governor");
        _;
    }
    modifier fundingOpen() {
        require(state == PoolState.Open, "funding closed");
        _;
    }
    modifier notClosed() {
        require(state != PoolState.Closed, "pool closed");
        _;
    }
    modifier nonReentrant() {
        require(_reentrancyStatus != _ENTERED, "reentrant");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    constructor(address _emberToken, address _governor, address _usdc, uint256 _timelockDelay) {
        require(_emberToken != address(0) && _emberToken.code.length > 0, "ember not contract");
        require(_governor != address(0) && _governor.code.length > 0, "governor not contract");
        require(_usdc != address(0) && _usdc.code.length > 0, "USDC not contract");
        require(_timelockDelay >= MIN_TIMELOCK_DELAY && _timelockDelay <= MAX_TIMELOCK_DELAY, "bad delay");
        emberToken = _emberToken;
        governor = _governor;
        USDC = IERC20Token(_usdc);
        timelockDelay = _timelockDelay;
        lastDrawTimestamp = block.timestamp;
        _reentrancyStatus = _NOT_ENTERED;
    }

    function tip(uint256 amount, string calldata memo) external fundingOpen nonReentrant {
        require(amount > 0, "zero amount");
        _safeUsdcTransferFrom(msg.sender, address(this), amount);
        emit Tipped(msg.sender, amount, memo);
    }

    function payForkRoyalty(uint256 amount) external fundingOpen nonReentrant {
        require(amount > 0, "zero amount");
        _safeUsdcTransferFrom(msg.sender, address(this), amount);
        emit ForkRoyalty(msg.sender, amount);
    }

    function queueDraw(uint256 amount, address to, string calldata reason)
        external
        onlyGovernor
        fundingOpen
        returns (uint256)
    {
        require(amount > 0 && to != address(0), "bad draw");
        return _queue(ProposalType.Draw, to, amount, reason);
    }

    function queueGovernorChange(address newGovernor) external onlyGovernor fundingOpen returns (uint256) {
        require(newGovernor != address(0) && newGovernor.code.length > 0, "governor not contract");
        return _queue(ProposalType.GovernorChange, newGovernor, 0, "");
    }

    function queueSunset(address recipient, string calldata reason)
        external
        onlyGovernor
        fundingOpen
        returns (uint256 id)
    {
        require(recipient != address(0), "zero recipient");
        require(_sunsetReady(), "still active");
        id = _queue(ProposalType.Sunset, recipient, 0, reason);
        state = PoolState.SunsetPending;
        pendingSunsetId = id;
    }

    function _queue(ProposalType ptype, address target, uint256 amount, string memory reason)
        internal
        returns (uint256 id)
    {
        id = ++proposalCount;
        uint256 eta = block.timestamp + timelockDelay;
        proposals[id] = Proposal(ptype, target, amount, eta, governanceEpoch, false, false, reason);
        emit ProposalQueued(id, ptype, target, amount, eta, governanceEpoch, reason);
    }

    function execute(uint256 id) external notClosed nonReentrant {
        require(id > 0 && id <= proposalCount, "unknown proposal");
        Proposal storage proposal = proposals[id];
        require(!proposal.executed && !proposal.canceled, "inactive proposal");
        require(proposal.epoch == governanceEpoch, "stale proposal");
        require(block.timestamp >= proposal.eta, "timelock");
        proposal.executed = true;

        if (proposal.ptype == ProposalType.Draw) {
            require(state == PoolState.Open, "sunset pending");
            lastDrawTimestamp = block.timestamp;
            _safeUsdcTransfer(proposal.target, proposal.amount);
            emit Claimed(proposal.target, proposal.amount, proposal.reason);
        } else if (proposal.ptype == ProposalType.GovernorChange) {
            address oldGovernor = governor;
            governor = proposal.target;
            governanceEpoch++;
            if (state == PoolState.SunsetPending) {
                state = PoolState.Open;
                pendingSunsetId = 0;
            }
            emit GovernorChanged(oldGovernor, proposal.target, governanceEpoch);
        } else {
            require(state == PoolState.SunsetPending && pendingSunsetId == id, "not pending sunset");
            require(_sunsetReady(), "still active");
            state = PoolState.Closed;
            pendingSunsetId = 0;
            uint256 balance = USDC.balanceOf(address(this));
            if (balance > 0) _safeUsdcTransfer(proposal.target, balance);
            emit Sunset(proposal.target, balance, proposal.reason);
            emit PoolClosed();
        }
        emit ProposalExecuted(id);
    }

    function cancel(uint256 id) external onlyGovernor {
        require(id > 0 && id <= proposalCount, "unknown proposal");
        Proposal storage proposal = proposals[id];
        require(proposal.epoch == governanceEpoch, "stale proposal");
        require(!proposal.executed && !proposal.canceled, "inactive proposal");
        proposal.canceled = true;
        if (id == pendingSunsetId) {
            pendingSunsetId = 0;
            state = PoolState.Open;
        }
        emit ProposalCanceled(id);
    }

    function closed() external view returns (bool) {
        return state == PoolState.Closed;
    }

    function _sunsetReady() internal view returns (bool) {
        return block.timestamp > lastDrawTimestamp + SUNSET_INACTIVITY;
    }

    // slither-disable-start incorrect-equality,reentrancy-balance
    function _safeUsdcTransfer(address to, uint256 value) internal {
        uint256 fromBefore = USDC.balanceOf(address(this));
        uint256 toBefore = USDC.balanceOf(to);
        (bool success, bytes memory data) = address(USDC).call(abi.encodeCall(IERC20Token.transfer, (to, value)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "USDC transfer failed");
        uint256 fromAfter = USDC.balanceOf(address(this));
        uint256 toAfter = USDC.balanceOf(to);
        require(fromBefore >= fromAfter && fromBefore - fromAfter == value, "USDC debit");
        require(toAfter >= toBefore && toAfter - toBefore == value, "USDC credit");
    }

    function _safeUsdcTransferFrom(address from, address to, uint256 value) internal {
        uint256 beforeBalance = USDC.balanceOf(to);
        (bool success, bytes memory data) =
            address(USDC).call(abi.encodeCall(IERC20Token.transferFrom, (from, to, value)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "USDC pull failed");
        uint256 afterBalance = USDC.balanceOf(to);
        require(afterBalance >= beforeBalance && afterBalance - beforeBalance == value, "USDC pull amount");
    }
    // slither-disable-end incorrect-equality,reentrancy-balance
}
// slither-disable-end timestamp
