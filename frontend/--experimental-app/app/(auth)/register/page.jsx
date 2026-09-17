"use client";

import React, { useState } from "react";
import { useRouter } from "next/navigation";
import { apiPost } from "../../../utils/api";
import { UserPlus, User, Mail, Lock } from "lucide-react";
import Link from "next/link";
import "../../styles/RegisterPage.css";

export default function RegisterPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");

  async function handleRegister(e) {
    e.preventDefault();
    setError("");
    try {
      await apiPost("/Auth/Register", {
        Email: email,
        Username: username,
        Password: password,
      });
      router.push("/login");
    } catch (err) {
      setError("Registration failed.");
    }
  }

  return (
    <div className="register-container">
      <div className="register-card-wrapper">
        <div className="info-card fadeIn">
          <div className="info-card-text">
            <h3>Why Join Tickify?</h3>
            <p>
              Get instant updates, manage your tickets efficiently, and collaborate with our team —
              all in one intuitive platform.
            </p>
          </div>
          <img
            src="/images/register-illustration.png"
            alt="Register Illustration"
            className="info-image"
          />
        </div>

        <div className="register-box fadeIn">
          <h2>
            Register <UserPlus size={20} />
          </h2>
          {error && <p className="error-message">{error}</p>}

          <form onSubmit={handleRegister}>
            <div className="input-box">
              <span className="icon"><User size={18} /></span>
              <input
                type="text"
                required
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder=" "
              />
              <label>Username</label>
            </div>

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

            <button type="submit" className="btn">Register</button>

            <div className="login-register">
              <p>
                Already have an account? <Link href="/login">Login</Link>
              </p>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
