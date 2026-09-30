import type { Metadata } from "next";
import Link from "next/link";
import { LandingHeader } from "@/components/landing-header";
import { DonateCard } from "@/components/donate-card";

export const metadata: Metadata = {
  title: "Donate to TruthID",
  description: "Donate to TruthID development with a crypto donation.",
};

// English only, on the unprefixed root like "/" and "/docs" (see
// app/layout.tsx) — the URL is the one the old Docusaurus site served.
export default function Donate() {
  return (
    <>
      <LandingHeader locale="en" />
      <main className="mx-auto w-full max-w-md px-6 py-16 text-center">
        <h1 className="mb-4 text-3xl font-semibold">Donate to TruthID</h1>
        <p className="mb-8 text-fd-muted-foreground">
          TruthID is open source and free — no subscriptions, no ads, no venture capital. If it
          saves you time or inspires you, a small tip helps keep the project going.
        </p>
        <DonateCard />
        <div className="mt-12">
          <Link href="/docs/intro" className="text-fd-primary">
            ← Back to docs
          </Link>
        </div>
      </main>
    </>
  );
}
