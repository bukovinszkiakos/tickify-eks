"use client";

import React, { useEffect, useState } from "react";
import { useAuth } from "../../context/AuthContext";
import { LogIn, Mail, Lock } from "lucide-react";
import "../../styles/LoginPage.css";
import Link from "next/link";

export default function LoginPage() {
  const { login } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [rememberMe, setRememberMe] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const savedEmail = localStorage.getItem("rememberedEmail");
    if (savedEmail) {
      setEmail(savedEmail);
      setRememberMe(true);
    }
  }, []);

  async function handleSubmit(e) {
    e.preventDefault();
    setError("");

    try {
      await login(email, password);

      if (rememberMe) {
        localStorage.setItem("rememberedEmail", email);
      } else {
        localStorage.removeItem("rememberedEmail");
      }

    } catch (err) {
      setError("Login failed. Check your credentials.");
    }
  }

  return (
    <div className="login-container">
      <div className="login-card-wrapper">
        <div className="login-info-card fadeIn">
          <div className="login-info-text">
            <h3>Welcome Back</h3>
            <p>
              Access your dashboard, manage tickets, and collaborate efficiently with your team.
            </p>
          </div>
          <img
            src="/images/login-illustration.png"
            alt="Login Illustration"
            className="login-info-image"
          />
        </div>

        <div className="login-box fadeIn">
          <h2>
            Login <LogIn size={20} />
          </h2>
          {error && <p className="error-message">{error}</p>}

          <form onSubmit={handleSubmit} className="login-form-content">
            <div className="input-box">
              <span className="icon"><Mail size={18} /></span>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder=" "
              />
              <label>Email</label>
            </div>

            <div className="input-box">
              <span className="icon"><Lock size={18} /></span>
              <input
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder=" "
              />
              <label>Password</label>
            </div>

            <div className="remember-me">
              <input
                type="checkbox"
                id="remember"
                checked={rememberMe}
                onChange={(e) => setRememberMe(e.target.checked)}
              />
              <label htmlFor="remember">Remember me</label>
            </div>

            <button type="submit" className="btn">Login</button>

            <div className="login-register">
              <p>
                Don’t have an account? <Link href="/register">Register</Link>
              </p>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
