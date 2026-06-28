import { useState, useCallback } from "react";

const KEY = "truthid:username";

export function useStoredUsername() {
  const [username, setUsername] = useState<string | null>(
    () => localStorage.getItem(KEY)
  );

  const save = useCallback((u: string) => {
    localStorage.setItem(KEY, u);
    setUsername(u);
  }, []);

  const clear = useCallback(() => {
    localStorage.removeItem(KEY);
    setUsername(null);
  }, []);

  return { username, save, clear };
}
