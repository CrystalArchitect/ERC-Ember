// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// slither-disable-start timestamp
import "./IEmber.sol";
import "./IERC20Token.sol";
import "./vendor/OZSignatureChecker.sol";

/// @title EmberCore — fee-free, holder-safe ERC-EMBER v1 credits
/// @notice Credits sell at one immutable price. Each consumed credit earns the
/// developer 80%; 20% remains locked until all committed source keys are
/// incrementally revealed. Failed and abandoned projects refund live credits.
contract EmberCore is IEmber {
    using OZSignatureChecker for address;

    enum SaleOutcome {
        Active,
        Successful,
        Failed
    }

    struct SourceUpdate {
        bytes32 commitment;
        string encryptedCID;
        bytes32 manifestHash;
        uint256 timestamp;
    }

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant USE_AUTHORIZATION_TYPEHASH = keccak256(
        "UseAuthorization(address user,address dApp,uint256 amount,bytes32 usageId,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant _NAME_HASH = keccak256("ERC-EMBER");
    bytes32 private constant _VERSION_HASH = keccak256("1");

    uint256 public constant RELEASE_QUORUM_BPS = 8_000;
    uint256 public constant RELEASE_TIMEOUT = 730 days;
    uint256 public constant EMBER_WINDOW = 30 days;
    uint256 public constant ABANDONMENT_TIMEOUT = 365 days;
    uint256 public constant MIN_SALE_DURATION = 7 days;
    uint256 public constant MAX_SALE_DURATION = 365 days;
    uint256 public constant MAX_LICENSE_LENGTH = 128;

    string public name;
    string public symbol;
    uint8 public constant decimals = 0;

    uint256 public immutable override INITIAL_SUPPLY;
    uint256 public immutable creditPrice;
    uint256 public immutable developerPerCredit;
    uint256 public immutable releaseReservePerCredit;
    uint256 public immutable fundingThreshold;
    uint256 public immutable saleStart;
    uint256 public immutable saleDeadline;
    address public immutable developer;
    address public immutable dApp;
    IERC20Token public immutable USDC;
    bytes32 public immutable originalCommitment;

    string public originalEncryptedCID;
    SourceManifest private _manifest;
    SourceUpdate[] public updates;
    string[] public revealedKeys;

    SaleOutcome public saleOutcome;
    bool public saleClosed;
    bool public override released;
    bool public override slashed;
    bool public override abandoned;
    uint256 public finalSoldSupply;
    uint256 public closeTimestamp;
    uint256 public override releaseDeadline;
    uint256 public override totalBurned;
    uint256 public totalRedeemed;
    uint256 public tokensSold;
    uint256 public totalRaised;
    uint256 public developerEarned;
    uint256 public releaseReserveAccrued;
    uint256 public devClaimed;
    uint256 public reserveSlashed;
    uint256 public override lastUserActivity;

    uint256 private _totalSupply;
    uint256 private _reentrancyStatus;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => mapping(address => uint256)) public burnAllowance;
    mapping(address => mapping(uint256 => bool)) public usedNonces;
    mapping(bytes32 => bool) public usedUsageIds;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BurnApproval(address indexed owner, address indexed app, uint256 exactAmount);
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 usdcCost);
    event SaleClosed(SaleOutcome outcome, uint256 finalSoldSupply, uint256 unsoldRetired);
    event DevWithdrew(uint256 usdcAmount);

    modifier onlyDeveloper() {
        require(msg.sender == developer, "not developer");
        _;
    }

    modifier nonReentrant() {
        require(_reentrancyStatus != _ENTERED, "reentrant");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 maxSupply,
        address _developer,
        address _dApp,
        bytes32 _originalCommitment,
        string memory _originalEncryptedCID,
        SourceManifest memory srcManifest,
        address usdc,
        uint256 _creditPrice,
        uint256 _fundingThreshold,
        uint256 saleDuration
    ) {
        require(maxSupply > 0 && _developer != address(0) && _dApp != address(0), "bad params");
        require(_dApp.code.length > 0, "dApp not contract");
        require(_originalCommitment != bytes32(0), "no commitment");
        require(usdc != address(0) && usdc.code.length > 0, "USDC not contract");
        require(_creditPrice > 0 && _creditPrice % 5 == 0, "price not exact 80/20");
        require(_creditPrice <= type(uint256).max / maxSupply, "sale value overflow");
        require(_fundingThreshold > 0 && _fundingThreshold <= maxSupply, "bad threshold");
        require(saleDuration >= MIN_SALE_DURATION && saleDuration <= MAX_SALE_DURATION, "bad sale duration");
        uint256 licenseLength = bytes(srcManifest.spdxLicense).length;
        require(licenseLength > 0 && licenseLength <= MAX_LICENSE_LENGTH, "bad SPDX declaration");
        require(srcManifest.archiveHash != bytes32(0), "no archive hash");

        name = _name;
        symbol = _symbol;
        INITIAL_SUPPLY = maxSupply;
        creditPrice = _creditPrice;
        developerPerCredit = (_creditPrice * 4) / 5;
        releaseReservePerCredit = _creditPrice / 5;
        fundingThreshold = _fundingThreshold;
        saleStart = block.timestamp;
        saleDeadline = block.timestamp + saleDuration;
        developer = _developer;
        dApp = _dApp;
        USDC = IERC20Token(usdc);
        originalCommitment = _originalCommitment;
        originalEncryptedCID = _originalEncryptedCID;
        _manifest = srcManifest;
        _totalSupply = maxSupply;
        _balances[address(this)] = maxSupply;
        lastUserActivity = block.timestamp;
        _reentrancyStatus = _NOT_ENTERED;
        emit Transfer(address(0), address(this), maxSupply);
    }

    function manifest() external view override returns (SourceManifest memory) {
        return _manifest;
    }

    function quote(uint256 amount) public view returns (uint256) {
        return creditPrice * amount;
    }

    function funded() public view returns (bool) {
        return tokensSold >= fundingThreshold;
    }

    function buy(uint256 amount, uint256 maxCost) external override nonReentrant {
        require(!saleClosed && block.timestamp <= saleDeadline, "sale closed");
        require(amount > 0 && _balances[address(this)] >= amount, "sold out");
        uint256 cost = quote(amount);
        require(cost <= maxCost, "slippage");
        tokensSold += amount;
        totalRaised += cost;
        _transfer(address(this), msg.sender, amount, false);
        lastUserActivity = block.timestamp;
        _safeUsdcTransferFrom(msg.sender, address(this), cost);
        emit TokensPurchased(msg.sender, amount, cost);
    }

    function closeSale() external override {
        require(!saleClosed, "sale closed");
        bool deadlineReached = block.timestamp > saleDeadline;
        if (!deadlineReached) {
            require(msg.sender == developer, "developer only before deadline");
            require(funded(), "threshold not met");
            require(block.timestamp >= saleStart + MIN_SALE_DURATION, "minimum sale duration");
        }
        _closeSale(funded() ? SaleOutcome.Successful : SaleOutcome.Failed);
    }

    function _closeSale(SaleOutcome outcome) internal {
        saleClosed = true;
        saleOutcome = outcome;
        finalSoldSupply = tokensSold;
        closeTimestamp = block.timestamp;
        uint256 unsold = _balances[address(this)];
        if (unsold > 0) {
            _balances[address(this)] = 0;
            _totalSupply -= unsold;
            emit Transfer(address(this), address(0), unsold);
        }
        emit SaleClosed(outcome, finalSoldSupply, unsold);
        if (outcome == SaleOutcome.Successful && finalSoldSupply > 0 && totalBurned == finalSoldSupply) {
            _openEmberPhase();
        }
    }

    function approveBurn(address app, uint256 exactAmount) external override returns (bool) {
        require(app == dApp, "wrong dApp");
        burnAllowance[msg.sender][app] = exactAmount;
        lastUserActivity = block.timestamp;
        emit BurnApproval(msg.sender, app, exactAmount);
        return true;
    }

    /// @notice Testnet fallback. The allowance must exactly equal this one use;
    /// ordinary ERC-20 transfer approval is never consulted.
    function useApp(address user, uint256 amount, bytes32 usageId) external override returns (bool) {
        require(msg.sender == dApp, "only dApp");
        require(burnAllowance[user][msg.sender] == amount, "exact burn allowance");
        burnAllowance[user][msg.sender] = 0;
        emit BurnApproval(user, msg.sender, 0);
        _consume(user, amount, usageId);
        return true;
    }

    function useAppWithAuthorization(
        address user,
        uint256 amount,
        bytes32 usageId,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external override returns (bool) {
        require(msg.sender == dApp, "only dApp");
        require(block.timestamp <= deadline, "authorization expired");
        require(!usedNonces[user][nonce], "nonce used");
        bytes32 structHash =
            keccak256(abi.encode(USE_AUTHORIZATION_TYPEHASH, user, dApp, amount, usageId, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        require(user.isValidSignatureNow(digest, signature), "invalid signature");
        usedNonces[user][nonce] = true;
        _consume(user, amount, usageId);
        return true;
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(_DOMAIN_TYPEHASH, _NAME_HASH, _VERSION_HASH, block.chainid, address(this)));
    }

    function _consume(address user, uint256 amount, bytes32 usageId) internal {
        require(funded(), "funding threshold not met");
        require(!abandoned && saleOutcome != SaleOutcome.Failed, "settlement only");
        require(releaseDeadline == 0, "ember phase: burns frozen");
        require(user != address(0) && amount > 0 && _balances[user] >= amount, "bad burn");
        require(usageId != bytes32(0) && !usedUsageIds[usageId], "usage id used");
        usedUsageIds[usageId] = true;
        _balances[user] -= amount;
        _totalSupply -= amount;
        totalBurned += amount;
        developerEarned += developerPerCredit * amount;
        releaseReserveAccrued += releaseReservePerCredit * amount;
        lastUserActivity = block.timestamp;
        emit Transfer(user, address(0), amount);
        emit TokensBurnedForUse(user, amount, usageId, totalBurned);
        if (saleClosed && saleOutcome == SaleOutcome.Successful && totalBurned == finalSoldSupply) {
            _openEmberPhase();
        }
    }

    function updateSource(bytes32 newCommitment, string calldata newCID, bytes32 newManifestHash)
        external
        onlyDeveloper
    {
        require(!abandoned && releaseDeadline == 0, "source frozen");
        require(newCommitment != bytes32(0) && bytes(newCID).length > 0 && newManifestHash != bytes32(0), "bad source");
        updates.push(SourceUpdate(newCommitment, newCID, newManifestHash, block.timestamp));
        emit SourceUpdated(updates.length, newCommitment, newCID);
    }

    function openEmberPhase() external override onlyDeveloper {
        require(saleClosed && saleOutcome == SaleOutcome.Successful, "sale not successful");
        _openEmberPhase();
    }

    function forceEmberPhase() external override {
        require(saleClosed && saleOutcome == SaleOutcome.Successful, "sale not successful");
        // slither-disable-next-line incorrect-equality
        require(releaseDeadline == 0, "already triggered");
        bool fullBurn = totalBurned == finalSoldSupply;
        bool quorum = finalSoldSupply > 0 && totalBurned * 10_000 >= finalSoldSupply * RELEASE_QUORUM_BPS
            && block.timestamp >= closeTimestamp + RELEASE_TIMEOUT;
        require(fullBurn || quorum, "neither path met");
        _openEmberPhase();
    }

    function _openEmberPhase() internal {
        // Zero is the explicit not-opened sentinel.
        // slither-disable-next-line incorrect-equality
        require(!abandoned && releaseDeadline == 0, "already triggered");
        releaseDeadline = block.timestamp + EMBER_WINDOW;
        emit EmberPhase(releaseDeadline);
    }

    function revealKey(uint256 index, string calldata decryptionKey) external override {
        require(releaseDeadline != 0 && !released && !slashed && !abandoned, "not revealable");
        require(index == revealedKeys.length && index <= updates.length, "wrong key index");
        bytes32 commitment = index == 0 ? originalCommitment : updates[index - 1].commitment;
        // Exact preimage equality is the source-commitment verification.
        // slither-disable-next-line incorrect-equality
        require(keccak256(bytes(decryptionKey)) == commitment, "wrong key");
        revealedKeys.push(decryptionKey);
        emit SourceKeyRevealed(index, decryptionKey);
    }

    function finalizeRelease() external override {
        require(releaseDeadline != 0 && !released && !slashed && !abandoned, "not releasable");
        // Every committed version must have exactly one revealed key.
        // slither-disable-next-line incorrect-equality
        require(revealedKeys.length == updates.length + 1, "keys incomplete");
        released = true;
        emit SourceReleased(revealedKeys.length);
        emit ContractTerminated(totalBurned, block.timestamp);
    }

    function slashReserve() external override nonReentrant {
        require(releaseDeadline != 0 && !released && !slashed, "not slashable");
        require(block.timestamp > releaseDeadline, "still in window");
        _slashAccruedReserve();
        emit ContractTerminated(totalBurned, block.timestamp);
    }

    function finalizeAbandonment() external override nonReentrant {
        require(!abandoned, "already abandoned");
        require(block.timestamp > lastUserActivity + ABANDONMENT_TIMEOUT, "user activity recent");
        if (!saleClosed) _closeSale(funded() ? SaleOutcome.Successful : SaleOutcome.Failed);
        abandoned = true;
        uint256 slashedAmount = 0;
        if (!released && !slashed) {
            slashedAmount = releaseReserveAccrued;
            _slashAccruedReserve();
        }
        emit AbandonmentSettled(redemptionLiability(), slashedAmount);
        emit ContractTerminated(totalBurned, block.timestamp);
    }

    function _slashAccruedReserve() internal {
        slashed = true;
        uint256 amount = releaseReserveAccrued - reserveSlashed;
        reserveSlashed = releaseReserveAccrued;
        if (amount > 0) _safeUsdcTransfer(address(0xdEaD), amount);
        emit ReserveSlashed(amount);
    }

    function redemptionEnabled() public view returns (bool) {
        return abandoned || saleOutcome == SaleOutcome.Failed || releaseDeadline != 0;
    }

    function redemptionQuote(uint256 amount) public view override returns (uint256) {
        return amount * creditPrice;
    }

    function redeem(uint256 amount) external override nonReentrant {
        require(redemptionEnabled(), "redemption unavailable");
        require(amount > 0 && _balances[msg.sender] >= amount, "bad amount");
        uint256 payout = redemptionQuote(amount);
        _balances[msg.sender] -= amount;
        _totalSupply -= amount;
        totalRedeemed += amount;
        lastUserActivity = block.timestamp;
        emit Transfer(msg.sender, address(0), amount);
        _safeUsdcTransfer(msg.sender, payout);
        emit Redeemed(msg.sender, amount, payout);
    }

    function outstandingLiveCredits() public view returns (uint256) {
        return tokensSold - totalBurned - totalRedeemed;
    }

    function redemptionLiability() public view returns (uint256) {
        return outstandingLiveCredits() * creditPrice;
    }

    function lockedReleaseLiability() public view returns (uint256) {
        if (released || slashed) return 0;
        return releaseReserveAccrued;
    }

    function devClaimable() public view override returns (uint256) {
        uint256 vested = developerEarned + (released ? releaseReserveAccrued : 0);
        return vested > devClaimed ? vested - devClaimed : 0;
    }

    function totalLiabilities() public view returns (uint256) {
        return redemptionLiability() + devClaimable() + lockedReleaseLiability();
    }

    function withdrawDev() external override onlyDeveloper nonReentrant {
        require(funded(), "funding threshold not met");
        uint256 amount = devClaimable();
        require(amount > 0, "nothing");
        devClaimed += amount;
        _safeUsdcTransfer(developer, amount);
        emit DevWithdrew(amount);
    }

    function terminated() external view override returns (bool) {
        return released || slashed || abandoned;
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IEmber).interfaceId;
    }

    function updateCount() external view returns (uint256) {
        return updates.length;
    }

    function revealedKeyCount() external view returns (uint256) {
        return revealedKeys.length;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external returns (bool) {
        require(spender != address(0), "zero address");
        _allowances[msg.sender][spender] = value;
        lastUserActivity = block.timestamp;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value, true);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 approved = _allowances[from][msg.sender];
        require(approved >= value, "allowance");
        if (approved != type(uint256).max) {
            _allowances[from][msg.sender] = approved - value;
            emit Approval(from, msg.sender, approved - value);
        }
        _transfer(from, to, value, true);
        return true;
    }

    function _transfer(address from, address to, uint256 value, bool userActivity) internal {
        require(from != address(0) && to != address(0), "zero address");
        require(to != address(this) || from == address(this), "contract recipient");
        require(_balances[from] >= value, "balance");
        _balances[from] -= value;
        _balances[to] += value;
        if (userActivity) lastUserActivity = block.timestamp;
        emit Transfer(from, to, value);
    }

    // Exact deltas reject no-op and fee-on-transfer payment tokens.
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
