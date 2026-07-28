# Canonical v1 launch deployer

The browser and Foundry scripts deploy an adminless suite. `EmberSuiteDeployer` creates `EmberCoreFactory`, `MaintenancePoolFactory`, and `EmberFactory` and binds both companions in its constructor. No owner, allowlist curator, fee recipient, or recovery recipient exists.

Required factory input is only the reviewed canonical six-decimal USDC address for the target chain. The suite does not prove the operator chose the right token; verify chain ID, code, issuer documentation, and deployment output independently.

Project inputs include flat `CREDIT_PRICE` (micro-USDC divisible by five), `FUNDING_THRESHOLD` (credits), `SALE_DURATION`, a contract dApp, source commitments, and a 1–128 byte SPDX expression. Display the expression as “Developer-declared — unverified.”

Optional maintenance pools require a contract governor and timelock. Tips are irreversible governor/timelock-trusted donations. No ContributorVote or BurnReceiptVote mode exists.

```bash
forge script script/DeployFactory.s.sol:DeployFactory --rpc-url "$RPC_URL" --broadcast --verify
forge script script/CheckFactoryDeployment.s.sol:CheckFactoryDeployment --rpc-url "$RPC_URL"
forge script script/DeployProject.s.sol:DeployProject --rpc-url "$RPC_URL" --broadcast --verify
forge script script/CheckProjectDeployment.s.sol:CheckProjectDeployment --rpc-url "$RPC_URL"
```

Before production, complete a testnet lifecycle for successful funding/use, missed-threshold refunds, source release, missed-release slash, and abandonment. Freeze the reviewed contracts and deploy a new versioned suite; do not present older immutable factories as canonical v1.
