// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 6-decimal USDC mock implementing the ERC20 surface the adapter needs
///         (balanceOf / transfer / transferFrom / approve / allowance / decimals)
///         plus EIP-3009 `receiveWithAuthorization` with real EIP-712 signature
///         verification and per-payer (per-authorizer) nonce tracking.
/// @dev    Mirrors Circle's FiatTokenV2 EIP-3009 surface closely enough for tests
///         to sign with `vm.sign` and exercise replay / expiry / wrong-signer
///         paths. `receiveWithAuthorization` enforces `to == msg.sender` so a
///         third party cannot redirect a payer's authorized funds.
contract MockEIP3009USDC {
    string public constant name = "Mock EIP-3009 USDC";
    string public constant symbol = "USDC";
    uint8 public constant decimals = 6;
    string public constant version = "2";

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // authorizer => nonce => used
    mapping(address => mapping(bytes32 => bool)) public authorizationState;

    // keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

    bytes32 public immutable DOMAIN_SEPARATOR;

    event Transfer(address indexed from, address indexed to, uint256 v);
    event Approval(address indexed owner, address indexed spender, uint256 v);
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                address(this)
            )
        );
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= value, "allowance");
        if (a != type(uint256).max) {
            allowance[from][msg.sender] = a - value;
            emit Approval(from, msg.sender, a - value);
        }
        _transfer(from, to, value);
        return true;
    }

    /// @notice EIP-3009: pull `value` from `from` to `msg.sender` against a signed
    ///         authorization. `to` MUST equal `msg.sender` (receive-style), so only
    ///         the intended recipient can redeem the authorization.
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(to == msg.sender, "caller must be payee");
        // forge-lint: disable-next-line(block-timestamp)
        require(block.timestamp > validAfter, "auth not yet valid");
        // forge-lint: disable-next-line(block-timestamp)
        require(block.timestamp < validBefore, "auth expired");
        require(!authorizationState[from][nonce], "auth used");

        bytes32 structHash =
            keccak256(abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = ecrecover(digest, v, r, s);
        require(signer != address(0) && signer == from, "invalid signature");

        authorizationState[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);

        _transfer(from, to, value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(balanceOf[from] >= value, "balance");
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }
}

/// @notice 6-dp EIP-3009 USDC whose `receiveWithAuthorization` reports success
///         (no revert) but moves nothing — the no-op variant. Proves the adapter's
///         exact-delta check after `receiveWithAuthorization` rejects credits for
///         money that never moved. Signature is NOT verified (the delta check is
///         the safety net under test).
contract NoOpEIP3009USDC {
    string public constant name = "No-op EIP-3009 USDC";
    string public constant symbol = "USDC";
    uint8 public constant decimals = 6;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function receiveWithAuthorization(address, address to, uint256, uint256, uint256, bytes32, uint8, bytes32, bytes32)
        external
        view
    {
        require(to == msg.sender, "caller must be payee");
        // Moves nothing.
    }
}

/// @notice 6-dp EIP-3009 USDC that delivers `value - 1` on receive (fee-on-
///         transfer style), so the adapter's exact-delta check rejects it.
contract FeeOnTransferEIP3009USDC {
    string public constant name = "FoT EIP-3009 USDC";
    string public constant symbol = "USDC";
    uint8 public constant decimals = 6;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _move(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= value, "allowance");
        if (a != type(uint256).max) allowance[from][msg.sender] = a - value;
        _move(from, to, value);
        return true;
    }

    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256,
        uint256,
        bytes32,
        uint8,
        bytes32,
        bytes32
    ) external {
        require(to == msg.sender, "caller must be payee");
        _move(from, to, value);
    }

    function _move(address from, address to, uint256 value) internal {
        require(balanceOf[from] >= value, "balance");
        uint256 received = value == 0 ? 0 : value - 1;
        balanceOf[from] -= value;
        balanceOf[to] += received;
        totalSupply -= value - received;
    }
}

/// @notice EIP-3009 USDC that attempts a configured reentrant callback in the
///         middle of `receiveWithAuthorization` (after marking the nonce used,
///         before moving funds), to prove the adapter's `nonReentrant` guard
///         blocks reentry into `settleAndCredit`.
contract ReentrantEIP3009USDC {
    string public constant name = "Reentrant EIP-3009 USDC";
    string public constant symbol = "USDC";
    uint8 public constant decimals = 6;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => mapping(bytes32 => bool)) public authorizationState;

    address public target;
    bytes public payload;
    bool public attemptedReentry;
    bool public reentrySucceeded;
    bool private _inCall;

    event Transfer(address indexed from, address indexed to, uint256 v);

    function setReentry(address target_, bytes calldata payload_) external {
        target = target_;
        payload = payload_;
        attemptedReentry = false;
        reentrySucceeded = false;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= value, "allowance");
        if (a != type(uint256).max) allowance[from][msg.sender] = a - value;
        _transfer(from, to, value);
        return true;
    }

    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256, /* validAfter */
        uint256, /* validBefore */
        bytes32 nonce,
        uint8, /* v */
        bytes32, /* r */
        bytes32 /* s */
    ) external {
        require(to == msg.sender, "caller must be payee");
        require(!authorizationState[from][nonce], "auth used");
        authorizationState[from][nonce] = true;
        _attemptReentry();
        _transfer(from, to, value);
    }

    function _attemptReentry() internal {
        if (_inCall || target == address(0)) return;
        _inCall = true;
        attemptedReentry = true;
        (reentrySucceeded,) = target.call(payload);
        _inCall = false;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(balanceOf[from] >= value, "balance");
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }
}
