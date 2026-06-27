import type {ReactNode} from 'react';
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
        <HowItWorks />
        <HomepageFeatures />
      </main>
    </Layout>
  );
}
