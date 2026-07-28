// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./EmberCore.sol";
import "./IEmber.sol";

/// @title EmberCoreFactory — creation-bytecode companion for EmberFactory
contract EmberCoreFactory {
    address public immutable suiteDeployer;
    address public emberFactory;

    event EmberFactoryBound(address indexed emberFactory);
    event CoreCreated(address indexed ember, address indexed developer);

    constructor() {
        suiteDeployer = msg.sender;
    }

    function bindEmberFactory(address factory) external {
        require(msg.sender == suiteDeployer, "not suite deployer");
        require(emberFactory == address(0), "factory bound");
        require(factory != address(0) && factory.code.length > 0, "factory not contract");
        emberFactory = factory;
        emit EmberFactoryBound(factory);
    }

    function create(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        address developer,
        address dApp,
        bytes32 originalCommitment,
        string memory originalEncryptedCID,
        IEmber.SourceManifest memory srcManifest,
        address usdc,
        uint256 creditPrice,
        uint256 fundingThreshold,
        uint256 saleDuration
    ) external returns (address ember) {
        require(msg.sender == emberFactory, "not factory");
        require(developer != address(0), "no developer");
        require(dApp != address(0), "no dApp");
        require(usdc != address(0), "no USDC");
        ember = address(
            new EmberCore(
                name,
                symbol,
                maxSupply,
                developer,
                dApp,
                originalCommitment,
                originalEncryptedCID,
                srcManifest,
                usdc,
                creditPrice,
                fundingThreshold,
                saleDuration
            )
        );
        emit CoreCreated(ember, developer);
    }
}
