"use client";

import React from "react";
import Link from "next/link";
import { useAuth } from "../../context/AuthContext";
import { Player } from "@lottiefiles/react-lottie-player";
import { Ticket, Settings, Shield } from "lucide-react";
import NotificationBell from "../NotificationBell/NotificationBell";
import "../../styles/Navbar.css";

export default function Navbar() {
  const { user, logout } = useAuth();

  const isAdmin = user?.roles?.includes("Admin");
  const isSuperAdmin = user?.roles?.includes("SuperAdmin");

  async function handleLogout() {
    try {
      await logout();
    } catch (err) {
      console.error("Logout error:", err);
    }
  }

  return (
    <header className="heading">
      <nav className="navbar">
        <div className="navbar-left">
          <div className="logo-container">
            <img
              src="/tickify-logo.png"
              alt="Tickify Logo"
              className="tickify-logo"
              draggable={false}
            />
            <span className="logo-text">Tickify</span>
          </div>
          {user && <NotificationBell />}
        </div>

        <div className="navbar-right">
          <Link href="/" className="nav-link">
            <button className="nav-button">
              Home
              <Player
                src="/animations/home-animation.json"
                className="animation"
                autoplay
                loop
              />
            </button>
          </Link>

          {user && !isAdmin && !isSuperAdmin && (
            <Link href="/tickets" className="nav-link">
              <button className="nav-button">
                My Tickets
                <Ticket className="animation" />
              </button>
            </Link>
          )}

          {user && (isAdmin || isSuperAdmin) && (
            <>
              <Link href="/admin/tickets" className="nav-link">
                <button className="nav-button">
                  Manage
                  <Settings className="animation" />
                </button>
              </Link>

              <Link href="/admin" className="nav-link">
                <button className="nav-button">
                  Admin
                  <Shield className="animation" />
                </button>
              </Link>
            </>
          )}

          {!user && (
            <>
              <Link href="/login" className="nav-link">
                <button className="nav-button">
                  Login
                  <Player
                    src="/animations/login-animation.json"
                    className="animation"
                    autoplay
                    loop
                  />
                </button>
              </Link>

              <Link href="/register" className="nav-link">
                <button className="nav-button">
                  Register
                  <Player
                    src="/animations/register-animation.json"
                    className="animation"
                    autoplay
                    loop
                  />
                </button>
              </Link>
            </>
          )}

          {user && (
            <button className="logout-button" onClick={handleLogout}>
              Logout
              <Player
                src="/animations/logout-animation.json"
                className="animation"
                autoplay
                loop
              />
            </button>
          )}
        </div>
      </nav>
    </header>
  );
}
