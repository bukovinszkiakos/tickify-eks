"use client";

import React, { useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { apiGet, apiPut, apiPost } from "../../utils/api";
import { useAuth } from "../context/AuthContext";
import "../styles/AdminTicketsPage.css";



export default function AdminTicketsPage() {
  const { user } = useAuth();
  const [tickets, setTickets] = useState([]);
  const [admins, setAdmins] = useState([]);
  const [error, setError] = useState("");
  const [filterStatus, setFilterStatus] = useState("");
  const [filterPriority, setFilterPriority] = useState("");
  const [onlyMine, setOnlyMine] = useState(false);
  const [reassignValues, setReassignValues] = useState({});
  const searchParams = useSearchParams();

  useEffect(() => {
    const statusFromUrl = searchParams.get("status");
    if (statusFromUrl) setFilterStatus(statusFromUrl);

    const priorityFromUrl = searchParams.get("priority");
    if (priorityFromUrl) setFilterPriority(priorityFromUrl);

    fetchTickets();
    fetchAdmins();
  }, []);

  async function fetchTickets() {
    try {
      const data = await apiGet("/api/admin/tickets");
      setTickets(data);
    } catch (err) {
      setError(err.message);
    }
  }

  async function fetchAdmins() {
    try {
      const data = await apiGet("/api/admin/users");
      const filtered = data.filter(
        (u) => u.roles.includes("Admin") || u.roles.includes("SuperAdmin")
      );
      setAdmins(filtered);
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleReassign(ticketId, newAdminId) {
    try {
      if (newAdminId === "null") newAdminId = null;
      await apiPost(`/api/admin/tickets/${ticketId}/reassign`, { newAdminId });
      setReassignValues((prev) => ({ ...prev, [ticketId]: "" }));
      await fetchTickets();
    } catch (err) {
      setError("Failed to reassign ticket.");
    }
  }

  async function handleAssignToMe(ticketId) {
    try {
      await apiPost(`/api/admin/tickets/${ticketId}/assign-to-me`, {});
      await fetchTickets();
    } catch (err) {
      setError("Failed to assign ticket.");
    }
  }

  async function handleUpdateStatus(ticketId, newStatus) {
    try {
      await apiPut(`/api/admin/tickets/${ticketId}/status/${newStatus}`, {});
      await fetchTickets();
    } catch (err) {
      setError(err.message);
    }
  }

  const filteredTickets = tickets
    .filter((t) => !filterStatus || t.status === filterStatus)
    .filter((t) => !filterPriority || t.priority === filterPriority)
    .filter((t) => !onlyMine || t.assignedTo === user?.id);

  return (
    <div className="admin-tickets-container">
      <br></br>
      <h1>Manage Tickets</h1>

      <div className="filters">
        <label>
          Status Filter:
          <select
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value)}
          >
            <option value="">All</option>
            <option>Open</option>
            <option>In Progress</option>
            <option>Resolved</option>
            <option>Closed</option>
          </select>
        </label>

        <label>
          Priority Filter:
          <select
            value={filterPriority}
            onChange={(e) => setFilterPriority(e.target.value)}
          >
            <option value="">All</option>
            <option>Low</option>
            <option>Normal</option>
            <option>High</option>
          </select>
        </label>

        <label className="mine-filter">
          <input
            type="checkbox"
            checked={onlyMine}
            onChange={(e) => setOnlyMine(e.target.checked)}
          />
          Show only tickets assigned to me
        </label>
      </div>

      {error && <p className="error-message">{error}</p>}

      <ul className="ticket-list">
        {filteredTickets.map((ticket) => {
          const isAssignedToMe =
            (ticket.assignedTo ?? "").trim() === (user?.id ?? "").trim();
          const isUnassigned = !ticket.assignedTo;

          return (
            <li key={ticket.id} className="ticket-item">
              <div className="ticket-title-container">
                <Link
                  href={`/tickets/${ticket.id}`}
                  className="ticket-title"
                  title={ticket.title}
                >
                  {ticket.title}
                </Link>

                {ticket.status === "Resolved" && (
                  <span className="status-badge resolved">✅ Resolved</span>
                )}
                {ticket.status === "Closed" && (
                  <span className="status-badge closed">❌ Closed</span>
                )}
              </div>

              <div className="status-info">
                {ticket.status} / {ticket.priority}
              </div>

              <div className="created-info">
                Created by:{" "}
                <span className="creator-name">
                  {ticket.createdByName || "Unknown"}
                </span>
              </div>

              <div className="assigned-info">
                {ticket.assignedTo ? (
                  <span className="assigned-badge">
                    Assigned to {ticket.assignedToName || "Admin"}
                  </span>
                ) : (
                  <span className="unassigned-badge">Unassigned</span>
                )}
              </div>

              <div className="comment-stats">
                💬 {ticket.totalCommentCount} comment
                {ticket.totalCommentCount !== 1 && "s"}
                {ticket.unreadCommentCount > 0 && (
                  <span className="unread-badge">
                    ({ticket.unreadCommentCount} new)
                  </span>
                )}
              </div>

              <div className="status-buttons">
              {user?.roles?.includes("SuperAdmin") ? (
                  <>
                    <select
                      value={reassignValues[ticket.id] ?? ""}
                      onChange={(e) => {
                        setReassignValues((prev) => ({ ...prev, [ticket.id]: e.target.value }));
                        handleReassign(ticket.id, e.target.value);
                      }}
                    >
                      <option value="">Assign to...</option>
                      {admins.map((admin) => (
                        <option key={admin.id} value={admin.id}>
                          {admin.userName || admin.email}
                          {admin.id === user?.id ? " (me)" : ""}
                        </option>
                      ))}

                      <option value="null">Unassign</option>
                    </select>
                  </>
                ) : isUnassigned ? (
                  <button
                    className="assign-button"
                    onClick={() => handleAssignToMe(ticket.id)}
                  >
                    Assign to Me
                  </button>
                ) : isAssignedToMe ? (
                  <>
                    <div className="status-controls">
                      <button
                        className="status-open"
                        onClick={() => handleUpdateStatus(ticket.id, "Open")}
                      >
                        Open
                      </button>
                      <button
                        className="status-inprogress"
                        onClick={() =>
                          handleUpdateStatus(ticket.id, "In Progress")
                        }
                      >
                        In Progress
                      </button>
                      <button
                        className="status-resolved"
                        onClick={() =>
                          handleUpdateStatus(ticket.id, "Resolved")
                        }
                      >
                        Resolved
                      </button>
                      <button
                        className="status-closed"
                        onClick={() => handleUpdateStatus(ticket.id, "Closed")}
                      >
                        Closed
                      </button>
                    </div>

                    <select
                      value={reassignValues[ticket.id] ?? ""}
                      onChange={(e) => {
                        setReassignValues((prev) => ({ ...prev, [ticket.id]: e.target.value }));
                        handleReassign(ticket.id, e.target.value);
                      }}
                    >
                      <option value="">Reassign to...</option>
                      {admins
                        .filter((admin) => admin.id !== ticket.assignedTo)
                        .map((admin) => (
                          <option key={admin.id} value={admin.id}>
                            {admin.userName || admin.email}
                          </option>
                        ))}
                      <option value="null">Unassign</option>
                    </select>
                  </>
                ) : null}
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
