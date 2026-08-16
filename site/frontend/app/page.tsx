const apiUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-6 p-8 text-center">
      <h1 className="text-3xl font-semibold">TruthID</h1>
      <p className="max-w-md text-sm text-gray-500">
        Sign in to continue. Login is OAuth-only — no password of your own.
      </p>
      {error && (
        <p className="rounded bg-red-100 px-4 py-2 text-sm text-red-700">
          Could not sign in ({error}). Please try again.
        </p>
      )}
      {/* Full-page navigation on purpose — this is how the OAuth handshake needs to
          work (Google redirects the browser back to Rails, this can't be done
          via fetch/XHR). */}
      <a
        href={`${apiUrl}/auth/google_oauth2`}
        className="rounded-full bg-black px-6 py-3 text-sm font-medium text-white transition hover:bg-gray-800"
      >
        Sign in with Google
      </a>
    </main>
  );
}
