"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { Link, useRouter } from "@/i18n/navigation";
import { SiteHeader } from "@/components/site-header";

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
  const t = useTranslations("dashboard");
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
    router.push("/signin");
  }

  if (status === "loading") {
    return (
      <>
        <SiteHeader />
        <main className="flex flex-1 items-center justify-center">
          <p className="text-sm text-gray-500">{t("loading")}</p>
        </main>
      </>
    );
  }

  if (status === "anonymous") {
    return (
      <>
        <SiteHeader />
        <main className="flex flex-1 flex-col items-center justify-center gap-4">
          <p>{t("notSignedIn")}</p>
          <Link href="/signin" className="text-sm underline">
            {t("back")}
          </Link>
        </main>
      </>
    );
  }

  return (
    <>
      <SiteHeader />
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
          {t("hello", { name: customer?.name ?? customer?.email ?? "" })}
        </h1>
        <p className="text-sm text-gray-500">{customer?.email}</p>
        <button
          onClick={handleLogout}
          className="rounded-full border px-6 py-2 text-sm font-medium transition hover:bg-gray-100"
        >
          {t("signOut")}
        </button>
      </main>
    </>
  );
}
