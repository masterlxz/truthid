import type {ReactNode} from 'react';
import {useState, useEffect} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import Heading from '@theme/Heading';

import styles from './index.module.css';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={clsx('hero', styles.heroBanner)}>
      <div className="container">
        <Heading as="h1" className="hero__title">
          {siteConfig.title}
        </Heading>
        <p className="hero__subtitle">{siteConfig.tagline}</p>
        <div className={styles.buttons}>
          <Link
            className={clsx('button button--lg', styles.ctaPrimary)}
            to="/docs/intro">
            Get Started
          </Link>
          <Link
            className={clsx('button button--outline button--lg', styles.ctaSecondary)}
            to="https://github.com/masterlxz/truthid">
            View on GitHub
          </Link>
        </div>
      </div>
    </header>
  );
}

type Asset = {name: string; browser_download_url: string};

const PLATFORM_MAP: {match: RegExp; label: string; sub: string}[] = [
  {match: /\.apk$/,        label: 'Android',  sub: 'APK'},
  {match: /\.deb$/,        label: 'Linux',     sub: '.deb'},
  {match: /AppImage$/,     label: 'Linux',     sub: 'AppImage'},
  {match: /x64-setup\.exe$/, label: 'Windows', sub: 'Installer'},
  {match: /\.msi$/,        label: 'Windows',   sub: 'MSI'},
  {match: /aarch64\.dmg$/, label: 'macOS',     sub: 'Apple Silicon'},
  {match: /x64\.dmg$/,     label: 'macOS',     sub: 'Intel'},
];

function DownloadSection() {
  const [assets, setAssets] = useState<Asset[]>([]);
  const [tag, setTag] = useState('');
  const [error, setError] = useState(false);

  useEffect(() => {
    fetch('https://api.github.com/repos/masterlxz/truthid/releases/latest')
      .then(r => r.json())
      .then(data => {
        setTag(data.tag_name ?? '');
        setAssets(data.assets ?? []);
      })
      .catch(() => setError(true));
  }, []);

  const mapped = assets
    .map(a => {
      const p = PLATFORM_MAP.find(p => p.match.test(a.name));
      return p ? {label: p.label, sub: p.sub, url: a.browser_download_url} : null;
    })
    .filter(Boolean);

  if (error || (!assets.length && tag === '')) return null;

  return (
    <section className={styles.downloadSection}>
      <div className="container">
        <Heading as="h2">Download {tag}</Heading>
        <div className={styles.downloadGrid}>
          {mapped.map((a, i) => (
            <a key={i} href={a!.url} className={styles.downloadBtn}>
              <span className={styles.downloadBtnPlatform}>{a!.label}</span>
              <span>{a!.sub}</span>
            </a>
          ))}
        </div>
        <p className={styles.downloadNote}>
          Android: enable <em>Install from unknown sources</em> before installing the APK.
        </p>
      </div>
    </section>
  );
}

function HowItWorks() {
  return (
    <section className={styles.howItWorks}>
      <div className="container">
        <Heading as="h2" className="text--center">
          How a login works
        </Heading>
        <pre className={styles.diagram}>
          <code>{`Your Backend          QR code (your frontend)        User's Phone
     |                         |                          |
     |── createChallenge() ───>|                          |
     |   embeds challenge +    |                          |
     |   callbackUrl in QR     |                          |
     |                         |───── scan QR ───────────>|
     |                         |                          |── user approves
     |                         |                          |   and signs locally
     |<──────────── POST {callbackUrl} (HTTPS, direct) ────|
     |    verifyAuthResponse() [SDK]:                       |
     |    signature valid + device active on-chain          |
     |                                                       |
     LOGIN OK`}</code>
        </pre>
        <p className="text--center">
          No TruthID-operated server sits in this path — the challenge travels
          inside the QR code, and the signed response goes straight from the
          phone to your own backend over HTTPS.
        </p>
      </div>
    </section>
  );
}

export default function Home(): ReactNode {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout
      title={siteConfig.title}
      description="Decentralized authentication. No passwords, no servers.">
      <HomepageHeader />
      <main>
        <DownloadSection />
        <HowItWorks />
        <HomepageFeatures />
      </main>
    </Layout>
  );
}
