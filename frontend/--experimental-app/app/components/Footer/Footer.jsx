"use client";
import React, { useEffect, useState } from "react";
import Link from "next/link";
import "../../styles/Footer.css";

const Footer = () => {
  const [year, setYear] = useState("");

  useEffect(() => {
    setYear(new Date().getFullYear());
  }, []);

  return (
    <footer className="footer">
      <p>© {year} Tickify. All rights reserved.</p>
      
    </footer>
  );
};

export default Footer;
