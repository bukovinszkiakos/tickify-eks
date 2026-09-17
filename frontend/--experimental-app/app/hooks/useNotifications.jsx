"use client";

import { useEffect, useState } from "react";
import { apiGet } from "../../utils/api";

export function useNotifications() {
  const [notifications, setNotifications] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function load() {
      try {
        const res = await apiGet("/api/user/notifications");
        setNotifications(res ?? []);
      } catch (err) {
        console.error("Failed to load notifications:", err);
      } finally {
        setLoading(false);
      }
    }

    load();
  }, []);

  return { notifications, loading, setNotifications };
}
