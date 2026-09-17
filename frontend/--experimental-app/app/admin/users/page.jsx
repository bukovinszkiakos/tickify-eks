"use client";

import React, { useEffect, useState } from "react";
import { apiGet, apiDelete, apiPost } from "../../../utils/api";
import { useAuth } from "../../context/AuthContext";
import "../../styles/AdminUsersPage.css";

export default function AdminUsersPage() {
  const { user } = useAuth();

  const [users, setUsers] = useState([]);
  const [error, setError] = useState("");
  const [roleToAssign, setRoleToAssign] = useState("Admin");
  const [userIdForRole, setUserIdForRole] = useState("");
  const [isSuperAdmin, setIsSuperAdmin] = useState(false);
  const [isAdmin, setIsAdmin] = useState(false);

  useEffect(() => {
    if (user?.roles) {
      setIsSuperAdmin(user.roles.includes("SuperAdmin"));
      setIsAdmin(user.roles.includes("Admin"));
    }
  }, [user]);

  useEffect(() => {
    fetchUsers();
  }, []);

  async function fetchUsers() {
    try {
      const data = await apiGet("/api/admin/users");
      setUsers(data);
    } catch (err) {
      setError(err.message);
    }
  }

  function canDelete(targetUser) {
    if (!targetUser || !user) return false;
    if (targetUser.email === user.email) return false;

    const targetRoles = targetUser.roles || [];

    if (isSuperAdmin) return true;
    if (isAdmin && !targetRoles.includes("SuperAdmin")) return true;

    return false;
  }

  function getPrimaryRole(roles) {
    if (!roles || roles.length === 0) return "User";
    if (roles.includes("SuperAdmin")) return "SuperAdmin";
    if (roles.includes("Admin")) return "Admin";
    return "User";
  }

 async function handleDeleteUser(userId) {
  try {
    await apiDelete(`/api/admin/users/${userId}`);
    setUsers((prev) => prev.filter((u) => u.id !== userId));
    setError(""); 
  } catch (err) {
    const msg = err.message || "";
    if (msg.includes("still active tickets")) {
      setError("❌ This user cannot be deleted because they still have unresolved tickets. Please close or resolve their tickets first.");
    } else {
      setError("An unexpected error occurred. Please try again.");
    }
  }
}


  async function handleAssignRole(e) {
    e.preventDefault();

    if (!userIdForRole) {
      setError("Please select a user.");
      return;
    }

    try {
      await apiPost(`/api/admin/users/${userIdForRole}/role/${roleToAssign}`, {});
      await fetchUsers();
      alert("Role assigned!");
    } catch (err) {
      setError(err.message);
    }
  }

  if (!user) {
    return (
      <div className="admin-users-container">
        <h1>Manage Users</h1>
        <p>Loading user...</p>
      </div>
    );
  }

  return (
    <div className="admin-users-container">
      <h1>Manage Users</h1>

      {error && <p className="error-message">{error}</p>}

      <div className="user-list-wrapper">
        <ul>
          {users.map((u) => (
            <li key={u.id}>
              <div>
                <strong>{u.userName}</strong> – {u.email}
                <span className={`role-badge ${getPrimaryRole(u.roles)}`}>
                  {getPrimaryRole(u.roles)}
                </span>
              </div>
              {canDelete(u) && (
                <button onClick={() => handleDeleteUser(u.id)}>Delete</button>
              )}
            </li>
          ))}
        </ul>
      </div>

      {isSuperAdmin && (
        <>
          <hr />
          <h2>Assign Role</h2>
          <form className="assign-role-form" onSubmit={handleAssignRole}>
            <select
              value={userIdForRole}
              onChange={(e) => setUserIdForRole(e.target.value)}
              required
            >
              <option value="">Select a user...</option>
              {users
                .filter((u) => u.email !== user.email)
                .filter((u) => !u.roles?.includes("SuperAdmin"))
                .map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.userName} – {u.email}
                  </option>
                ))}
            </select>

            <select
              value={roleToAssign}
              onChange={(e) => setRoleToAssign(e.target.value)}
            >
              <option value="Admin">Admin</option>
              <option value="User">User</option>
            </select>

            <button type="submit">Assign</button>
          </form>
        </>
      )}
    </div>
  );
}
