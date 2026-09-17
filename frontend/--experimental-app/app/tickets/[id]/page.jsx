"use client";

import React, { useEffect, useState, useRef } from "react";
import { useParams, useRouter } from "next/navigation";
import { useAuth } from "../../context/AuthContext";
import { Pencil, Trash2, Save, Eye, FileImage } from "lucide-react";
import "../../styles/TicketDetailPage.css";

export default function TicketDetailPage() {
  const router = useRouter();
  const { id } = useParams();
  const { user } = useAuth();

  const [ticket, setTicket] = useState(null);
  const [error, setError] = useState("");
  const [editMode, setEditMode] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [priority, setPriority] = useState("");
  const [status, setStatus] = useState("");
  const [editImage, setEditImage] = useState(null);
  const [previewImage, setPreviewImage] = useState(null);
  const [comments, setComments] = useState([]);
  const [newComment, setNewComment] = useState("");
  const [newImage, setNewImage] = useState(null);
  const [previewChanges, setPreviewChanges] = useState(null);
  const [oldImageUrl, setOldImageUrl] = useState(null);
  const [newImageUrl, setNewImageUrl] = useState(null);
  const [textChanges, setTextChanges] = useState([]);
  const commentsTopRef = useRef(null);

  useEffect(() => {
    if (!id || id === "null") router.push("/tickets");
  }, [id, router]);

  const fetchTicketData = async () => {
    const res = await fetch(`/api/tickets/${id}`, { credentials: "include" });
    if (!res.ok) {
      if (res.status === 401) return router.push("/login");
      throw new Error("Failed to fetch ticket data");
    }
    const data = await res.json();
    setTicket(data);
    setTitle(data.title);
    setDescription(data.description);
    setPriority(data.priority);
    setStatus(data.status);
  };

  const fetchComments = async () => {
    const res = await fetch(`/api/tickets/${id}/comments`, {
      credentials: "include",
    });
    if (!res.ok) {
      if (res.status === 401) return router.push("/login");
      throw new Error("Failed to fetch comments");
    }
    const data = await res.json();
    setComments(data);
  };

  useEffect(() => {
    if (!id || id === "null") return;
    fetchTicketData().catch((err) => {
      console.error(err);
      setError("Ticket not found or deleted.");
      router.push("/tickets");
    });
    fetchComments().catch((err) => console.error(err));

    if (user?.isAdmin) {
      fetch(`/api/admin/tickets/${id}/mark-comments-read`, {
        method: "POST",
        credentials: "include",
      });
    }
  }, [id, user]);

  const handleUpdate = async (e) => {
    e.preventDefault();
    const formData = new FormData();
    formData.append("title", title);
    formData.append("description", description);
    formData.append("priority", priority);
    formData.append("status", status);
    if (editImage) formData.append("image", editImage);

    try {
      const res = await fetch(`/api/tickets/${id}`, {
        method: "PUT",
        body: formData,
        credentials: "include",
      });
      if (!res.ok) throw new Error("Failed to update ticket");
      setEditMode(false);
      setEditImage(null);
      await fetchTicketData();
      await fetchComments();
    } catch (err) {
      setError(err.message);
    }
  };

  const handleDelete = async () => {
    try {
      await fetch(`/api/tickets/${id}`, {
        method: "DELETE",
        credentials: "include",
      });
      router.push("/tickets");
    } catch (err) {
      setError(err.message);
    }
  };

  const handleAdminStatusChange = async (e) => {
    const newStatus = e.target.value;
    setStatus(newStatus);

    try {
      const res = await fetch(`/api/admin/tickets/${id}/status/${newStatus}`, {
        method: "PUT",
        credentials: "include",
      });
      if (!res.ok) throw new Error("Failed to update status");
      await fetchTicketData();
      await fetchComments();
    } catch (err) {
      setError("Failed to update status.");
    }
  };

  const handleAddComment = async (e) => {
    e.preventDefault();
    const formData = new FormData();
    formData.append("comment", newComment);
    if (newImage) formData.append("image", newImage);

    try {
      const res = await fetch(`/api/tickets/${id}/comments`, {
        method: "POST",
        body: formData,
        credentials: "include",
      });
      if (!res.ok) throw new Error("Failed to add comment");
      setNewComment("");
      setNewImage(null);
      await fetchComments();
      setTimeout(() => {
        commentsTopRef.current?.scrollIntoView({ behavior: "smooth" });
      }, 100);
    } catch (err) {
      setError("Failed to add comment. Please try again.");
    }
  };

  const handleSeeChanges = (text) => {
    setPreviewChanges(text);
    const lines = text
      .split("\n")
      .filter((line) =>
        ["Title:", "Description:", "Priority:", "Assigned To:"].some((prefix) =>
          line.startsWith(prefix)
        )
      );
    setTextChanges(lines);

    const oldMatch = text.match(/Old image: (https?:\/\/\S+)/);
    const newMatch = text.match(/New image: (https?:\/\/\S+)/);
    setOldImageUrl(oldMatch?.[1] || null);
    setNewImageUrl(newMatch?.[1] || null);
  };

  const canDelete =
    (!user?.isAdmin && user?.id === ticket?.createdBy) ||
    (user?.isAdmin && user?.id === ticket?.assignedTo) ||
    user?.roles?.includes("SuperAdmin");
    if (error) return <p className="error-message">{error}</p>;
    if (!ticket) return <p className="loading-message">Loading ticket...</p>;
  
    return (
      <div className="ticket-page-container">
        <div className="ticket-detail-card">
          <h1>🎫 Ticket Detail</h1>
          <div className="info-block">
            <strong>👤 Created by:</strong>{" "}
            <span>{ticket.createdByName || "Unknown"}</span>
          </div>
  
          <div className="ticket-info">
            <div className="info-block">
              <strong>📝 Title:</strong>
              {editMode ? (
                <input
                  className="field-input"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                />
              ) : (
                <div className="scrollable-text">{ticket.title}</div>
              )}
            </div>
  
            <div className="info-block">
              <strong>📄 Description:</strong>
              {editMode ? (
                <textarea
                  className="field-input"
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                />
              ) : (
                <div className="scrollable-text">{ticket.description}</div>
              )}
            </div>
  
            <div className="info-block">
              <strong>🚦 Priority:</strong>
              {editMode ? (
                <select
                  className="field-input"
                  value={priority}
                  onChange={(e) => setPriority(e.target.value)}
                >
                  <option>Low</option>
                  <option>Normal</option>
                  <option>High</option>
                </select>
              ) : (
                <span>{ticket.priority}</span>
              )}
            </div>
  
            <div className="info-block">
              <strong>📌 Status:</strong>
              {user?.isAdmin && user.id === ticket.assignedTo ? (
                <select
                  className="field-input"
                  value={status}
                  onChange={handleAdminStatusChange}
                >
                  <option>Open</option>
                  <option>In Progress</option>
                  <option>Resolved</option>
                  <option>Closed</option>
                </select>
              ) : (
                <span>{status}</span>
              )}
            </div>
  
            {editMode && (
              <div className="info-block">
                <strong>
                  <FileImage size={14} /> Change Screenshot:
                </strong>
                <input
                  type="file"
                  accept="image/*"
                  onChange={(e) => setEditImage(e.target.files[0])}
                />
              </div>
            )}
          </div>
  
          <div className="action-buttons">
            {!user?.isAdmin && status !== "Resolved" && status !== "Closed" && (
  <button className="edit-btn" onClick={() => setEditMode(!editMode)}>
    {editMode ? (
      <>
        <Eye size={16} /> Cancel
      </>
    ) : (
      <>
        <Pencil size={16} /> Edit Ticket
      </>
    )}
  </button>
)}

  
            {canDelete && (
              <button className="delete-btn" onClick={handleDelete}>
                <Trash2 size={16} /> Delete Ticket
              </button>
            )}
          </div>
  
          {editMode && !user?.isAdmin && (
            <form className="edit-form" onSubmit={handleUpdate}>
              <button type="submit" className="save-btn">
                <Save size={16} /> Save Changes
              </button>
            </form>
          )}
  
          {ticket.imageUrl && !editMode && (
            <div className="screenshot-section">
              <button onClick={() => setPreviewImage(ticket.imageUrl)}>
                📎 Screenshot or attachment
              </button>
            </div>
          )}
        </div>
        <div className="ticket-comments-section">
        <h2>💬 Comments</h2>
        <div className="comment-scroll">
          <ul className="comment-list">
            <div ref={commentsTopRef}></div>
            {[...comments]
              .reverse()
              .filter((c) => !c.comment.startsWith("Ticket created with image:"))
              .map((c) => (
                <li key={c.id} className="comment-item">
                  <p>
                    <strong>{c.commenter || "Unknown"}</strong>{" "}
                    <em>({new Date(c.createdAt).toLocaleString()})</em>
                  </p>
                  {c.comment.startsWith("🔄 Ticket updated:") ? (
                    <>
                      <p className="change-preview">
                        This ticket has been updated.
                      </p>
                      <button
                        className="see-changes-btn"
                        onClick={() => handleSeeChanges(c.comment)}
                      >
                        See Changes
                      </button>
                    </>
                  ) : (
                    <p>{c.comment}</p>
                  )}
                  {c.imageUrl && (
                    <button onClick={() => setPreviewImage(c.imageUrl)}>
                      📷 Screenshot
                    </button>
                  )}
                </li>
              ))}
          </ul>
        </div>

        {ticket.status !== "Resolved" && ticket.status !== "Closed" && (
          <form
            onSubmit={handleAddComment}
            className="comment-form"
            encType="multipart/form-data"
          >
            <textarea
              placeholder="Write a comment..."
              value={newComment}
              onChange={(e) => setNewComment(e.target.value)}
              required
            />
            <input
              type="file"
              accept="image/*"
              onChange={(e) => setNewImage(e.target.files[0])}
            />
            <button type="submit">Submit Comment</button>
          </form>
        )}
      </div>

      {previewImage && (
        <div
          className="preview-modal image-overlay"
          onClick={() => setPreviewImage(null)}
        >
          <img src={previewImage} alt="Preview" className="preview-full" />
        </div>
      )}

      {previewChanges && (
        <div className="preview-modal" onClick={() => setPreviewChanges(null)}>
          <div className="preview-content" onClick={(e) => e.stopPropagation()}>
            <h3>📋 Ticket Changes</h3>
            <p className="change-preview">📝 Changes made to the ticket.</p>
            {textChanges.length > 0 && <pre>{textChanges.join("\n")}</pre>}
            {oldImageUrl && oldImageUrl.startsWith("http") && (
              <button
                className="image-button"
                onClick={() => setPreviewImage(oldImageUrl)}
              >
                🖼️ Old Image
              </button>
            )}
            {newImageUrl && newImageUrl.startsWith("http") && (
              <button
                className="image-button"
                onClick={() => setPreviewImage(newImageUrl)}
              >
                🆕 New Image
              </button>
            )}
            <button
              className="close-btn"
              onClick={() => setPreviewChanges(null)}
            >
              Close
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
  