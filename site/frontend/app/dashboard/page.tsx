"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

const apiUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

type Customer = {
  id: number;
  email: string;
  name: string | null;
  avatar_url: string | null;
};

type Status = "loading" | "authed" | "anonymous";

export default function DashboardPage() {
  const router = useRouter();
  const [customer, setCustomer] = useState<Customer | null>(null);
  const [status, setStatus] = useState<Status>("loading");

  useEffect(() => {
    let cancelled = false;

    fetch(`${apiUrl}/api/me`, { credentials: "include" })
      .then(async (res) => {
        if (cancelled) return;
        if (!res.ok) {
          setStatus("anonymous");
          return;
        }
        setCustomer(await res.json());
        setStatus("authed");
      })
      .catch(() => {
        if (!cancelled) setStatus("anonymous");
      });

    return () => {
      cancelled = true;
    };
  }, []);

  async function handleLogout() {
    await fetch(`${apiUrl}/logout`, { method: "DELETE", credentials: "include" });
    router.push("/");
  }

  if (status === "loading") {
    return (
      <main className="flex flex-1 items-center justify-center">
        <p className="text-sm text-gray-500">Loading…</p>
      </main>
    );
  }

  if (status === "anonymous") {
    return (
      <main className="flex flex-1 flex-col items-center justify-center gap-4">
        <p>You are not signed in.</p>
        <Link href="/" className="text-sm underline">
          Back
        </Link>
      </main>
    );
  }

  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-4 p-8">
      {customer?.avatar_url && (
        // eslint-disable-next-line @next/next/no-img-element -- avatar vem de uma URL externa (Google), sem otimização local
        <img
          src={customer.avatar_url}
          alt=""
          className="h-16 w-16 rounded-full object-cover"
        />
      )}
      <h1 className="text-xl font-semibold">
        Hello, {customer?.name ?? customer?.email}
      </h1>
      <p className="text-sm text-gray-500">{customer?.email}</p>
      <button
        onClick={handleLogout}
        className="rounded-full border px-6 py-2 text-sm font-medium transition hover:bg-gray-100"
      >
        Sign out
      </button>
    </main>
  );
}
