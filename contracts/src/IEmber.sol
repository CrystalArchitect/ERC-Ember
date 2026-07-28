// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./IERC165.sol";

/// @title IEmber — canonical fee-free ERC-EMBER v1 interface
interface IEmber is IERC165 {
    struct SourceManifest {
        bytes32 archiveHash;
        bytes32 fileTreeMerkleRoot;
        bytes32 lockfileHash;
        bytes32 buildArtifactHash;
        string spdxLicense;
        string manifestCID;
    }

    event TokensBurnedForUse(address indexed user, uint256 amount, bytes32 indexed usageId, uint256 totalBurned);
    event SourceUpdated(uint256 indexed version, bytes32 commitment, string encryptedCID);
    event SourceKeyRevealed(uint256 indexed index, string decryptionKey);
    event SourceReleased(uint256 keyCount);
    event EmberPhase(uint256 deadline);
    event ContractTerminated(uint256 finalBurned, uint256 timestamp);
    event Redeemed(address indexed holder, uint256 tokens, uint256 usdc);
    event ReserveSlashed(uint256 usdcAmount);
    event AbandonmentSettled(uint256 liveCreditLiability, uint256 reserveSlashed);

    function INITIAL_SUPPLY() external view returns (uint256);
    function totalBurned() external view returns (uint256);
    function released() external view returns (bool);
    function slashed() external view returns (bool);
    function abandoned() external view returns (bool);
    function lastUserActivity() external view returns (uint256);
    function terminated() external view returns (bool);
    function manifest() external view returns (SourceManifest memory);
    function releaseDeadline() external view returns (uint256);
    function devClaimable() external view returns (uint256);
    function redemptionQuote(uint256 amount) external view returns (uint256);

    function buy(uint256 amount, uint256 maxCost) external;
    function approveBurn(address app, uint256 exactAmount) external returns (bool);
    function useApp(address user, uint256 amount, bytes32 usageId) external returns (bool);
    function useAppWithAuthorization(
        address user,
        uint256 amount,
        bytes32 usageId,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external returns (bool);
    function closeSale() external;
    function openEmberPhase() external;
    function forceEmberPhase() external;
    function revealKey(uint256 index, string calldata decryptionKey) external;
    function finalizeRelease() external;
    function slashReserve() external;
    function finalizeAbandonment() external;
    function redeem(uint256 amount) external;
    function withdrawDev() external;
}
