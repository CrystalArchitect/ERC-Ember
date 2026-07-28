# Formal verification artifacts

These are review inputs, not completed-proof claims. The runnable stateful Foundry invariants currently enforce exact USDC liability equality and credit conservation. The Certora specification records the corresponding v1 accounting properties but is not a CI gate and must not be described as a completed verification run without archived tool output, version, configuration, and commit.

Run `certoraRun formal/certora/conf/embercore.conf` only after updating its constructor inputs for the selected harness and setting `CERTORAKEY`.
