import type { ReactNode } from 'react';
import { useState } from 'react';
import Layout from '@theme/Layout';
import Link from '@docusaurus/Link';
import { QRCodeSVG } from 'qrcode.react';

const DONATE_ADDRESS = '0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265';
const DONATE_URI = `ethereum:${DONATE_ADDRESS}`;

export default function Donate(): ReactNode {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    await navigator.clipboard.writeText(DONATE_ADDRESS);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <Layout
      title="Support TruthID"
      description="Support TruthID development with a crypto donation.">
      <main style={{ maxWidth: 480, margin: '4rem auto', padding: '0 1.5rem', textAlign: 'center' }}>
        <h1>Support TruthID</h1>
        <p style={{ color: 'var(--ifm-color-emphasis-700)', marginBottom: '2rem' }}>
          TruthID is open source and free — no subscriptions, no ads, no venture capital.
          If it saves you time or inspires you, a small tip helps keep the project going.
        </p>

        <div style={{
          display: 'inline-flex',
          padding: '1rem',
          background: '#fff',
          borderRadius: 12,
          marginBottom: '1.25rem',
        }}>
          <QRCodeSVG
            value={DONATE_URI}
            size={200}
            fgColor="#000000"
            bgColor="#ffffff"
          />
        </div>

        <p style={{ marginBottom: '0.5rem' }}>
          <code style={{ fontSize: '0.8rem', wordBreak: 'break-all' }}>{DONATE_ADDRESS}</code>
        </p>

        <p style={{ color: 'var(--ifm-color-emphasis-600)', fontSize: '0.85rem', marginBottom: '1.5rem' }}>
          Any EVM-compatible chain (ETH, Base, Polygon…) · 0.001 ETH suggested
        </p>

        <button
          onClick={handleCopy}
          style={{
            padding: '0.6rem 1.4rem',
            fontSize: '0.95rem',
            cursor: 'pointer',
            borderRadius: 8,
            border: '1px solid var(--ifm-color-primary)',
            background: copied ? 'var(--ifm-color-primary)' : 'transparent',
            color: copied ? '#fff' : 'var(--ifm-color-primary)',
            transition: 'all 0.2s',
          }}>
          {copied ? '✓ Copied!' : 'Copy address'}
        </button>

        <div style={{ marginTop: '3rem' }}>
          <Link to="/docs/intro">← Back to docs</Link>
        </div>
      </main>
    </Layout>
  );
}
