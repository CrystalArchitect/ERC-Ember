import React, { useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import {
  type Address, type Hex, createPublicClient, createWalletClient, custom,
  decodeEventLog, getAddress, isAddress,
} from 'viem';
import { contracts } from './generated/contracts';
import './styles.css';

const zero32 = `0x${'0'.repeat(64)}` as Hex;
type Status = { kind: 'ok' | 'error' | 'info'; text: string };

function address(value: string, label: string): Address {
  if (!isAddress(value)) throw new Error(`${label} must be an address`);
  return getAddress(value);
}
function uint(value: string, label: string): bigint {
  if (!/^\d+$/.test(value)) throw new Error(`${label} must be an unsigned integer`);
  return BigInt(value);
}
function bytes32(value: string, label: string, allowZero = false): Hex {
  if (!/^0x[0-9a-fA-F]{64}$/.test(value) || (!allowZero && value === zero32)) throw new Error(`${label} must be nonzero bytes32`);
  return value as Hex;
}

function App() {
  const provider = window.ethereum;
  const clients = useMemo(() => provider ? {
    public: createPublicClient({ transport: custom(provider) }),
    wallet: createWalletClient({ transport: custom(provider) }),
  } : null, [provider]);
  const [account, setAccount] = useState<Address>();
  const [status, setStatus] = useState<Status[]>([]);
  const [busy, setBusy] = useState(false);
  const [factory, setFactory] = useState('');
  const [canonicalUsdc, setCanonicalUsdc] = useState('');
  const [form, setForm] = useState({
    name: 'Example Ember', symbol: 'EMBER', maxSupply: '1000000', dApp: '',
    commitment: '', encryptedCid: 'ipfs://encrypted-source', archiveHash: '', treeRoot: '',
    lockfileHash: '', artifactHash: '', spdx: 'MIT', manifestCid: 'ipfs://source-manifest',
    creditPrice: '10000', fundingThreshold: '100000', saleDuration: '2592000',
    spawnPool: false, governor: '', timelock: '604800', parent: zero32,
  });
  const [registry, setRegistry] = useState<Array<{ token: Address; developer: Address; pool: Address; declaration: Hex }>>([]);

  function log(kind: Status['kind'], text: string) { setStatus(s => [{ kind, text }, ...s].slice(0, 10)); }
  async function run(task: () => Promise<void>) {
    if (!clients) return log('error', 'No injected wallet found');
    setBusy(true); try { await task(); } catch (e) { log('error', e instanceof Error ? e.message : String(e)); } finally { setBusy(false); }
  }
  async function connect() { await run(async () => {
    const [selected] = await clients!.wallet.requestAddresses(); setAccount(selected); log('ok', `Connected ${selected}`);
  }); }
  async function deploySuite() { await run(async () => {
    if (!account) throw new Error('Connect a wallet first');
    const hash = await clients!.wallet.deployContract({
      chain: null,
      account, abi: contracts.EmberSuiteDeployer.abi, bytecode: contracts.EmberSuiteDeployer.bytecode,
      args: [address(canonicalUsdc, 'Canonical USDC')],
    });
    const receipt = await clients!.public.waitForTransactionReceipt({ hash });
    const suite = receipt.contractAddress;
    if (!suite) throw new Error('Suite deployment address missing');
    const deployedFactory = await clients!.public.readContract({ address: suite, abi: contracts.EmberSuiteDeployer.abi, functionName: 'emberFactory' });
    setFactory(deployedFactory); log('ok', `Adminless suite deployed; factory ${deployedFactory}`);
  }); }
  async function deployProject() { await run(async () => {
    if (!account) throw new Error('Connect a wallet first');
    const factoryAddress = address(factory, 'Factory');
    if (!form.spdx || form.spdx.length > 128) throw new Error('SPDX declaration must be 1–128 bytes');
    const governor = form.spawnPool ? address(form.governor, 'Contract governor') : '0x0000000000000000000000000000000000000000';
    if (form.spawnPool) {
      const code = await clients!.public.getCode({ address: governor });
      if (!code || code === '0x') throw new Error('Maintenance governor must be a contract');
    }
    const args = [
      form.name, form.symbol, uint(form.maxSupply, 'Max supply'), address(form.dApp, 'dApp'),
      bytes32(form.commitment, 'Original commitment'), form.encryptedCid,
      { archiveHash: bytes32(form.archiveHash, 'Archive hash'), fileTreeMerkleRoot: bytes32(form.treeRoot, 'Tree root'),
        lockfileHash: bytes32(form.lockfileHash, 'Lockfile hash'), buildArtifactHash: bytes32(form.artifactHash, 'Artifact hash'),
        spdxLicense: form.spdx, manifestCID: form.manifestCid },
      uint(form.creditPrice, 'Credit price'), uint(form.fundingThreshold, 'Funding threshold'),
      uint(form.saleDuration, 'Sale duration'), form.spawnPool, governor,
      uint(form.timelock, 'Pool timelock'), bytes32(form.parent, 'Parent', true),
    ] as const;
    const hash = await clients!.wallet.writeContract({ chain: null, account, address: factoryAddress, abi: contracts.EmberFactory.abi, functionName: 'deploy', args });
    const receipt = await clients!.public.waitForTransactionReceipt({ hash });
    const event = receipt.logs.map(logEntry => { try { return decodeEventLog({ abi: contracts.EmberFactory.abi, data: logEntry.data, topics: logEntry.topics }); } catch { return null; } })
      .find(decoded => decoded?.eventName === 'Deployed');
    log('ok', event ? `Project deployed: ${(event.args as { token: Address }).token}` : `Project transaction confirmed: ${hash}`);
  }); }
  async function loadRegistry() { await run(async () => {
    const factoryAddress = address(factory, 'Factory');
    const count = await clients!.public.readContract({ address: factoryAddress, abi: contracts.EmberFactory.abi, functionName: 'deploymentCount' });
    const rows = await Promise.all(Array.from({ length: Number(count) }, async (_, i) => {
      const token = await clients!.public.readContract({ address: factoryAddress, abi: contracts.EmberFactory.abi, functionName: 'deployments', args: [BigInt(i)] });
      const info = await clients!.public.readContract({ address: factoryAddress, abi: contracts.EmberFactory.abi, functionName: 'info', args: [token] });
      return { token, developer: info[0], pool: info[2], declaration: info[4] };
    }));
    setRegistry(rows); log('ok', `Loaded ${rows.length} on-chain registry entries`);
  }); }
  const field = (key: keyof typeof form, label: string) => <label>{label}<input value={String(form[key])} onChange={e => setForm({ ...form, [key]: e.target.value })} /></label>;

  return <main className="app-shell"><header><h1>ERC-EMBER v1 deployer</h1><p>Fee-free flat-price credits. License text is developer-declared and unverified.</p><button onClick={connect} disabled={busy}>{account ? 'Wallet connected' : 'Connect wallet'}</button></header>
    <section className="card"><h2>1. Deploy adminless suite</h2><label>Canonical 6-decimal USDC<input value={canonicalUsdc} onChange={e => setCanonicalUsdc(e.target.value)} /></label><button onClick={deploySuite} disabled={busy}>Deploy and bind suite</button></section>
    <section className="card"><h2>2. Deploy project</h2><label>Factory<input value={factory} onChange={e => setFactory(e.target.value)} /></label>
      {field('name','Name')}{field('symbol','Symbol')}{field('maxSupply','Maximum credits')}{field('dApp','dApp contract')}{field('commitment','Genesis key commitment')}{field('encryptedCid','Encrypted archive CID')}
      {field('archiveHash','Archive hash')}{field('treeRoot','File-tree root')}{field('lockfileHash','Lockfile hash')}{field('artifactHash','Build artifact hash')}{field('spdx','SPDX expression — developer-declared, unverified')}{field('manifestCid','Manifest CID')}
      {field('creditPrice','Flat price (micro-USDC, divisible by 5)')}{field('fundingThreshold','Funding threshold (credits)')}{field('saleDuration','Sale duration (seconds)')}
      <label><input type="checkbox" checked={form.spawnPool} onChange={e => setForm({ ...form, spawnPool: e.target.checked })} /> Optional maintenance pool — tips are irreversible governor/timelock-trusted donations</label>
      {form.spawnPool && <>{field('governor','Contract governor')}{field('timelock','Timelock seconds')}</>}{field('parent','Parent deployment hash')}
      <button onClick={deployProject} disabled={busy}>Deploy project</button></section>
    <section className="card"><h2>3. On-chain registry</h2><button onClick={loadRegistry} disabled={busy}>Load registry</button>{registry.map(r => <p key={r.token}>{r.token} — developer {r.developer} — pool {r.pool} — declaration hash {r.declaration}</p>)}</section>
    <section className="card"><h2>Status</h2>{status.map((s,i) => <p key={i} className={s.kind}>{s.text}</p>)}</section>
  </main>;
}

createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
