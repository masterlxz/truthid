import { LandingHeader } from "@/components/landing-header";
import { LandingContent } from "@/components/landing-content";

export default async function Home({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;

  return (
    <>
      <LandingHeader locale={locale} />
      <LandingContent locale={locale} />
    </>
  );
}
