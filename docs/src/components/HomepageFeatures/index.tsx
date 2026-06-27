import type {ReactNode} from 'react';
import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

function LockIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
      <rect x="5" y="11" width="14" height="10" rx="2" />
      <path d="M8 11V7a4 4 0 0 1 8 0v4" />
      <circle cx="12" cy="16" r="1.4" fill="currentColor" stroke="none" />
    </svg>
  );
}

function WalletIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
      <rect x="3" y="6" width="18" height="13" rx="2" />
      <path d="M3 10h18" />
      <circle cx="16" cy="14.5" r="1.4" fill="currentColor" stroke="none" />
    </svg>
  );
}

function CodeIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
      <path d="M8 6l-5 6 5 6" />
      <path d="M16 6l5 6-5 6" />
    </svg>
  );
}

type FeatureItem = {
  title: string;
  Icon: React.ComponentType;
  description: ReactNode;
};

const FeatureList: FeatureItem[] = [
  {
    title: 'No Passwords, No Servers',
    Icon: LockIcon,
    description: (
      <>
        Login challenges travel inside a QR code; the signed response goes
        straight from the user&apos;s phone to your own backend over HTTPS.
        No TruthID-operated server ever sits in the path.
      </>
    ),
  },
  {
    title: 'Self-Sovereign Identity',
    Icon: WalletIcon,
    description: (
      <>
        Users own their identity through a blockchain wallet, not an account
        you control. Trusted devices sign locally — private keys never leave
        the device.
      </>
    ),
  },
  {
    title: 'Open Source SDKs',
    Icon: CodeIcon,
    description: (
      <>
        Drop-in <code>truthid-sdk</code> packages for TypeScript, Python, and
        Ruby verify signatures and device status on-chain, so your backend
        never talks to the blockchain directly.
      </>
    ),
  },
];

function Feature({title, Icon, description}: FeatureItem) {
  return (
    <div className={clsx('col col--4')}>
      <div className={styles.card}>
        <Icon />
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
