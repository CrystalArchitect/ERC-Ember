// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./EmberCoreFactory.sol";
import "./MaintenancePoolFactory.sol";
import "./IEmber.sol";
import "./IERC20Token.sol";

/// @title EmberFactory — adminless canonical ERC-EMBER v1 registry
/// @notice SPDX expressions are developer declarations, not legal, OSI,
/// ownership, archive, or reproducible-build verification.
contract EmberFactory {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 public constant MAX_LICENSE_LENGTH = 128;

    address public immutable CANONICAL_USDC;
    EmberCoreFactory public immutable CORE_FACTORY;
    MaintenancePoolFactory public immutable POOL_FACTORY;

    struct DeploymentInfo {
        address developer;
        uint256 deployedAt;
        address maintenancePool;
        bytes32 parentDeployment;
        bytes32 licenseDeclarationHash;
    }

    address[] public deployments;
    mapping(address => DeploymentInfo) public info;
    mapping(address => address[]) public devProjects;
    mapping(address => address) public poolForEmber;
    uint256 private _reentrancyStatus;

    event Deployed(
        address indexed token,
        address indexed developer,
        address maintenancePool,
        bytes32 parentDeployment,
        bytes32 licenseDeclarationHash
    );

    modifier nonReentrant() {
        require(_reentrancyStatus != _ENTERED, "reentrant");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    constructor(address coreFactory, address poolFactory, address canonicalUsdc) {
        require(coreFactory != address(0) && coreFactory.code.length > 0, "core factory not contract");
        require(poolFactory != address(0) && poolFactory.code.length > 0, "pool factory not contract");
        require(canonicalUsdc != address(0) && canonicalUsdc.code.length > 0, "USDC not contract");
        require(IERC20Token(canonicalUsdc).decimals() == 6, "USDC decimals");
        CORE_FACTORY = EmberCoreFactory(coreFactory);
        POOL_FACTORY = MaintenancePoolFactory(poolFactory);
        CANONICAL_USDC = canonicalUsdc;
        _reentrancyStatus = _NOT_ENTERED;
    }

    // Registry writes intentionally follow successful companion creation so no
    // failed deployment is recorded. Both companions are irrevocably bound to
    // this nonReentrant factory and cannot callback into deploy.
    // slither-disable-next-line reentrancy-benign
    function deploy(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        address dApp,
        bytes32 originalCommitment,
        string memory originalEncryptedCID,
        IEmber.SourceManifest memory srcManifest,
        uint256 creditPrice,
        uint256 fundingThreshold,
        uint256 saleDuration,
        bool spawnMaintenancePool,
        address poolGovernor,
        uint256 poolTimelockDelay,
        bytes32 parentDeployment
    ) external nonReentrant returns (address ember, address pool) {
        require(
            POOL_FACTORY.emberFactory() == address(this) && CORE_FACTORY.emberFactory() == address(this),
            "suite not bound"
        );
        uint256 declarationLength = bytes(srcManifest.spdxLicense).length;
        require(declarationLength > 0 && declarationLength <= MAX_LICENSE_LENGTH, "bad SPDX declaration");
        require(dApp != address(0), "no dApp");
        require(!spawnMaintenancePool || poolGovernor != address(0), "no governor");

        ember = CORE_FACTORY.create(
            name,
            symbol,
            maxSupply,
            msg.sender,
            dApp,
            originalCommitment,
            originalEncryptedCID,
            srcManifest,
            CANONICAL_USDC,
            creditPrice,
            fundingThreshold,
            saleDuration
        );

        if (spawnMaintenancePool) {
            pool = POOL_FACTORY.create(ember, poolGovernor, CANONICAL_USDC, poolTimelockDelay);
            poolForEmber[ember] = pool;
        }

        bytes32 declarationHash = keccak256(bytes(srcManifest.spdxLicense));
        deployments.push(ember);
        info[ember] = DeploymentInfo(msg.sender, block.timestamp, pool, parentDeployment, declarationHash);
        devProjects[msg.sender].push(ember);
        emit Deployed(ember, msg.sender, pool, parentDeployment, declarationHash);
    }

    function deploymentCount() external view returns (uint256) {
        return deployments.length;
    }

    function projectsByDeveloper(address dev) external view returns (address[] memory) {
        return devProjects[dev];
    }
}
