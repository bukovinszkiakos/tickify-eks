"use client";

import React, { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "../../context/AuthContext";
import "../../styles/CreateTicketPage.css";

export default function CreateTicketPage() {
  const { user } = useAuth();
  const router = useRouter();
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [priority, setPriority] = useState("Normal");
  const [image, setImage] = useState(null);
  const [error, setError] = useState("");
  const [showPreview, setShowPreview] = useState(false);
  const [previewImage, setPreviewImage] = useState(null);

  useEffect(() => {
    if (user === null) return;
    if (!user) {
      router.push("/login");
    } else if (user.isAdmin) {
      router.push("/tickets");
    }
  }, [user, router]);

  useEffect(() => {
    if (image) {
      const reader = new FileReader();
      reader.onload = (e) => setPreviewImage(e.target.result);
      reader.readAsDataURL(image);
    } else {
      setPreviewImage(null);
    }
  }, [image]);

  async function handleSubmit(e) {
    e.preventDefault();
    setError("");

    const formData = new FormData();
    formData.append("title", title);
    formData.append("description", description);
    formData.append("priority", priority);
    if (image) {
      formData.append("image", image);
    }

    try {
      const response = await fetch("/api/tickets", {
        method: "POST",
        body: formData,
        credentials: "include",
      });

      if (!response.ok) throw new Error("Failed to create ticket");

      router.push("/tickets");
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <div className="create-ticket-container">
      <div className="create-ticket-box">
        <h1>Create Ticket</h1>
        {error && <p className="error-message">{error}</p>}
        <form onSubmit={handleSubmit} encType="multipart/form-data">
          <label htmlFor="title">Title</label>
          <input
            type="text"
            id="title"
            placeholder="Short title for the issue"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            required
          />

          <label htmlFor="description">Description</label>
          <textarea
            id="description"
            placeholder="Describe the issue in detail..."
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            required
          />

          <label htmlFor="priority">Priority</label>
          <select
            id="priority"
            value={priority}
            onChange={(e) => setPriority(e.target.value)}
          >
            <option>Low</option>
            <option>Normal</option>
            <option>High</option>
          </select>

          <label htmlFor="file">Optional Image Attachment</label>
          <div className="file-input-wrapper">
            <input
              id="file"
              type="file"
              accept="image/*"
              onChange={(e) => setImage(e.target.files[0])}
            />
            {image && (
              <button
                type="button"
                className="clear-file-btn"
                onClick={() => {
                  setImage(null);
                  setPreviewImage(null);
                  document.getElementById("file").value = "";
                }}
                title="Remove selected file"
              >
                ×
              </button>
            )}
          </div>

          <div className="button-group">
            <button
              type="button"
              className="preview-btn"
              onClick={() => setShowPreview(true)}
            >
              Preview Ticket
            </button>
            <button type="submit">+ Create Ticket</button>
          </div>
        </form>
      </div>

      {showPreview && (
        <div className="preview-modal" onClick={() => setShowPreview(false)}>
          <div className="preview-content" onClick={(e) => e.stopPropagation()}>
            <h2>Ticket Preview</h2>
            <div>
              <strong>Title:</strong>
              <div className="scrollable-text">{title}</div>
            </div>

            <div>
              <strong>Description:</strong>
              <div className="scrollable-text">{description}</div>
            </div>

            <p>
              <strong>Priority:</strong> {priority}
            </p>
            {previewImage && (
              <div className="preview-image">
                <img src={previewImage} alt="Preview" />
              </div>
            )}
            <button className="close-btn" onClick={() => setShowPreview(false)}>
              Close
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
