"use client";

import React, { createContext, useContext, useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { apiGet, apiPost } from "../../utils/api";

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const router = useRouter();

  async function fetchUser() {
    try {
      const res = await apiGet("/Auth/Me");

      if (!res || !res.email) {
        setUser(null);
        return null;
      }

      res.roles = res.roles || [];
      res.isAdmin =
        res.roles.includes("Admin") || res.roles.includes("SuperAdmin");
      res.isSuperAdmin = res.roles.includes("SuperAdmin");
      setUser(res);
      return res;
    } catch (err) {
      console.error("Unexpected error fetching user:", err);
      setUser(null);
      return null;
    }
  }

  useEffect(() => {
    fetchUser();
  }, []);

  async function login(email, password) {
    try {
      await apiPost("/Auth/Login", { Email: email, Password: password });
      const userData = await fetchUser();
      if (userData?.isSuperAdmin || userData?.isAdmin) {
        router.push("/admin/tickets");
      } else {
        router.push("/tickets");
      }
    } catch (err) {
      console.error("Login error:", err);
      throw err;
    }
  }

  async function logout() {
    try {
      await apiPost("/Auth/Logout", {});
    } catch (err) {
      console.warn("Logout API failed, possibly already logged out:", err);
    } finally {
      setUser(null);
      router.push("/login");
    }
  }

  return (
    <AuthContext.Provider value={{ user, login, logout, fetchUser }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
