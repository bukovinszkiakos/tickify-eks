"use client";
import React, { useEffect, useState } from "react";
import Link from "next/link";
import { PieChart, Pie, Cell, Legend, ResponsiveContainer } from "recharts";
import { apiGet } from "../../utils/api";
import "../styles/AdminDashboardPage.css";

export default function AdminDashboardPage() {
  const [stats, setStats] = useState(null);
  const [error, setError] = useState("");

  useEffect(() => {
    apiGet("/api/admin/dashboard")
      .then((data) => setStats(data))
      .catch((err) => setError(err.message));
  }, []);

  if (error) return <p className="error-message">{error}</p>;
  if (!stats) return <p>Loading dashboard...</p>;

  const chartData = [
    { name: "Open", value: stats.openTickets },
    { name: "In Progress", value: stats.inProgressTickets },
    { name: "Resolved", value: stats.resolvedTickets },
    { name: "Closed", value: stats.closedTickets },
  ];

  const COLORS = ["#28a745", "#ffc107", "#17a2b8", "#dc3545"];

  return (
    <div className="admin-dashboard-page">
      <div className="dashboard-card">
        <h1>📊 Admin Dashboard</h1>

        <div className="stats-section">
          <Link href="/admin/tickets?status=Open" className="stat-box open">
            Open: {stats.openTickets}
          </Link>
          <Link href="/admin/tickets?status=In Progress" className="stat-box in-progress">
            In Progress: {stats.inProgressTickets}
          </Link>
          <Link href="/admin/tickets?status=Resolved" className="stat-box resolved">
            Resolved: {stats.resolvedTickets}
          </Link>
          <Link href="/admin/tickets?status=Closed" className="stat-box closed">
            Closed: {stats.closedTickets}
          </Link>
          <Link href="/admin/tickets" className="stat-box total">
            Total Tickets: {stats.totalTickets}
          </Link>
        </div>

        <div className="chart-wrapper">
          <ResponsiveContainer width="100%" height={250}>
            <PieChart>
              <Pie
                data={chartData}
                dataKey="value"
                nameKey="name"
                cx="50%"
                cy="50%"
                outerRadius={80}
                innerRadius={50}
              >
                {chartData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={COLORS[index]} />
                ))}
              </Pie>
              <Legend verticalAlign="bottom" height={36} />
            </PieChart>
          </ResponsiveContainer>
        </div>

        <div className="admin-links">
          <Link href="/admin/users">Manage Users</Link>
          <Link href="/admin/tickets">Manage Tickets</Link>
        </div>
      </div>
    </div>
  );
}
