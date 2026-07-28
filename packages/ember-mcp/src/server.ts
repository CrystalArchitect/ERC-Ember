export interface ExperimentalMcpServerConfig { readonly enabled: false }
export function createExperimentalMcpServer(): never {
  throw new Error('MCP/x402 is not part of canonical ERC-EMBER v1');
}
