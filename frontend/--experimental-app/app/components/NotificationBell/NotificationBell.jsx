"use client";

import React, { useState, useRef, useEffect } from "react";
import { useNotifications } from "../../hooks/useNotifications";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { apiPost, apiDelete } from "../../../utils/api";
import "../../styles/NotificationBell.css";

export default function NotificationBell() {
  const { notifications, loading, setNotifications } = useNotifications();
  const [open, setOpen] = useState(false);
  const router = useRouter();
  const dropdownRef = useRef(null);

  const unreadCount = notifications.filter((n) => !n.isRead).length;

  const handleNotificationClick = async (notification) => {
  try {
    const check = await fetch(`/api/tickets/${notification.ticketId}`, {
      method: "GET",
      credentials: "include",
    });

    if (!check.ok) {
      if (check.status === 404) {
        setNotifications((prev) => prev.filter((n) => n.id !== notification.id));
        alert("❌ This ticket was deleted. Notification removed.");
        return;
      } else {
        throw new Error("Ticket check failed");
      }
    }

    await apiPost(`/api/user/notifications/${notification.id}/read`, {});
    setNotifications((prev) =>
      prev.map((n) =>
        n.id === notification.id ? { ...n, isRead: true } : n
      )
    );

    setOpen(false);
    router.push(`/tickets/${notification.ticketId}`);
  } catch (err) {
    console.error("Failed to open notification:", err);
    alert("Something went wrong. Please try again.");
  }
};


  const handleDelete = async (id) => {
    try {
      await apiDelete(`/api/user/notifications/${id}`);
      setNotifications((prev) => prev.filter((n) => n.id !== id));
    } catch (err) {
      console.error("Failed to delete notification:", err);
    }
  };

  useEffect(() => {
    const handleClickOutside = (event) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target)) {
        setOpen(false);
      }
    };

    if (open) {
      document.addEventListener("mousedown", handleClickOutside);
    }

    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
    };
  }, [open]);

  return (
    <div className="notification-bell" ref={dropdownRef}>
      <button className="bell-icon" onClick={() => setOpen(!open)}>
        🔔
        {unreadCount > 0 && (
          <span className="notification-badge">{unreadCount}</span>
        )}
      </button>

      {open && (
        <div className="notification-dropdown">
          <h4>Notifications</h4>

          {loading ? (
            <p>Loading...</p>
          ) : notifications.length === 0 ? (
            <p>No notifications</p>
          ) : (
            <ul>
              {notifications.map((n) => (
                <li
                  key={n.id}
                  className={`notification-item ${
                    n.isRead ? "read" : "unread"
                  }`}
                >
                  {n.isTicketDeleted ? (
                    <div className="notification-disabled">
                      <span className="message" title={n.message}>
                        {n.message}
                      </span>
                      <span className="notification-time">
                        {new Date(n.createdAt).toLocaleString()}
                      </span>
                    </div>
                  ) : (
                    <div
                      onClick={() => handleNotificationClick(n)}
                      className="notification-clickable"
                    >
                      <span className="message" title={n.message}>
                        {n.message}
                      </span>
                      <span className="notification-time">
                        {new Date(n.createdAt).toLocaleString()}
                      </span>
                    </div>
                  )}

                  <button
                    className="delete-notification"
                    onClick={() => handleDelete(n.id)}
                    title="Delete"
                  >
                    ❌
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
